import Foundation
import Combine
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

public extension Notification.Name {
    static let firebaseCareStateDidChange = Notification.Name("firebaseCareStateDidChange")
}

/// The two apps use anonymous Firebase accounts for this demo. A random
/// pairing code joins the two anonymous accounts without asking a stroke
/// survivor to create or remember a password.
public enum FirebaseSyncRole {
    case survivor
    case caregiver
}

public enum FirebaseSyncState: Equatable {
    case notConfigured
    case signingIn
    case ready
    case connected
    case failed(String)

    public var title: String {
        switch self {
        case .notConfigured: return "Firebase is not configured"
        case .signingIn: return "Connecting securely…"
        case .ready: return "Ready to connect"
        case .connected: return "Connected to CareBridge"
        case .failed: return "Connection needs attention"
        }
    }

    public var detail: String {
        switch self {
        case .notConfigured: return "Add the Firebase configuration to this app target."
        case .signingIn: return "Signing in anonymously so no password is required."
        case .ready: return "Create or enter a pairing code to link the apps."
        case .connected: return "Updates sync through Firestore and remain available offline."
        case .failed(let message): return message
        }
    }
}

private enum FirebaseSyncError: LocalizedError {
    case notConfigured
    case missingPair
    case invalidPair
    case alreadyConnected
    case emptyPayload

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Firebase is not configured for this app target."
        case .missingPair: return "No pairing code was found."
        case .invalidPair: return "That pairing code is not valid."
        case .alreadyConnected: return "That code is already connected to another CareBridge device."
        case .emptyPayload: return "The remote update was empty."
        }
    }
}

/// Firestore transport for the shared patient/caregiver state.
///
/// SharedCareStore remains the local cache and same-device fallback. Firebase
/// is only the remote transport, so the apps still work in the simulator and
/// when a device temporarily loses connectivity.
@MainActor
public final class FirebaseSync: ObservableObject {
    private static var instance: FirebaseSync?
    private static var configuredRole: FirebaseSyncRole = .survivor

    public static var shared: FirebaseSync {
        if let instance { return instance }
        let instance = FirebaseSync(role: configuredRole)
        self.instance = instance
        return instance
    }

    /// Call once from each app's @main initializer before the first view is built.
    public static func configure(role: FirebaseSyncRole) {
        configuredRole = role
        if instance == nil { instance = FirebaseSync(role: role) }
    }

    public let role: FirebaseSyncRole
    @Published public private(set) var state: FirebaseSyncState = .notConfigured
    @Published public private(set) var pairCode: String?
    @Published public private(set) var lastSyncedAt: Date?

    private let defaults = UserDefaults.standard
    private let auth: Auth?
    private let db: Firestore?
    private var stateListener: ListenerRegistration?
    private var pairListener: ListenerRegistration?

    private var pairDefaultsKey: String {
        switch role {
        case .survivor: return "firebase.solace.pairCode"
        case .caregiver: return "firebase.carebridge.pairCode"
        }
    }

    public init(role: FirebaseSyncRole) {
        self.role = role
        self.pairCode = UserDefaults.standard.string(forKey: role == .survivor
                                                      ? "firebase.solace.pairCode"
                                                      : "firebase.carebridge.pairCode")

        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else {
            self.auth = nil
            self.db = nil
            return
        }

        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        self.auth = Auth.auth()
        self.db = Firestore.firestore()

        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.signInIfNeeded()
            if self.pairCode != nil { self.startListeners() }
        }
    }

    deinit {
        stateListener?.remove()
        pairListener?.remove()
    }

    public var isConfigured: Bool { auth != nil && db != nil }
    public var statusTitle: String { state.title }
    public var statusDetail: String { state.detail }

    public func createPairingCode() async {
        guard let db else {
            state = .notConfigured
            return
        }

        do {
            let user = try await signInIfNeeded()
            stopListeners()
            let code = makePairingCode()
            let reference = pairReference(code, db: db)
            try await setData([
                "survivorUid": user.uid,
                "caregiverUid": NSNull(),
                "createdAt": Timestamp(date: Date()),
                "updatedAt": Timestamp(date: Date())
            ], on: reference, merge: false)
            defaults.set(code, forKey: pairDefaultsKey)
            pairCode = code
            state = .ready
            startListeners()
            await publishCurrentState()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func connect(code rawCode: String) async {
        guard let db else {
            state = .notConfigured
            return
        }

        let code = normalizedCode(rawCode)
        guard !code.isEmpty else {
            state = .failed(FirebaseSyncError.invalidPair.localizedDescription)
            return
        }

        do {
            let user = try await signInIfNeeded()
            let reference = pairReference(code, db: db)
            let snapshot = try await getDocument(reference)
            guard let data = snapshot.data(),
                  let survivorUid = data["survivorUid"] as? String,
                  !survivorUid.isEmpty else {
                throw FirebaseSyncError.invalidPair
            }

            if let existing = data["caregiverUid"] as? String,
               !existing.isEmpty,
               existing != user.uid {
                throw FirebaseSyncError.alreadyConnected
            }

            stopListeners()
            try await updateData([
                "caregiverUid": user.uid,
                "updatedAt": Timestamp(date: Date())
            ], on: reference)
            defaults.set(code, forKey: pairDefaultsKey)
            pairCode = code
            state = .connected
            startListeners()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func disconnect() {
        stopListeners()
        defaults.removeObject(forKey: pairDefaultsKey)
        pairCode = nil
        state = isConfigured ? .ready : .notConfigured
    }

    /// Push the current local cache. This is intentionally callable by either
    /// app: CareBridge edits (approval and ordering) should travel back to Solace.
    public func publishCurrentState() async {
        guard let db, let pairCode else { return }

        do {
            _ = try await signInIfNeeded()
            let payload = FirebaseCarePayload(
                snapshot: SharedCareStore.readSnapshot(),
                feed: SharedCareStore.readFeed(),
                carePlanActivities: SharedCareStore.readCarePlanActivities(),
                curatedActivities: SharedCareStore.readCuratedActivities(),
                ssiPlan: SharedCareStore.readSSIPlan(),
                updatedAt: Date()
            )
            let data = try JSONEncoder().encode(payload)
            guard let json = String(data: data, encoding: .utf8), !json.isEmpty else {
                throw FirebaseSyncError.emptyPayload
            }
            let reference = stateReference(pairCode, db: db)
            try await setData([
                "payload": json,
                "updatedAt": Timestamp(date: payload.updatedAt)
            ], on: reference, merge: true)
            lastSyncedAt = payload.updatedAt
            state = .connected
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func signInIfNeeded() async throws -> User {
        guard let auth else { throw FirebaseSyncError.notConfigured }
        if let current = auth.currentUser {
            if state != .connected { state = .ready }
            return current
        }

        state = .signingIn
        return try await withCheckedThrowingContinuation { continuation in
            auth.signInAnonymously { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let user = result?.user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: FirebaseSyncError.notConfigured)
                }
            }
        }
    }

    private func startListeners() {
        guard let db, let pairCode else { return }
        stopListeners()

        let pair = pairReference(pairCode, db: db)
        pairListener = pair.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.state = .failed(error.localizedDescription)
                    return
                }
                guard let data = snapshot?.data() else { return }
                let connected = (data["caregiverUid"] as? String)?.isEmpty == false
                if self.role == .survivor {
                    self.state = connected ? .connected : .ready
                }
            }
        }

        let stateReference = stateReference(pairCode, db: db)
        stateListener = stateReference.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.state = .failed(error.localizedDescription)
                    return
                }
                guard let json = snapshot?.data()?["payload"] as? String else { return }
                self.applyRemotePayload(json)
            }
        }
    }

    private func applyRemotePayload(_ json: String) {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(FirebaseCarePayload.self, from: data) else { return }

        // The caregiver app receives the complete survivor state. The survivor
        // app only accepts caregiver-owned plan changes, avoiding stale remote
        // check-ins from overwriting a newer local check-in.
        if role == .caregiver {
            if let snapshot = payload.snapshot { SharedCareStore.writeSnapshot(snapshot) }
            SharedCareStore.writeFeed(payload.feed)
            SharedCareStore.writeCarePlanActivities(payload.carePlanActivities)
            if payload.curatedActivities.isEmpty {
                SharedCareStore.clearCuratedActivities()
            } else {
                SharedCareStore.writeCuratedActivities(payload.curatedActivities)
            }
            if let ssiPlan = payload.ssiPlan {
                SharedCareStore.writeSSIPlan(ssiPlan)
            } else {
                SharedCareStore.clearSSIPlan()
            }
        } else {
            SharedCareStore.writeCarePlanActivities(payload.carePlanActivities)
            if payload.curatedActivities.isEmpty {
                SharedCareStore.clearCuratedActivities()
            } else {
                SharedCareStore.writeCuratedActivities(payload.curatedActivities)
            }
        }

        lastSyncedAt = payload.updatedAt
        state = .connected
        NotificationCenter.default.post(name: .firebaseCareStateDidChange, object: self)
    }

    private func stopListeners() {
        stateListener?.remove()
        pairListener?.remove()
        stateListener = nil
        pairListener = nil
    }

    private func pairReference(_ code: String, db: Firestore) -> DocumentReference {
        db.collection("pairs").document(code)
    }

    private func stateReference(_ code: String, db: Firestore) -> DocumentReference {
        pairReference(code, db: db).collection("state").document("current")
    }

    private func getDocument(_ reference: DocumentReference) async throws -> DocumentSnapshot {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DocumentSnapshot, Error>) in
            reference.getDocument { snapshot, error in
                if let error { continuation.resume(throwing: error) }
                else if let snapshot { continuation.resume(returning: snapshot) }
                else { continuation.resume(throwing: FirebaseSyncError.invalidPair) }
            }
        }
    }

    private func setData(_ data: [String: Any], on reference: DocumentReference,
                         merge: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.setData(data, merge: merge) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    private func updateData(_ data: [String: Any], on reference: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.updateData(data) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    private func makePairingCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let suffix = String((0..<6).compactMap { _ in alphabet.randomElement() })
        return "SOLACE-\(suffix)"
    }

    private func normalizedCode(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

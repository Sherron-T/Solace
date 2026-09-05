import SwiftUI

/// Caregiver-side pairing control. Enter the code shown in Solace, then leave
/// this screen open to receive live check-ins and publish approved care plans.
struct FirebaseConnectionCard: View {
    @ObservedObject private var firebase = FirebaseSync.shared
    @State private var code = ""
    @State private var isConnecting = false
    @State private var isRetrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CareToken.primary)
                Text(connectionTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CareToken.heading)
                Spacer()
                if firebase.state == .connected {
                    Circle().fill(CareToken.sage).frame(width: 9, height: 9)
                }
            }

            if let lastSyncedAt = firebase.lastSyncedAt {
                Label("Last synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))",
                      systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(CareToken.muted)
            }

            if firebase.hasPendingChanges {
                Label("Changes waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color(careHex: "8a6c3b"))
            }

            Text(connectionDetail)
                .font(.system(size: 12.5))
                .foregroundStyle(CareToken.muted)
                .fixedSize(horizontal: false, vertical: true)

            if firebase.state == .connected, let pairCode = firebase.pairCode {
                HStack {
                    Text(pairCode)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(CareToken.primary)
                    Spacer()
                    Button("Disconnect") { firebase.disconnect() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CareToken.muted)
                }
            } else {
                HStack(spacing: 8) {
                    TextField("SOLACE-ABC123", text: $code)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .frame(minHeight: 45)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(CareToken.border, lineWidth: 1)
                        )

                    Button {
                        isConnecting = true
                        Task {
                            await firebase.connect(code: code)
                            await MainActor.run { isConnecting = false }
                        }
                    } label: {
                        Group {
                            if isConnecting { ProgressView().tint(CareToken.onPrimary) }
                            else { Text("Connect") }
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CareToken.onPrimary)
                        .frame(minWidth: 82, minHeight: 45)
                        .background(CareToken.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isConnecting || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !firebase.isConfigured)
                }
            }

            if case .failed(let message) = firebase.state {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(careHex: "a8543a"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if firebase.pairCode != nil && firebase.state != .connected {
                Button {
                    isRetrying = true
                    Task {
                        await firebase.retryConnection()
                        await MainActor.run { isRetrying = false }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isRetrying { ProgressView().tint(CareToken.primary) }
                        Text("Refresh connection")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(CareToken.primary)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(CareToken.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRetrying || !firebase.isConfigured)
            }
        }
        .padding(15)
        .background(CareToken.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(CareToken.border, lineWidth: 1)
        )
        .onAppear {
            if let saved = firebase.pairCode { code = saved }
        }
    }

    private var iconName: String {
        switch firebase.state {
        case .connected: return "checkmark.icloud.fill"
        case .offline: return "icloud.slash"
        case .failed: return "exclamationmark.icloud.fill"
        case .signingIn: return "arrow.triangle.2.circlepath.icloud"
        default: return "link"
        }
    }

    private var connectionTitle: String {
        switch firebase.state {
        case .connected: return "Connected to Solace"
        case .offline: return "Offline — saved locally"
        case .failed: return "Connection needs attention"
        default: return "Connect to Solace"
        }
    }

    private var connectionDetail: String {
        switch firebase.state {
        case .connected: return "Live updates are syncing between the two devices."
        case .offline: return "No internet connection. Local care notes remain available and will sync when you reconnect."
        case .failed(let message): return message
        default: return "Enter the pairing code shown in the Solace app on the survivor's device."
        }
    }
}

import SwiftUI

/// Patient-side pairing control. The survivor creates a short code once, then
/// the caregiver enters that code on the other device.
struct FirebaseConnectionCard: View {
    @ObservedObject private var firebase = FirebaseSync.shared
    @State private var isCreating = false
    @State private var isRetrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text("Connect CareBridge")
                    .font(.ui(17, .semibold))
                    .foregroundStyle(Token.heading2)
                Spacer(minLength: 0)
                Text(firebase.statusTitle)
                    .font(.ui(11, .semibold))
                    .foregroundStyle(iconColor)
                    .multilineTextAlignment(.trailing)
            }

            Text(firebase.statusDetail)
                .font(.ui(13))
                .foregroundStyle(Token.muted2)
                .fixedSize(horizontal: false, vertical: true)

            if let lastSyncedAt = firebase.lastSyncedAt {
                Label("Last synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))",
                      systemImage: "clock.arrow.circlepath")
                    .font(.ui(12.5, .medium))
                    .foregroundStyle(Token.muted)
            }

            if let code = firebase.pairCode {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PAIRING CODE")
                        .font(.ui(10, .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Token.muted2)
                    Text(code)
                        .font(.system(size: 25, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(Token.primary)
                }
                .padding(.vertical, 3)
            }

            if case .failed(let message) = firebase.state {
                Text(message)
                    .font(.ui(12.5))
                    .foregroundStyle(Token.urgent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                isCreating = true
                Task {
                    await firebase.createPairingCode()
                    await MainActor.run { isCreating = false }
                }
            } label: {
                HStack(spacing: 8) {
                    if isCreating { ProgressView().tint(Token.onPrimary) }
                    Text(firebase.pairCode == nil ? "Create pairing code" : "Create a new code")
                        .font(.ui(15, .semibold))
                }
                .foregroundStyle(Token.onPrimary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Token.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .disabled(isCreating || !firebase.isConfigured)

            if firebase.pairCode != nil {
                Button {
                    isRetrying = true
                    Task {
                        await firebase.retryConnection()
                        await MainActor.run { isRetrying = false }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isRetrying { ProgressView().tint(Token.body) }
                        Text("Refresh connection")
                            .font(.ui(14, .semibold))
                    }
                    .foregroundStyle(Token.body)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Token.borderOutline, lineWidth: 1)
                    )
                }
                .buttonStyle(PressableStyle())
                .disabled(isRetrying || !firebase.isConfigured)
                .accessibilityHint("Reconnects without changing the pairing code.")
            }
        }
        .padding(16)
        .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Token.borderCard, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var iconName: String {
        switch firebase.state {
        case .connected: return "checkmark.icloud.fill"
        case .failed: return "exclamationmark.icloud.fill"
        case .signingIn: return "arrow.triangle.2.circlepath.icloud"
        default: return "link"
        }
    }

    private var iconColor: Color {
        switch firebase.state {
        case .failed: return Token.urgent
        case .connected: return Token.primary
        default: return Token.body
        }
    }
}

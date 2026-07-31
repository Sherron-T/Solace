import SwiftUI

/// Patient-side pairing control. The survivor creates a short code once, then
/// the caregiver enters that code on the other device.
struct FirebaseConnectionCard: View {
    @ObservedObject private var firebase = FirebaseSync.shared
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: firebase.state == .connected ? "checkmark.icloud.fill" : "link")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Token.primary)
                Text("Connect CareBridge")
                    .font(.ui(17, .semibold))
                    .foregroundStyle(Token.heading2)
            }

            Text(firebase.state == .connected
                 ? "CareBridge is connected on another device. Updates will sync automatically."
                 : "Create a code for the caregiver app. Your data stays on this device until you choose to connect.")
                .font(.ui(13))
                .foregroundStyle(Token.muted2)
                .fixedSize(horizontal: false, vertical: true)

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
        }
        .padding(16)
        .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Token.borderCard, lineWidth: 1)
        )
    }
}

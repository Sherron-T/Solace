import SwiftUI

/// Caregiver-side pairing control. Enter the code shown in Solace, then leave
/// this screen open to receive live check-ins and publish approved care plans.
struct FirebaseConnectionCard: View {
    @ObservedObject private var firebase = FirebaseSync.shared
    @State private var code = ""
    @State private var isConnecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: firebase.state == .connected ? "checkmark.icloud.fill" : "link")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CareToken.primary)
                Text(firebase.state == .connected ? "Connected to Solace" : "Connect to Solace")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CareToken.heading)
                Spacer()
                if firebase.state == .connected {
                    Circle().fill(CareToken.sage).frame(width: 9, height: 9)
                }
            }

            Text(firebase.state == .connected
                 ? "Live updates are syncing between the two devices."
                 : "Enter the pairing code shown in the Solace app on the survivor's device.")
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
}

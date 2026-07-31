import SwiftUI

@main
struct SolaceCareApp: App {
    init() {
        SolaceFonts.register()
        FirebaseSync.configure(role: .caregiver)
    }

    var body: some Scene {
        WindowGroup {
            CareDashboardView()
                .preferredColorScheme(.light)
        }
    }
}

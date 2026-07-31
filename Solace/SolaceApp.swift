import SwiftUI

@main
struct SolaceApp: App {
    @StateObject private var model: AppModel
    @StateObject private var narrator: Narrator
    @StateObject private var handsFree: HandsFreeController

    init() {
        SolaceFonts.register()   // before any view builds a Font
        FirebaseSync.configure(role: .survivor)
        NotificationPresenter.shared.install()
        let narrator = Narrator()
        _model = StateObject(wrappedValue: AppModel())
        _narrator = StateObject(wrappedValue: narrator)
        _handsFree = StateObject(wrappedValue: HandsFreeController(
            speech: SpeechManager(),
            narrator: narrator
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.bridge)
                .environmentObject(narrator)
                .environmentObject(handsFree)
                .preferredColorScheme(.light)   // the palette is pale-light by design
        }
    }
}

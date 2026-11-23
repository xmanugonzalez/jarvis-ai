import SwiftUI

@main
@MainActor
struct JarvisAIApp: App {
    @StateObject private var model = AssistantViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { model.foregrounded() }
                    if phase == .background { model.backgrounded() }
                }
        }
    }
}

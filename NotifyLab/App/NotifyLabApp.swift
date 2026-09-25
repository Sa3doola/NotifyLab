import SwiftUI

@main
struct NotifyLabApp: App {
    // Push and PushKit callbacks still arrive on an app delegate, even in a SwiftUI app.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            let model = appDelegate.model
            RootView()
                .environment(model.navigation)
                .environment(model.permission)
                .environment(model.habits)
                .environment(model.orders)
                .environment(model.sync)
                .environment(model.tokens)
                .environment(model.voip)
                .tint(.notifyRed)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.didBecomeActive() }
                    }
                }
        }
    }
}

import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    let model = AppModel()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 1. Set the delegate before launch finishes, or the tap that launched the app is lost.
        UNUserNotificationCenter.current().delegate = model.router

        // 2. Register buttons (categories) before any notification can arrive.
        NotificationCategories.register()

        // 3. Ask for the APNs token on EVERY launch. This needs no permission,
        //    and it's how we notice a token that changed since last time.
        application.registerForRemoteNotifications()

        // 4. VoIP pushes use their own token, delivered through PushKit.
        model.voip.start()

        // 5. Optional: FCM. Does nothing until the Firebase package + plist are added.
        FirebaseBridge.shared.configure(tokens: model.tokens)
        return true
    }

    // MARK: - APNs token

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        model.tokens.didReceiveAPNsToken(deviceToken)
        FirebaseBridge.shared.setAPNsToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Most common cause: the Push Notifications capability (aps-environment) is missing.
        model.tokens.didFailToRegister(error)
    }

    // MARK: - Silent push (content-available: 1)

    /// Runs in the background for ~30 s. Not called if the user force-quit the app.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await model.sync.handleSilentPush(userInfo)
    }
}

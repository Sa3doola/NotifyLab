import Foundation

// FCM is optional. The app builds and runs without it.
// project.yml already links the FirebaseMessaging package. To turn FCM on (Part 3),
// put your GoogleService-Info.plist in secrets/ and build again: a build step in
// project.yml copies it into the app. Without it, configure() logs a message and FCM stays off.

#if canImport(FirebaseCore) && canImport(FirebaseMessaging)
import FirebaseCore
import FirebaseMessaging

@MainActor
final class FirebaseBridge: NSObject {
    static let shared = FirebaseBridge()
    private weak var tokens: PushTokenStore?

    var isAvailable: Bool { FirebaseApp.app() != nil }

    func configure(tokens: PushTokenStore) {
        // FirebaseApp.configure() crashes without the plist, so check first.
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            EventLog.add("Firebase added, but GoogleService-Info.plist is missing", source: "app")
            return
        }
        self.tokens = tokens
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
    }

    /// Info.plist sets FirebaseAppDelegateProxyEnabled = NO (no swizzling),
    /// so we hand the APNs token to FCM ourselves. FCM maps it to an FCM token.
    func setAPNsToken(_ token: Data) {
        guard isAvailable else { return }
        Messaging.messaging().apnsToken = token
    }
}

extension FirebaseBridge: MessagingDelegate {
    /// Called on launch and whenever the FCM token changes (reinstall, restore, new APNs token…).
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            self.tokens?.didReceiveFCMToken(fcmToken)
        }
    }
}

#else

@MainActor
final class FirebaseBridge {
    static let shared = FirebaseBridge()
    let isAvailable = false

    func configure(tokens: PushTokenStore) {
        EventLog.add("FCM is off: add the FirebaseMessaging package to turn it on", source: "app")
    }

    func setAPNsToken(_ token: Data) {}
}

#endif

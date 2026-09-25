import UIKit
import UserNotifications

/// Asking for permission, and reading what the user actually allowed.
@MainActor @Observable
final class NotificationPermission {
    struct Row: Identifiable, Hashable {
        let id: String
        let value: String
    }

    private(set) var status: UNAuthorizationStatus = .notDetermined
    private(set) var rows: [Row] = []
    private(set) var lowPowerMode = false
    private(set) var backgroundRefresh = "Unknown"

    private let center = UNUserNotificationCenter.current()

    /// Full permission. iOS shows the prompt only the first time; later calls return the saved answer.
    @discardableResult
    func requestFull() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refresh()
        return granted
    }

    /// Provisional permission (iOS 12+): no prompt. Notifications arrive quietly in
    /// Notification Center with "Keep" / "Turn Off" buttons, so the user decides later.
    func requestProvisional() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])
        await refresh()
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Settings can change in the Settings app at any time, so read them every time we become active.
    func refresh() async {
        let settings = await center.notificationSettings()
        status = settings.authorizationStatus
        rows = [
            Row(id: "Authorization", value: settings.authorizationStatus.label),
            Row(id: "Alerts", value: settings.alertSetting.label),
            Row(id: "Sounds", value: settings.soundSetting.label),
            Row(id: "Badges", value: settings.badgeSetting.label),
            Row(id: "Lock Screen", value: settings.lockScreenSetting.label),
            Row(id: "Notification Center", value: settings.notificationCenterSetting.label),
            Row(id: "Banner style", value: settings.alertStyle.label),
            Row(id: "Show previews", value: settings.showPreviewsSetting.label),
            Row(id: "Time Sensitive", value: settings.timeSensitiveSetting.label),
            Row(id: "Critical Alerts", value: settings.criticalAlertSetting.label),
            Row(id: "Scheduled Summary", value: settings.scheduledDeliverySetting.label),
        ]
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        backgroundRefresh = switch UIApplication.shared.backgroundRefreshStatus {
        case .available: "On"
        case .denied: "Off (silent pushes won't wake the app)"
        case .restricted: "Restricted"
        @unknown default: "Unknown"
        }
    }
}

extension UNAuthorizationStatus {
    var label: String {
        switch self {
        case .notDetermined: "Not asked yet"
        case .denied: "Denied"
        case .authorized: "Allowed"
        case .provisional: "Provisional (quiet)"
        case .ephemeral: "Ephemeral (App Clip)"
        @unknown default: "Unknown"
        }
    }
}

extension UNNotificationSetting {
    var label: String {
        switch self {
        case .notSupported: "Not supported"
        case .disabled: "Off"
        case .enabled: "On"
        @unknown default: "Unknown"
        }
    }
}

extension UNAlertStyle {
    var label: String {
        switch self {
        case .none: "None"
        case .banner: "Temporary banner"
        case .alert: "Persistent banner"
        @unknown default: "Unknown"
        }
    }
}

extension UNShowPreviewsSetting {
    var label: String {
        switch self {
        case .always: "Always"
        case .whenAuthenticated: "When unlocked"
        case .never: "Never"
        @unknown default: "Unknown"
        }
    }
}

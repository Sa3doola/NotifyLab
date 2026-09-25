import SwiftUI
import UserNotifications

extension Color {
    static let notifyRed = Color(red: 0.83, green: 0.22, blue: 0.17)
}

enum AppTab: Hashable {
    case status, habits, orders, sync, calls
}

/// Where the UI should be. The notification router writes here when a tap needs to open a screen.
@MainActor @Observable
final class Navigation {
    var tab: AppTab = .status
    var highlightedOrderID: String?
}

/// Owns one instance of every feature object. Created by the AppDelegate,
/// handed to SwiftUI through the environment.
@MainActor
final class AppModel {
    let navigation = Navigation()
    let permission = NotificationPermission()
    let habits = HabitScheduler()
    let orders = OrderStore()
    let sync = SyncStore()
    let tokens = PushTokenStore()
    let voip: VoIPService
    let router: NotificationRouter

    init() {
        voip = VoIPService(tokens: tokens)
        router = NotificationRouter(navigation: navigation, habits: habits, orders: orders)
    }

    func didBecomeActive() async {
        await permission.refresh()
        await habits.replan()          // rolling window: top up reminders every time we run
        orders.reload()                // the Service Extension may have updated an order
        sync.reload()
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }
}

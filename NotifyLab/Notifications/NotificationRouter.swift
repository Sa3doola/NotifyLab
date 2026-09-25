import UserNotifications

/// A Sendable copy of what we need from a notification.
/// `UNNotification` and its `userInfo` are not Sendable, so we copy the values out
/// before hopping to the main actor.
struct NotificationEvent: Sendable {
    let requestID: String
    let categoryID: String
    let actionID: String
    let title: String
    let habitID: UUID?
    let order: OrderUpdate?
    let typedText: String?

    init(_ request: UNNotificationRequest,
         actionID: String = UNNotificationDefaultActionIdentifier,
         typedText: String? = nil) {
        let content = request.content
        requestID = request.identifier
        categoryID = content.categoryIdentifier
        self.actionID = actionID
        title = content.title
        habitID = (content.userInfo[PayloadKey.habitID] as? String).flatMap(UUID.init(uuidString:))
        order = OrderUpdate(userInfo: content.userInfo)
        self.typedText = typedText
    }
}

/// The UNUserNotificationCenter delegate: decides what shows in the foreground,
/// and what happens when the user taps a notification or one of its buttons.
@MainActor
final class NotificationRouter: NSObject {
    private let navigation: Navigation
    private let habits: HabitScheduler
    private let orders: OrderStore

    init(navigation: Navigation, habits: HabitScheduler, orders: OrderStore) {
        self.navigation = navigation
        self.habits = habits
        self.orders = orders
    }

    /// App is open and a notification arrives. Without this, iOS shows nothing.
    func presentInForeground(_ event: NotificationEvent) -> UNNotificationPresentationOptions {
        EventLog.add("Arrived in foreground: \(event.title)", source: "app")
        if let order = event.order {
            orders.apply(order)          // update the screen in place, too
        }
        return [.banner, .list, .sound, .badge]
    }

    /// The user tapped the notification, a button, or dismissed it.
    func handle(_ event: NotificationEvent) async {
        switch event.actionID {
        case ActionID.habitDone:
            guard let id = event.habitID else { return }
            await habits.markDone(id)
            EventLog.add("Habit done from notification", source: "app")

        case ActionID.habitSnooze:
            guard let id = event.habitID else { return }
            await habits.snooze(id)
            EventLog.add("Habit snoozed for 10 min", source: "app")

        case ActionID.habitNote:
            EventLog.add("Habit note: \(event.typedText ?? "")", source: "app")

        case ActionID.orderContact:
            EventLog.add("Call driver (forwarded to app)", source: "app")

        case ActionID.messageReply:
            EventLog.add("Reply to driver: \(event.typedText ?? "")", source: "app")

        case UNNotificationDismissActionIdentifier:
            EventLog.add("Dismissed: \(event.title)", source: "app")

        default:
            // Plain tap, or "Track order": deep-link to the right screen.
            if let order = event.order {
                orders.apply(order)
                navigation.highlightedOrderID = order.orderID
                navigation.tab = .orders
            } else if event.categoryID == CategoryID.habit {
                navigation.tab = .habits
            } else if event.categoryID == CategoryID.message {
                navigation.tab = .orders
            }
            EventLog.add("Opened from notification: \(event.title)", source: "app")
        }
    }
}

// iOS wants its hidden completion handler called on the MAIN thread.
// With `async` delegate methods, Swift calls that handler for you, from whatever
// executor the method finishes on. A `nonisolated async` method finishes on a
// background thread → "Call must be made on main thread" → crash.
// A main-actor-isolated conformance makes both methods finish on the main actor.
extension NotificationRouter: @MainActor UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        presentInForeground(NotificationEvent(notification.request))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let typed = (response as? UNTextInputNotificationResponse)?.userText
        await handle(NotificationEvent(response.notification.request,
                                       actionID: response.actionIdentifier,
                                       typedText: typed))
    }
}

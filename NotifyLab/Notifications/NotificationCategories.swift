import UserNotifications

/// Categories are the buttons under a notification. A payload picks one with `aps.category`,
/// a local notification with `content.categoryIdentifier`.
enum NotificationCategories {
    static func register() {
        // Habit reminder: Done, Snooze, or type a note, all without opening the app.
        let done = UNNotificationAction(
            identifier: ActionID.habitDone,
            title: "Done",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "checkmark.circle")
        )
        let snooze = UNNotificationAction(
            identifier: ActionID.habitSnooze,
            title: "Snooze 10 min",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "clock.arrow.circlepath")
        )
        let note = UNTextInputNotificationAction(
            identifier: ActionID.habitNote,
            title: "Add a note",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "square.and.pencil"),
            textInputButtonTitle: "Save",
            textInputPlaceholder: "How did it go?"
        )
        let habit = UNNotificationCategory(
            identifier: CategoryID.habit,
            actions: [done, snooze, note],
            intentIdentifiers: [],
            options: [.customDismissAction])   // also tell us when the user swipes it away

        // Order update: "Track" opens the app (.foreground), "Call driver" is handled
        // by the Content Extension without opening the app.
        let track = UNNotificationAction(
            identifier: ActionID.orderTrack,
            title: "Track order",
            options: [.foreground],
            icon: UNNotificationActionIcon(systemImageName: "map")
        )
        let contact = UNNotificationAction(
            identifier: ActionID.orderContact,
            title: "Call driver",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "phone")
        )
        let order = UNNotificationCategory(
            identifier: CategoryID.order,
            actions: [track, contact],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Order update",
            options: []
        )

        // Chat message from the driver: reply without opening the app.
        // The sender's photo comes from the Service Extension (communication notification).
        let reply = UNTextInputNotificationAction(
            identifier: ActionID.messageReply,
            title: "Reply",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "arrowshape.turn.up.left"),
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Message"
        )
        let message = UNNotificationCategory(
            identifier: CategoryID.message,
            actions: [reply],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Message",
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([habit, order, message])
    }
}

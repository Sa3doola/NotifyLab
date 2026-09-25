import Foundation

/// Compiled into the app AND both extensions, so every target agrees on the same strings.
/// The server must use the same values in its payloads.

enum AppGroup {
    /// Comes from APP_GROUP_ID in project.yml, via each target's Info.plist,
    /// so the app and both extensions always agree on the same group.
    static let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}

/// Custom keys that sit next to `aps` in a push payload.
enum PayloadKey {
    static let orderID = "orderId"
    static let status = "status"
    static let eta = "eta"
    static let imageURL = "image"
    static let habitID = "habitId"
    static let reason = "reason"      // silent push: why we were woken
    static let caller = "caller"      // VoIP push: who is calling
    static let sender = "sender"      // chat message: {"id", "name", "avatar"}
    static let conversationID = "conversationId"
}

/// `aps.category` on the server == `categoryIdentifier` on the device.
enum CategoryID {
    static let habit = "HABIT"
    static let order = "ORDER"
    static let message = "MESSAGE"
}

enum ActionID {
    static let habitDone = "HABIT_DONE"
    static let habitSnooze = "HABIT_SNOOZE"
    static let habitNote = "HABIT_NOTE"
    static let orderTrack = "ORDER_TRACK"
    static let orderContact = "ORDER_CONTACT"
    static let messageReply = "MESSAGE_REPLY"
}

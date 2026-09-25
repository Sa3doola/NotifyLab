import Foundation

/// A tiny log in the App Group container. The app and both extensions write to it,
/// so the Status tab can prove which process handled a notification and when.
struct LogEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    let date: Date
    let source: String   // "app", "service", "content", "voip"
    let message: String
}

enum EventLog {
    private static let key = "eventLog.v1"
    private static let limit = 100

    static func add(_ message: String, source: String) {
        var entries = all()
        entries.insert(LogEntry(date: .now, source: source, message: message), at: 0)
        save(Array(entries.prefix(limit)))
    }

    static func all() -> [LogEntry] {
        guard let data = AppGroup.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([LogEntry].self, from: data)) ?? []
    }

    static func clear() { save([]) }

    private static func save(_ entries: [LogEntry]) {
        AppGroup.defaults.set(try? JSONEncoder().encode(entries), forKey: key)
    }
}

// MARK: - Orders

enum OrderStatus: String, Codable, CaseIterable, Sendable {
    case placed, packed, shipped, outForDelivery = "out_for_delivery", delivered

    var title: String {
        switch self {
        case .placed: "Order placed"
        case .packed: "Packed"
        case .shipped: "Shipped"
        case .outForDelivery: "Out for delivery"
        case .delivered: "Delivered"
        }
    }

    var symbol: String {
        switch self {
        case .placed: "bag"
        case .packed: "shippingbox"
        case .shipped: "airplane"
        case .outForDelivery: "box.truck"
        case .delivered: "checkmark.seal"
        }
    }
}

/// What an order push carries next to `aps`. Parsed from `userInfo`, which is not Sendable,
/// into a plain struct that is.
struct OrderUpdate: Codable, Hashable, Sendable {
    let orderID: String
    let status: OrderStatus
    let eta: String?
    let imageURL: URL?

    init?(userInfo: [AnyHashable: Any]) {
        guard let id = userInfo[PayloadKey.orderID] as? String,
              let raw = userInfo[PayloadKey.status] as? String,
              let status = OrderStatus(rawValue: raw) else { return nil }
        orderID = id
        self.status = status
        eta = userInfo[PayloadKey.eta] as? String
        imageURL = (userInfo[PayloadKey.imageURL] as? String).flatMap(URL.init(string:))
    }

    init(orderID: String, status: OrderStatus, eta: String?, imageURL: URL? = nil) {
        self.orderID = orderID
        self.status = status
        self.eta = eta
        self.imageURL = imageURL
    }
}

struct OrderEvent: Codable, Hashable, Sendable {
    let status: OrderStatus
    let date: Date
}

/// Order timelines live in the App Group, so the Service Extension can update an order
/// before the user even opens the app.
enum SharedOrders {
    private static let key = "orders.v1"

    static func timelines() -> [String: [OrderEvent]] {
        guard let data = AppGroup.defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: [OrderEvent]].self, from: data)) ?? [:]
    }

    static func apply(_ update: OrderUpdate) {
        var all = timelines()
        var events = all[update.orderID] ?? []
        if !events.contains(where: { $0.status == update.status }) {
            events.append(OrderEvent(status: update.status, date: .now))
        }
        all[update.orderID] = events
        AppGroup.defaults.set(try? JSONEncoder().encode(all), forKey: key)
    }

    static func reset(orderID: String) {
        var all = timelines()
        all[orderID] = [OrderEvent(status: .placed, date: .now)]
        AppGroup.defaults.set(try? JSONEncoder().encode(all), forKey: key)
    }
}

// MARK: - Messages

/// A chat message push: who sent it and which conversation it belongs to.
/// The Service Extension turns it into a communication notification.
struct ChatMessage: Sendable {
    let senderID: String
    let senderName: String
    let avatarURL: URL?
    let conversationID: String
    let text: String

    init?(userInfo: [AnyHashable: Any], text: String) {
        guard let sender = userInfo[PayloadKey.sender] as? [String: Any],
              let id = sender["id"] as? String,
              let name = sender["name"] as? String,
              let conversation = userInfo[PayloadKey.conversationID] as? String else { return nil }
        senderID = id
        senderName = name
        avatarURL = (sender["avatar"] as? String).flatMap(URL.init(string:))
        conversationID = conversation
        self.text = text
    }
}

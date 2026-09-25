import UIKit
import UserNotifications

/// The demo order's timeline. It lives in the App Group, so the Service Extension
/// can update it while the app isn't running.
@MainActor @Observable
final class OrderStore {
    static let demoOrderID = "1042"
    private(set) var timeline: [OrderEvent] = []

    init() { reload() }

    var current: OrderStatus { timeline.last?.status ?? .placed }

    func reload() {
        let saved = SharedOrders.timelines()[Self.demoOrderID] ?? []
        if saved.isEmpty {
            SharedOrders.reset(orderID: Self.demoOrderID)
            timeline = SharedOrders.timelines()[Self.demoOrderID] ?? []
        } else {
            timeline = saved
        }
    }

    func apply(_ update: OrderUpdate) {
        SharedOrders.apply(update)
        reload()
    }

    func reset() {
        SharedOrders.reset(orderID: Self.demoOrderID)
        reload()
    }

    /// Sends the same content a push would carry, as a LOCAL notification, so you can try
    /// the category buttons and the Content Extension (long-press) without a server.
    /// (The Service Extension only runs for remote pushes.)
    func previewLocally(_ status: OrderStatus, after seconds: TimeInterval = 3) async {
        let content = UNMutableNotificationContent()
        content.title = "Order #\(Self.demoOrderID): \(status.title)"
        content.body = status == .delivered ? "Enjoy! Tap to rate your delivery." : "Arriving today, 2–4 pm."
        content.sound = .default
        content.categoryIdentifier = CategoryID.order
        content.threadIdentifier = "order-\(Self.demoOrderID)"
        content.interruptionLevel = status == .outForDelivery ? .timeSensitive : .active
        content.userInfo = [
            PayloadKey.orderID: Self.demoOrderID,
            PayloadKey.status: status.rawValue,
            PayloadKey.eta: "2–4 pm",
        ]
        if let attachment = Self.makeImageAttachment(for: status) {
            content.attachments = [attachment]
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        // Same identifier for every update of this order: a newer one replaces the older one.
        let request = UNNotificationRequest(identifier: "order-\(Self.demoOrderID)", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Local notifications can carry attachments too. The file must be on disk; iOS moves it.
    private static func makeImageAttachment(for status: OrderStatus) -> UNNotificationAttachment? {
        let size = CGSize(width: 600, height: 400)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.83, green: 0.22, blue: 0.17, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let config = UIImage.SymbolConfiguration(pointSize: 170, weight: .semibold)
            if let symbol = UIImage(systemName: status.symbol, withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                symbol.draw(at: CGPoint(x: (size.width - symbol.size.width) / 2,
                                        y: (size.height - symbol.size.height) / 2))
            }
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "order-\(UUID().uuidString).png")
        guard let data = image.pngData(), (try? data.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "image", url: url)
    }
}

/// Silent pushes: the app is woken in the background for ~30 s.
@MainActor @Observable
final class SyncStore {
    private(set) var count = 0
    private(set) var lastSync: Date?
    private(set) var lastReason: String?

    init() { reload() }

    func reload() {
        let defaults = AppGroup.defaults
        count = defaults.integer(forKey: "sync.count")
        lastSync = defaults.object(forKey: "sync.date") as? Date
        lastReason = defaults.string(forKey: "sync.reason")
    }

    func handleSilentPush(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        let reason = userInfo[PayloadKey.reason] as? String ?? "unspecified"
        EventLog.add("Silent push woke the app (reason: \(reason))", source: "app")

        // Real apps fetch changes from their API here. Finish well within ~30 s,
        // or iOS gives your app fewer background wake-ups in the future.
        try? await Task.sleep(for: .seconds(1))

        let defaults = AppGroup.defaults
        defaults.set(defaults.integer(forKey: "sync.count") + 1, forKey: "sync.count")
        defaults.set(Date.now, forKey: "sync.date")
        defaults.set(reason, forKey: "sync.reason")
        reload()
        return .newData
    }
}

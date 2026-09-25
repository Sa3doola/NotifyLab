import Intents
import UserNotifications

/// Runs for every remote alert push that has `"mutable-content": 1`, BEFORE iOS shows it.
/// It has ~30 seconds to change the content: download an image, turn a chat message into
/// a communication notification, decrypt text, update shared data.
/// It never runs for local notifications or silent pushes.
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    // Written in didReceive, read again when time runs out. The lock guarantees
    // the content handler is called exactly once, whichever path gets there first.
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }

        // 1. Quick work first. If time runs out later, iOS shows at least this.
        let update = OrderUpdate(userInfo: content.userInfo)
        if let update {
            SharedOrders.apply(update)   // the app is up to date before the user opens it
            if content.title.isEmpty {
                content.title = "Order #\(update.orderID): \(update.status.title)"
            }
            EventLog.add("Service extension saved order \(update.orderID) → \(update.status.title)", source: "service")
        }
        let imageURL = update?.imageURL
            ?? (content.userInfo[PayloadKey.imageURL] as? String).flatMap(URL.init(string:))

        lock.withLock {
            self.contentHandler = contentHandler
            self.bestAttempt = content
        }

        // 2. A message from a person: show it as a communication notification.
        if let message = ChatMessage(userInfo: content.userInfo, text: content.body) {
            Task {
                let intent = await Self.donateMessageIntent(for: message)
                self.finish { content in
                    do {
                        // Swaps the app icon for the sender's photo and name.
                        return try content.updating(from: intent)
                    } catch {
                        EventLog.add("updating(from:) failed: \(error.localizedDescription)", source: "service")
                        return content
                    }
                }
            }
            return
        }

        // 3. Slow work: download the image and attach it.
        guard let imageURL else {
            finish()
            return
        }
        Task {
            let attachment = await Self.downloadAttachment(from: imageURL)
            if attachment != nil {
                EventLog.add("Service extension attached image", source: "service")
            }
            self.finish { content in
                if let attachment { content.attachments = [attachment] }
                return content
            }
        }
    }

    /// iOS is about to kill the extension. Deliver whatever we have.
    override func serviceExtensionTimeWillExpire() {
        EventLog.add("Service extension ran out of time; showing original text", source: "service")
        finish()
    }

    private func finish(_ transform: (UNMutableNotificationContent) -> UNNotificationContent = { $0 }) {
        lock.lock()
        let handler = contentHandler
        let content = bestAttempt
        contentHandler = nil
        lock.unlock()

        guard let handler, let content else { return }   // already delivered
        handler(transform(content))
    }

    /// Describes the message as an `INSendMessageIntent` and donates it. iOS then treats the
    /// notification as a message from a person: sender photo, sender name, Focus-aware.
    /// Needs the Communication Notifications capability and `INSendMessageIntent` in the
    /// app's NSUserActivityTypes. Without them, the notification stays a plain one.
    private static func donateMessageIntent(for message: ChatMessage) async -> INSendMessageIntent {
        // Pass the photo as bytes. We download it here, inside the extension's 30 seconds.
        var avatar: INImage?
        if let url = message.avatarURL, let data = try? await URLSession.shared.data(from: url).0 {
            avatar = INImage(imageData: data)
        }
        let sender = INPerson(
            personHandle: INPersonHandle(value: message.senderID, type: .unknown),
            nameComponents: nil,
            displayName: message.senderName,
            image: avatar,
            contactIdentifier: nil,
            customIdentifier: message.senderID
        )
        let intent = INSendMessageIntent(
            recipients: nil,                          // one-to-one: the user is the recipient
            outgoingMessageType: .outgoingMessageText,
            content: message.text,
            speakableGroupName: nil,
            conversationIdentifier: message.conversationID,   // same ID for the whole chat
            serviceName: nil,
            sender: sender,
            attachments: nil
        )

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        do {
            try await interaction.donate()
            EventLog.add("Service extension: message from \(message.senderName) → communication notification", source: "service")
        } catch {
            EventLog.add("Intent donation failed: \(error.localizedDescription)", source: "service")
        }
        return intent
    }

    /// Downloads to a temp file with the right extension. iOS uses the file extension to
    /// work out the type. Limits: image 10 MB, audio 5 MB, video 50 MB.
    private static func downloadAttachment(from url: URL) async -> UNNotificationAttachment? {
        do {
            let (downloaded, response) = try await URLSession.shared.download(from: url)
            let ext = url.pathExtension.isEmpty
                ? ((response.mimeType?.contains("png") ?? false) ? "png" : "jpg")
                : url.pathExtension
            let file = FileManager.default.temporaryDirectory
                .appending(path: "\(UUID().uuidString).\(ext)")
            try FileManager.default.moveItem(at: downloaded, to: file)
            return try UNNotificationAttachment(identifier: "image", url: file)
        } catch {
            return nil
        }
    }
}

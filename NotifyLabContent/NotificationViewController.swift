import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

/// Shown when the user long-presses a notification whose category is listed in
/// this extension's Info.plist (`UNNotificationExtensionCategory` = ORDER).
/// iOS calls these methods on the main thread, so a main-actor conformance is safe.
final class NotificationViewController: UIViewController, @preconcurrency UNNotificationContentExtension {
    private let card = OrderCardModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        // The UI is SwiftUI, hosted in the UIKit view controller that the extension requires.
        let host = UIHostingController(rootView: OrderCardView(model: card))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    /// Called with each notification in the group. Update the UI for the newest one.
    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        card.title = content.title
        card.body = content.body
        card.update = OrderUpdate(userInfo: content.userInfo)
        if let id = card.update?.orderID {
            card.timeline = SharedOrders.timelines()[id] ?? []
        }
        card.image = Self.loadImage(from: content.attachments.first)
        card.note = nil
        EventLog.add("Content extension showed the order card", source: "content")
    }

    /// Action buttons come here first. We decide: handle in place, or open the app.
    func didReceive(_ response: UNNotificationResponse,
                    completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        switch response.actionIdentifier {
        case ActionID.orderContact:
            card.note = "Calling your driver…"
            EventLog.add("Call driver tapped in the content extension", source: "content")
            completion(.doNotDismiss)              // stay open, card updated
        default:
            completion(.dismissAndForwardAction)   // e.g. "Track order": let the app handle it
        }
    }

    /// Attachments live in a security-scoped location managed by iOS.
    private static func loadImage(from attachment: UNNotificationAttachment?) -> UIImage? {
        guard let url = attachment?.url, url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        return UIImage(contentsOfFile: url.path)
    }
}

@MainActor @Observable
final class OrderCardModel {
    var title = ""
    var body = ""
    var update: OrderUpdate?
    var timeline: [OrderEvent] = []
    var image: UIImage?
    var note: String?
}

struct OrderCardView: View {
    let model: OrderCardModel
    private let red = Color(red: 0.83, green: 0.22, blue: 0.17)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let image = model.image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: model.update?.status.symbol ?? "shippingbox")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(red)
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title).font(.headline)
                    Text(model.body).font(.subheadline).foregroundStyle(.secondary)
                    if let eta = model.update?.eta {
                        Label("ETA \(eta)", systemImage: "clock").font(.caption.weight(.semibold))
                    }
                }
            }

            // Five-step progress, filled up to the current status.
            let steps = OrderStatus.allCases
            let reached = steps.firstIndex(of: model.update?.status ?? .placed) ?? 0
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= reached ? AnyShapeStyle(red) : AnyShapeStyle(.quaternary))
                        .frame(height: 6)
                }
            }
            HStack {
                Text(steps.first?.title ?? "")
                Spacer()
                Text(model.update?.status.title ?? "")
                    .fontWeight(.semibold)
                    .foregroundStyle(red)
            }
            .font(.caption)

            if let note = model.note {
                Label(note, systemImage: "phone.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

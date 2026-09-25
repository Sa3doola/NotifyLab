import SwiftUI

struct OrdersView: View {
    @Environment(OrderStore.self) private var orders
    @Environment(PushTokenStore.self) private var tokens
    @Environment(Navigation.self) private var navigation
    @State private var registryURL = ""

    private var bundleID: String { Bundle.main.bundleIdentifier ?? "" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    OrderTimeline(timeline: orders.timeline)
                        .listRowBackground(navigation.highlightedOrderID == OrderStore.demoOrderID
                                           ? Color.notifyRed.opacity(0.08) : nil)
                } header: {
                    Text("Order #\(OrderStore.demoOrderID)")
                } footer: {
                    Text("A push with orderId + status updates this screen. So does the Service Extension, before you even open the app.")
                }

                Section {
                    Menu {
                        ForEach(OrderStatus.allCases, id: \.self) { status in
                            Button(status.title) {
                                Task { await orders.previewLocally(status) }
                            }
                        }
                    } label: {
                        Label("Preview an update as a local notification", systemImage: "rectangle.stack.badge.plus")
                    }
                    Button(role: .destructive) { orders.reset() } label: {
                        Label("Reset order", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("Arrives in 3 s. Long-press it to open the custom card from the Content Extension.")
                }

                Section {
                    TokenRow(title: "APNs device token", value: tokens.apnsToken,
                             placeholder: tokens.registrationError ?? "Waiting for APNs…")
                    TokenRow(title: "FCM registration token", value: tokens.fcmToken,
                             placeholder: "Add FirebaseMessaging to enable")
                    LabeledContent("Environment", value: "\(tokens.environment.rawValue) · \(tokens.environment.host)")
                } header: {
                    Text("Push tokens")
                } footer: {
                    Text("A Debug build's token only works with the sandbox endpoint. Sending it to production returns 400 BadDeviceToken.")
                }

                Section {
                    TextField("http://192.168.1.20:8080", text: $registryURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit { tokens.registryURL = registryURL }
                    Button("Upload tokens now") {
                        tokens.registryURL = registryURL
                        Task { await tokens.uploadIfNeeded(force: true) }
                    }
                    Text(tokens.uploadStatus).font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("Your server (optional)")
                } footer: {
                    Text("Run  node tools/registry-server.mjs  on your Mac. Use http:// (not https://). Simulator: http://localhost:8080. iPhone: http://<your Mac's IP>:8080 on the same Wi-Fi.")
                }

                Section("Send a real push to the Simulator") {
                    CommandRow(caption: "From the NotifyLab folder, in Terminal:",
                               command: "xcrun simctl push booted \(bundleID) payloads/order-shipped.apns")
                    CommandRow(caption: "Or drag any .apns file from payloads/ onto the Simulator window.",
                               command: "payloads/order-out-for-delivery.apns")
                }
            }
            .navigationTitle("Orders")
            .onAppear { registryURL = tokens.registryURL }
        }
    }
}

private struct OrderTimeline: View {
    let timeline: [OrderEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(OrderStatus.allCases, id: \.self) { status in
                let event = timeline.first { $0.status == status }
                HStack(spacing: 12) {
                    Image(systemName: event == nil ? status.symbol : "checkmark.circle.fill")
                        .frame(width: 26)
                        .foregroundStyle(event == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                    Text(status.title)
                        .foregroundStyle(event == nil ? .secondary : .primary)
                    Spacer()
                    if let event {
                        Text(event.date.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

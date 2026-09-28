import SwiftUI

struct StatusView: View {
    @Environment(NotificationPermission.self) private var permission
    @Environment(PushTokenStore.self) private var tokens
    @State private var log: [LogEntry] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if permission.status == .notDetermined || permission.status == .provisional {
                        Button {
                            Task { await permission.requestFull() }
                        } label: {
                            Label("Ask for permission", systemImage: "bell")
                        }
                    }
                    if permission.status == .notDetermined {
                        Button {
                            Task { await permission.requestProvisional() }
                        } label: {
                            Label("Start quietly (provisional, no prompt)", systemImage: "bell.slash")
                        }
                    }
                    Button {
                        permission.openSettings()
                    } label: {
                        Label("Open this app's notification settings", systemImage: "gear")
                    }
                } footer: {
                    Text("iOS shows the permission prompt only once. After a \"Don't Allow\", the only way back is Settings.")
                }

                Section {
                    ForEach(permission.rows) { row in
                        LabeledContent(row.id, value: row.value)
                    }
                } header: {
                    Text("What the user allowed")
                } footer: {
                    Text("Read with getNotificationSettings(). Users can change these in Settings at any time, so we re-read them every time the app becomes active.")
                }

                Section("This device") {
                    LabeledContent("Low Power Mode", value: permission.lowPowerMode ? "On (pushes may be delayed)" : "Off")
                    LabeledContent("Background App Refresh", value: permission.backgroundRefresh)
                }

                Section {
                    if let result = tokens.lastSendResult {
                        LabeledContent("APNs status", value: "\(result.status)")
                        if let reason = result.reason {
                            LabeledContent("Reason", value: reason)
                        }
                        if let action = result.action {
                            LabeledContent("Server's next move", value: action)
                        }
                        if let apnsId = result.apnsId {
                            LabeledContent("apns-id", value: apnsId)
                        }
                        if let date = result.sentDate {
                            LabeledContent("Sent", value: date.formatted(date: .omitted, time: .standard))
                        }
                    } else {
                        Text(tokens.lastSendResultStatus).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Last test push")
                } footer: {
                    Text("APNs's own response to the last push /send made for this device. Status 200 means APNs accepted it — it does not mean iOS displayed it. If nothing showed up, check permission, Low Power Mode and Focus above, not this row.")
                }

                Section {
                    if log.isEmpty {
                        Text("Nothing yet. Schedule a habit test or send a push.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(log) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message).font(.subheadline)
                            Text("\(entry.source) · \(entry.date.formatted(date: .omitted, time: .standard))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    HStack {
                        Text("Event log (app + extensions)")
                        Spacer()
                        Button("Clear") { EventLog.clear(); log = [] }
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("NotifyLab")
            .task {
                // The extensions write to the shared log from their own processes; poll it.
                // The send itself happens from Terminal, not the app, so poll the registry server too.
                while !Task.isCancelled {
                    log = EventLog.all()
                    await tokens.refreshLastSendResult()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                Task { await permission.refresh() }
            }
        }
    }
}

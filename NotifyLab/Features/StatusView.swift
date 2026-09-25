import SwiftUI

struct StatusView: View {
    @Environment(NotificationPermission.self) private var permission
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
                while !Task.isCancelled {
                    log = EventLog.all()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                Task { await permission.refresh() }
            }
        }
    }
}

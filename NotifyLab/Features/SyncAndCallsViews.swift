import SwiftUI

struct SyncView: View {
    @Environment(SyncStore.self) private var sync
    @Environment(NotificationPermission.self) private var permission

    private var bundleID: String { Bundle.main.bundleIdentifier ?? "" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Background wake-ups", value: "\(sync.count)")
                    LabeledContent("Last one", value: sync.lastSync?.formatted(date: .abbreviated, time: .standard) ?? "Never")
                    LabeledContent("Reason", value: sync.lastReason ?? "—")
                } header: {
                    Text("Silent pushes received")
                } footer: {
                    Text("A silent push has content-available: 1 and nothing to show. iOS wakes the app for about 30 seconds. No permission needed.")
                }

                Section {
                    LabeledContent("Low Power Mode", value: permission.lowPowerMode ? "On" : "Off")
                    LabeledContent("Background App Refresh", value: permission.backgroundRefresh)
                } header: {
                    Text("Why one might not arrive")
                } footer: {
                    Text("Silent pushes are best-effort. iOS throttles them (aim for 2–3 per hour at most), delays them in Low Power Mode, and doesn't deliver them after the user force-quits the app. Always sync again on launch.")
                }

                Section {
                    CommandRow(caption: "Send a real sandbox push (works for the Simulator too, since it has a real token):",
                               command: "./tools/apns.sh payloads/silent-sync.apns background")
                } header: {
                    Text("Try it")
                } footer: {
                    Text("xcrun simctl push refuses silent payloads (\"no user visible content\"), so this one needs APNs.")
                }
            }
            .navigationTitle("Sync")
            .refreshable { sync.reload() }
        }
    }
}

struct CallsView: View {
    @Environment(VoIPService.self) private var voip
    @Environment(PushTokenStore.self) private var tokens

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TokenRow(title: "VoIP token (PushKit)", value: tokens.voipToken,
                             placeholder: "Waiting for PushKit…")
                } footer: {
                    Text("A separate token from the APNs alert token. Send it with apns-push-type: voip and topic <bundle id>.voip.")
                }

                Section {
                    Button {
                        voip.reportIncomingCall(from: "Sara (demo)")
                    } label: {
                        Label("Show an incoming call now", systemImage: "phone.arrow.down.left")
                    }
                } footer: {
                    Text("Reports a call to CallKit directly, the same thing the VoIP push handler does. Send a real one with ./tools/apns.sh payloads/voip-call.json voip. The Simulator gets the push, but CallKit ends the call at once: the call screen needs a device.")
                }

                Section("Calls") {
                    if voip.calls.isEmpty {
                        Text("No calls yet").foregroundStyle(.secondary)
                    }
                    ForEach(voip.calls) { call in
                        LabeledContent(call.caller) {
                            VStack(alignment: .trailing) {
                                Text(call.state)
                                Text(call.date.formatted(date: .omitted, time: .standard)).font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Calls")
        }
    }
}

import SwiftUI
import UIKit

struct RootView: View {
    @Environment(Navigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.tab) {
            StatusView()
                .tabItem { Label("Status", systemImage: "bell.badge") }
                .tag(AppTab.status)
            HabitsView()
                .tabItem { Label("Habits", systemImage: "checklist") }
                .tag(AppTab.habits)
            OrdersView()
                .tabItem { Label("Orders", systemImage: "shippingbox") }
                .tag(AppTab.orders)
            SyncView()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                .tag(AppTab.sync)
            CallsView()
                .tabItem { Label("Calls", systemImage: "phone") }
                .tag(AppTab.calls)
        }
    }
}

/// A long token, shown in full and copyable.
struct TokenRow: View {
    let title: String
    let value: String?
    var placeholder = "Not received yet"
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if let value {
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.string = value
                        copied = true
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                }
            }
            Text(value ?? placeholder)
                .font(.caption.monospaced())
                .foregroundStyle(value == nil ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

/// Monospaced command the reader can copy into Terminal.
struct CommandRow: View {
    let caption: String
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption).font(.footnote).foregroundStyle(.secondary)
            Text(command)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

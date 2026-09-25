import UIKit

/// Which APNs endpoint this build's tokens belong to.
/// Debug builds → sandbox. TestFlight / App Store → production. Mixing them = 400 BadDeviceToken.
enum APSEnvironment: String, Codable, Sendable {
    case development, production

    var host: String {
        self == .development ? "api.sandbox.push.apple.com" : "api.push.apple.com"
    }

    /// Reads `aps-environment` from the embedded provisioning profile.
    /// App Store and TestFlight builds have no embedded profile, and they are always production.
    static let current: APSEnvironment = {
        #if targetEnvironment(simulator)
        return .development
        #else
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let raw = try? String(contentsOf: url, encoding: .isoLatin1),
              let start = raw.range(of: "<?xml"),
              let end = raw.range(of: "</plist>"),
              let data = String(raw[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let value = entitlements["aps-environment"] as? String
        else { return .production }
        return APSEnvironment(rawValue: value) ?? .production
        #endif
    }()
}

/// What we send to our backend. One row per device, upserted by `deviceID`.
struct DeviceRecord: Codable, Sendable {
    let deviceID: String
    let userID: String
    let platform: String
    let bundleID: String
    let environment: APSEnvironment
    let apnsToken: String?
    let fcmToken: String?
    let voipToken: String?
    let appVersion: String
    let osVersion: String
}

/// Holds the three tokens this app can have, and uploads them only when something changed.
@MainActor @Observable
final class PushTokenStore {
    private(set) var apnsToken: String?
    private(set) var fcmToken: String?
    private(set) var voipToken: String?
    private(set) var registrationError: String?
    private(set) var uploadStatus = "Waiting for a token"
    let environment = APSEnvironment.current

    var registryURL: String {
        get { UserDefaults.standard.string(forKey: "registryURL")
              ?? Bundle.main.object(forInfoDictionaryKey: "NotifyLabRegistryURL") as? String ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "registryURL") }
    }

    func didReceiveAPNsToken(_ token: Data) {
        // The token is opaque bytes of no fixed length. Never parse it; just hex-encode it.
        let hex = token.map { String(format: "%02x", $0) }.joined()
        if hex != apnsToken { EventLog.add("APNs token \(hex.prefix(8))… (\(environment.rawValue))", source: "app") }
        apnsToken = hex
        registrationError = nil
        Task { await uploadIfNeeded() }
    }

    func didFailToRegister(_ error: Error) {
        registrationError = error.localizedDescription
        EventLog.add("APNs registration failed: \(error.localizedDescription)", source: "app")
    }

    func didReceiveFCMToken(_ token: String?) {
        fcmToken = token
        if let token { EventLog.add("FCM token \(token.prefix(8))…", source: "app") }
        Task { await uploadIfNeeded() }
    }

    func didReceiveVoIPToken(_ token: Data?) {
        voipToken = token.map { $0.map { String(format: "%02x", $0) }.joined() }
        Task { await uploadIfNeeded() }
    }

    /// Upload when a token changed, or at least once a week so the server's `lastSeenAt` stays fresh.
    func uploadIfNeeded(force: Bool = false) async {
        guard apnsToken != nil || fcmToken != nil || voipToken != nil else { return }
        let fingerprint = [apnsToken, fcmToken, voipToken, environment.rawValue]
            .map { $0 ?? "-" }.joined(separator: "|")
        let defaults = UserDefaults.standard
        let lastUpload = defaults.object(forKey: "registry.date") as? Date ?? .distantPast
        let isStale = Date.now.timeIntervalSince(lastUpload) > 7 * 24 * 3600
        guard force || fingerprint != defaults.string(forKey: "registry.fingerprint") || isStale else {
            uploadStatus = "Server already has these tokens"
            return
        }
        guard let base = DeviceRegistry.normalizedURL(registryURL) else {
            uploadStatus = "No server URL set. Copy the token instead."
            return
        }
        do {
            try await DeviceRegistry.upload(makeRecord(), to: base)
            defaults.set(fingerprint, forKey: "registry.fingerprint")
            defaults.set(Date.now, forKey: "registry.date")
            uploadStatus = "Uploaded to \(base.absoluteString) at \(Date.now.formatted(date: .omitted, time: .shortened))"
        } catch {
            // Show the exact URL: "TLS error" almost always means it started with https://
            uploadStatus = "Upload to \(base.absoluteString) failed: \(error.localizedDescription)"
        }
    }

    private func makeRecord() -> DeviceRecord {
        DeviceRecord(
            // identifierForVendor also changes when the user deletes all your apps, like the token does.
            deviceID: UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            userID: "demo-user",
            platform: "ios",
            bundleID: Bundle.main.bundleIdentifier ?? "",
            environment: environment,
            apnsToken: apnsToken,
            fcmToken: fcmToken,
            voipToken: voipToken,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            osVersion: UIDevice.current.systemVersion)
    }
}

/// POST /devices on tools/registry-server.mjs (or your real backend).
enum DeviceRegistry {
    struct HTTPError: LocalizedError {
        let status: Int
        var errorDescription: String? { "HTTP \(status)" }
    }

    /// "192.168.1.20:8080" → "http://192.168.1.20:8080". The demo server speaks plain HTTP only.
    static func normalizedURL(_ text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") { value = "http://" + value }
        return URL(string: value)
    }

    static func upload(_ record: DeviceRecord, to base: URL) async throws {
        var request = URLRequest(url: base.appending(path: "devices"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(record)
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw HTTPError(status: status) }
    }
}

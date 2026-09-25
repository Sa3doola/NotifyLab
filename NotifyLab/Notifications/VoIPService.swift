import CallKit
import PushKit
import UIKit

/// VoIP pushes (PushKit) + the system call screen (CallKit).
///
/// The one rule: every VoIP push must be reported to CallKit as an incoming call,
/// before PushKit's completion handler is called. Skip it, and iOS terminates the app;
/// keep skipping it, and iOS stops delivering VoIP pushes to the app altogether.
@MainActor @Observable
final class VoIPService: NSObject {
    struct CallRecord: Identifiable, Hashable {
        let id: UUID
        let caller: String
        let date: Date
        var state: String
    }

    private(set) var calls: [CallRecord] = []

    @ObservationIgnored private let registry = PKPushRegistry(queue: .main)
    @ObservationIgnored private let provider: CXProvider
    @ObservationIgnored private weak var tokens: PushTokenStore?

    init(tokens: PushTokenStore) {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        provider = CXProvider(configuration: configuration)
        self.tokens = tokens
        super.init()
        provider.setDelegate(self, queue: nil)    // nil = main queue
    }

    /// Registering asks for a VoIP token. No permission prompt is involved.
    func start() {
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
    }

    /// Shows the system incoming-call screen.
    func reportIncomingCall(from caller: String) {
        let uuid = UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: caller)
        update.localizedCallerName = caller
        update.hasVideo = false

        calls.insert(CallRecord(id: uuid, caller: caller, date: .now, state: "Ringing"), at: 0)
        EventLog.add("Reported call from \(caller) to CallKit", source: "voip")

        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            guard let error else { return }
            Task { @MainActor in self.setState(uuid, "Failed: \(error.localizedDescription)") }
        }
    }

    private func setState(_ id: UUID, _ state: String) {
        guard let index = calls.firstIndex(where: { $0.id == id }) else { return }
        calls[index].state = state
    }
}

// PushKit calls us on the queue we gave it (.main), so a main-actor conformance is safe.
extension VoIPService: @preconcurrency PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry,
                      didUpdate pushCredentials: PKPushCredentials,
                      for type: PKPushType) {
        tokens?.didReceiveVoIPToken(pushCredentials.token)
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        tokens?.didReceiveVoIPToken(nil)
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {
        let caller = payload.dictionaryPayload[PayloadKey.caller] as? String ?? "Unknown caller"
        reportIncomingCall(from: caller)   // FIRST: tell CallKit
        completion()                       // THEN: tell PushKit we're done
    }
}

// CallKit calls us on the main queue (we passed `queue: nil`).
extension VoIPService: @preconcurrency CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        for index in calls.indices where calls[index].state == "Ringing" {
            calls[index].state = "Reset"
        }
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        setState(action.callUUID, "Answered")
        // Start your audio session / WebRTC connection here.
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        setState(action.callUUID, "Ended")
        action.fulfill()
    }
}

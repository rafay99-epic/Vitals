import Testing
import Foundation
@testable import Vitals

struct LanBridgeTests {
    private func decode(_ line: String) throws -> ToApp {
        try JSONDecoder().decode(ToApp.self, from: Data(line.utf8))
    }

    @Test func statusCarriesLanAndSetup() throws {
        let key = String(repeating: "A", count: 43)
        let line = #"{"t":"status","status":{"serve":"off","url":null,"detail":null,"ownerLogin":null,"clients":0,"lan":{"port":47812,"key":"\#(key)","reachable":false},"setup":{"step":"https","url":"https://login.tailscale.com/f/serve?node=n1"},"extra":1}}"#
        guard case let .status(status) = try decode(line) else { throw Unexpected() }
        #expect(status.lan == GatewayStatus.Lan(port: 47_812, key: key, reachable: false))
        #expect(status.setup == TailscaleSetup(step: .https, url: "https://login.tailscale.com/f/serve?node=n1"))
    }

    @Test func olderOrNewerStatusShapesStillDecode() throws {
        let old = #"{"t":"status","status":{"serve":"serving","url":"https://m.ts.net","detail":null,"ownerLogin":"o@","clients":1}}"#
        guard case let .status(status) = try decode(old) else { throw Unexpected() }
        #expect(status.lan == nil)
        #expect(status.setup == nil)

        let newer = #"{"t":"status","status":{"serve":"off","url":null,"detail":null,"ownerLogin":null,"clients":0,"lan":null,"setup":{"step":"warp","url":null}}}"#
        guard case let .status(next) = try decode(newer) else { throw Unexpected() }
        #expect(next.setup?.step == .external)
    }

    @Test func pairPromptAndEndDecode() throws {
        let line = #"{"t":"pairPrompt","prompt":{"id":"p1","device":{"name":"Pixel 9","platform":"android","model":"Pixel 9","appVersion":"1.2.0"},"code":"4819","address":"192.168.1.44","expiresAt":1790000120000}}"#
        guard case let .pairPrompt(prompt) = try decode(line) else { throw Unexpected() }
        #expect(prompt.id == "p1")
        #expect(prompt.device.name == "Pixel 9")
        #expect(prompt.code == "4819")
        #expect(prompt.address == "192.168.1.44")
        #expect(prompt.expiry == Date(timeIntervalSince1970: 1_790_000_120))
        #expect(try decode(#"{"t":"pairPromptEnded","id":"p1"}"#) == .pairPromptEnded(id: "p1"))
    }

    @Test func resolvePairPromptRoundTrips() throws {
        let data = try JSONEncoder().encode(FromApp.admin(id: "a-9", op: .resolvePairPrompt(id: "p1", allow: true)))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
        #expect(json == ["t": "admin", "id": "a-9", "op": ["_tag": "ResolvePairPrompt", "id": "p1", "allow": true]])
        let result = #"{"t":"adminResult","id":"a-9","ok":{"_tag":"ResolvePairPrompt"},"error":null}"#
        #expect(try decode(result) == .adminResult(id: "a-9", result: .resolvePairPrompt, error: nil))
    }

    @Test func setupStepsMapToFourVisibleSteps() {
        let steps: [TailscaleSetup.Step] = [.install, .start, .signin, .magicdns, .https, .ready, .external]
        #expect(steps.map(\.number) == [1, 2, 2, 3, 3, 4, nil])
        #expect(TailscaleSetup.Step.signin.finished(ownerLogin: "o@") == ["installed"])
        #expect(TailscaleSetup.Step.https.finished(ownerLogin: "o@") == ["installed", "signed in as o@", "MagicDNS"])
    }

    @Test func pairNotificationActionsResolveTheirPrompt() {
        let id = NotificationManager.pairNotificationId("p1")
        #expect(NotificationManager.remoteAction(NotificationManager.Action.allowPair, identifier: id) == .resolvePair(id: "p1", allow: true))
        #expect(NotificationManager.remoteAction(NotificationManager.Action.denyPair, identifier: id) == .resolvePair(id: "p1", allow: false))
        #expect(NotificationManager.remoteAction(NotificationManager.Action.allowPair, identifier: "other") == nil)
    }

    @Test func txtRecordIsLengthPrefixed() {
        let advert = LanAdvertiser.Advert(name: "Mac", port: 1, key: "K", channel: "dev")
        #expect(LanAdvertiser.txtRecord(advert) == [3] + Array("k=K".utf8) + [5] + Array("n=Mac".utf8) + [5] + Array("c=dev".utf8) + [3] + Array("v=1".utf8))
    }

    private struct Unexpected: Error {}
}

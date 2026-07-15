import XCTest
@testable import OpenVoiceTyper

/// The keyboard↔app IPC layer: App Group mailbox semantics plus real Darwin
/// notification delivery (in-process, but through the actual Darwin center).
final class BridgeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DictationBridge.clearCommand()
        DictationBridge.clearResult()
    }

    func testBridgeIsAvailableInHostApp() {
        XCTAssertTrue(DictationBridge.isAvailable, "App Group container must be reachable from the app")
    }

    func testCommandRoundTripAndClear() {
        let command = KeyboardCommand(kind: .startDictation, styleID: Style.light.id)
        DictationBridge.send(command)

        let pending = DictationBridge.pendingCommand()
        XCTAssertEqual(pending?.id, command.id)
        XCTAssertEqual(pending?.kind, .startDictation)

        DictationBridge.clearCommand()
        XCTAssertNil(DictationBridge.pendingCommand(), "handled commands must not replay")
    }

    func testResultRoundTripAndClear() {
        let commandID = UUID()
        DictationBridge.publish(DictationResult(
            commandID: commandID,
            styleID: Style.formal.id,
            rawText: "raw",
            polishedText: "polished"
        ))

        let result = DictationBridge.latestResult()
        XCTAssertEqual(result?.commandID, commandID)
        XCTAssertEqual(result?.polishedText, "polished")
        XCTAssertFalse(result?.isError ?? true)

        DictationBridge.clearResult()
        XCTAssertNil(DictationBridge.latestResult(), "inserted results must not replay")
    }

    func testHeartbeatLiveness() {
        DictationBridge.publish(SessionHeartbeat(startedAt: .now, lastBeatAt: .now))
        XCTAssertTrue(DictationBridge.isSessionAlive)

        let stale = SessionHeartbeat(
            startedAt: .now.addingTimeInterval(-60),
            lastBeatAt: .now.addingTimeInterval(-SessionHeartbeat.staleAfter - 1)
        )
        DictationBridge.publish(stale)
        XCTAssertFalse(DictationBridge.isSessionAlive, "stale heartbeat must read as dead")

        DictationBridge.publish(nil as SessionHeartbeat?)
        XCTAssertFalse(DictationBridge.isSessionAlive)
    }

    func testDarwinNotificationDelivers() {
        let fired = expectation(description: "darwin observer fired")
        let token = DarwinNotifier.observe(.commandPosted) {
            fired.fulfill()
        }
        DictationBridge.send(KeyboardCommand(kind: .startDictation, styleID: Style.raw.id))
        wait(for: [fired], timeout: 5)
        _ = token // keep observer alive until delivery
        DictationBridge.clearCommand()
    }

    func testErrorResultCarriesMessage() {
        DictationBridge.publish(DictationResult(
            commandID: UUID(),
            styleID: Style.light.id,
            rawText: "",
            polishedText: "",
            errorMessage: "No ASR API key configured. Add one in Settings."
        ))
        let result = DictationBridge.latestResult()
        XCTAssertTrue(result?.isError ?? false)
        XCTAssertTrue(result?.errorMessage?.contains("API key") ?? false)
        DictationBridge.clearResult()
    }
}

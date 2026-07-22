import XCTest
@testable import OpenVoiceTyper

/// The keyboard↔app IPC layer: App Group mailbox semantics plus real Darwin
/// notification delivery (in-process, but through the actual Darwin center).
final class BridgeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DictationBridge.clearCommands()
        DictationBridge.clearResult()
        DictationBridge.setAwaitingCommandID(nil)
    }

    func testBridgeIsAvailableInHostApp() {
        XCTAssertTrue(DictationBridge.isAvailable, "App Group container must be reachable from the app")
    }

    func testCommandRoundTrip() {
        let command = KeyboardCommand(kind: .startDictation, styleID: Style.light.id)
        DictationBridge.send(command)

        let pending = DictationBridge.commandQueue().first
        XCTAssertEqual(pending?.id, command.id)
        XCTAssertEqual(pending?.kind, .startDictation)

        DictationBridge.clearCommands()
        XCTAssertTrue(DictationBridge.commandQueue().isEmpty)
    }

    /// The regression that made dictation hang: a fast start→stop must keep
    /// BOTH commands, in order — a single-slot mailbox lost the start.
    func testFastStartStopKeepsBothCommandsInOrder() {
        let start = KeyboardCommand(kind: .startDictation, styleID: Style.light.id)
        let stop = KeyboardCommand(kind: .stopDictation, styleID: Style.light.id)
        DictationBridge.send(start)
        DictationBridge.send(stop)

        let queue = DictationBridge.commandQueue()
        XCTAssertEqual(queue.map(\.id), [start.id, stop.id])
        XCTAssertEqual(queue.map(\.kind), [.startDictation, .stopDictation])
    }

    func testCommandQueueIsBounded() {
        for _ in 0..<20 {
            DictationBridge.send(KeyboardCommand(kind: .cancelDictation, styleID: Style.raw.id))
        }
        XCTAssertLessThanOrEqual(DictationBridge.commandQueue().count, 8)
    }

    func testAwaitingCommandIDPersistsAcrossKeyboardLifetimes() {
        let id = UUID()
        DictationBridge.setAwaitingCommandID(id)
        XCTAssertEqual(DictationBridge.awaitingCommandID(), id)
        DictationBridge.setAwaitingCommandID(nil)
        XCTAssertNil(DictationBridge.awaitingCommandID())
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
        DictationBridge.clearCommands()
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

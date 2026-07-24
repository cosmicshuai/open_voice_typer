import XCTest
@testable import OpenVoiceTyper

/// The keyboard-side state machine. It had no coverage at all until the
/// stranded-panel bug below, which is exactly the kind of fault it hides: the
/// phase is the only thing standing between the user and a dead mic button,
/// and nothing outside the model can put it right.
@MainActor
final class VoicePanelModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DictationBridge.clearCommands()
        DictationBridge.clearResult()
        // A live session, so refreshSessionState() leaves .idle alone instead
        // of dropping the model into .noSession.
        DictationBridge.publish(SessionHeartbeat(startedAt: .now, lastBeatAt: .now))
    }

    override func tearDown() {
        DictationBridge.clearCommands()
        DictationBridge.clearResult()
        super.tearDown()
    }

    private func makeModel() -> VoicePanelModel {
        VoicePanelModel(needsInputModeSwitchKey: false)
    }

    // MARK: Stranded panel

    /// The regression: dismissing the keyboard mid-recording used to leave the
    /// phase at .recording. The model outlives a dismissal, and
    /// refreshSessionState() only clears the transient phases when the session
    /// is *dead* — so with the app still alive the panel came back showing
    /// "Listening…" forever, awaiting nothing and with no timeout armed.
    func testDeactivateClearsRecordingPhase() {
        let model = makeModel()
        model.activate()
        XCTAssertEqual(model.phase, .idle, "a live session should start idle")

        model.toggleDictation()
        XCTAssertEqual(model.phase, .recording)

        model.deactivate()
        XCTAssertEqual(model.phase, .idle, "a dismissed keyboard must not stay in .recording")

        // Reopening must land on a usable panel, not a stranded one.
        model.activate()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.canDictate, "the mic must be tappable again after reopening")
    }

    /// Same fault on the other transient phase: .processing is what a keyboard
    /// dismissed while waiting for a transcript would have been stuck in, and
    /// unlike .recording it also disables the mic button.
    func testDeactivateClearsProcessingPhase() {
        let model = makeModel()
        model.activate()
        model.toggleDictation()
        model.phase = .processing

        model.deactivate()
        XCTAssertEqual(model.phase, .idle, "a dismissed keyboard must not stay in .processing")

        model.activate()
        XCTAssertTrue(model.canDictate)
    }

    /// Deactivating while recording must also tell the app to stop capturing,
    /// or the session keeps recording into a dictation nobody is waiting for.
    func testDeactivateCancelsTheInFlightDictation() {
        let model = makeModel()
        model.activate()
        DictationBridge.clearCommands()

        model.toggleDictation()
        model.deactivate()

        XCTAssertEqual(
            DictationBridge.commandQueue().last?.kind, .cancelDictation,
            "an abandoned recording must be cancelled app-side"
        )
    }

    /// Defence in depth: stopping with nothing awaited would arm no timeout and
    /// match no result, parking the panel in .processing permanently.
    func testStoppingWithNothingAwaitedReturnsToIdle() {
        let model = makeModel()
        model.activate()
        model.phase = .recording // no awaited command id

        model.toggleDictation()

        XCTAssertEqual(model.phase, .idle, "a stop with nothing in flight must not hang in .processing")
    }

    // MARK: Result routing

    /// A result the model never asked for belongs to a previous dictation —
    /// very likely one raised in a different host app — and inserting it would
    /// leak app A's transcript into app B's text field.
    func testUnrequestedResultIsNotInserted() {
        let model = makeModel()
        var inserted = ""
        model.insertTextHandler = { inserted += $0 }
        model.activate()

        DictationBridge.publish(DictationResult(
            commandID: UUID(),
            styleID: Style.light.id,
            rawText: "raw",
            polishedText: "should not appear"
        ))

        model.activate() // the poll/notification path re-reads the slot
        XCTAssertTrue(inserted.isEmpty, "a foreign result must never be inserted")
    }

    /// Activating discards whatever is sitting in the shared single-slot
    /// mailbox, so a stale transcript cannot surface in the next host app.
    func testActivateDiscardsStaleResult() {
        DictationBridge.publish(DictationResult(
            commandID: UUID(),
            styleID: Style.light.id,
            rawText: "raw",
            polishedText: "stale"
        ))

        let model = makeModel()
        model.activate()

        XCTAssertNil(DictationBridge.latestResult(), "a fresh keyboard must clear the result slot")
    }

    // MARK: Mode

    func testModeFollowsSelectedStyle() {
        let model = makeModel()
        model.activate()

        model.setMode(.translate)
        XCTAssertEqual(model.mode, .translate)
        XCTAssertEqual(model.selectedStyleID, Style.translate.id)

        model.setMode(.dictate)
        XCTAssertEqual(model.mode, .dictate)
        XCTAssertNotEqual(model.selectedStyleID, Style.translate.id)
    }

    /// Translate is reachable from the toggle, so it must not also appear in
    /// the style menu the toggle sits next to.
    func testDictateStylesExcludeTranslate() {
        let model = makeModel()
        model.activate()
        XCTAssertFalse(model.dictateStyles.contains { $0.id == Style.translate.id })
    }

    // MARK: Undo

    func testUndoIsUnavailableWithNothingInserted() {
        let model = makeModel()
        model.activate()
        XCTAssertFalse(model.canUndo, "undo must stay disabled until something is dictated")
    }
}

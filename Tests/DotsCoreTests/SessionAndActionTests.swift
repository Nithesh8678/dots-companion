import XCTest
@testable import DotsCore

final class SessionStateTests: XCTestCase {
    func testHostBridgeCannotInventVoiceOrCompletion() {
        var machine = SessionStateMachine(capabilities: .hostBridge)
        let session = machine.beginSession()
        let turn = machine.startTurn()
        func envelope(_ event: SessionEvent) -> SessionEventEnvelope {
            SessionEventEnvelope(sessionID: session, turnID: turn, generation: machine.generation, event: event)
        }
        XCTAssertEqual(machine.apply(envelope(.hostOpening)), .applied)
        XCTAssertEqual(machine.apply(envelope(.hostOpened)), .applied)
        XCTAssertEqual(machine.state, .hostOpen)
        let unsupportedEvents: [SessionEvent] = [.listeningStarted, .speechStarted, .transcript("invented"), .completed]
        for event in unsupportedEvents {
            XCTAssertEqual(machine.apply(envelope(event)), .unsupportedCapability)
            XCTAssertEqual(machine.state, .hostOpen)
        }
    }

    func testSupersededTurnCannotSpeakOrChangeTranscript() {
        var machine = SessionStateMachine(capabilities: [.voiceEvents, .transcripts])
        let session = machine.beginSession()
        let oldTurn = machine.startTurn()
        let oldGeneration = machine.generation
        let newTurn = machine.startTurn()
        XCTAssertNotEqual(oldTurn, newTurn)
        let late = SessionEventEnvelope(sessionID: session, turnID: oldTurn, generation: oldGeneration, event: .speechStarted)
        XCTAssertEqual(machine.apply(late), .staleGeneration)
        let wrongTurn = SessionEventEnvelope(sessionID: session, turnID: oldTurn, generation: machine.generation, event: .transcript("late"))
        XCTAssertEqual(machine.apply(wrongTurn), .staleTurn)
        XCTAssertEqual(machine.transcript, "")
        XCTAssertEqual(machine.state, .appearing)
    }

    func testCancellationRejectsLateEventsAndWaitsForAcknowledgement() {
        var machine = SessionStateMachine(capabilities: [.voiceEvents, .remoteCancellation])
        let session = machine.beginSession()
        let turn = machine.startTurn()
        let before = machine.generation
        let ticket = machine.cancel()
        XCTAssertTrue(ticket.remoteAcknowledgementRequired)
        XCTAssertTrue(machine.remoteCancellationPending)
        XCTAssertEqual(machine.apply(.init(sessionID: session, turnID: turn, generation: before, event: .speechStarted)), .staleGeneration)
        XCTAssertEqual(machine.apply(.init(sessionID: session, turnID: nil, generation: ticket.generation, event: .listeningStarted)), .invalidTransition)
        XCTAssertEqual(machine.apply(.init(sessionID: session, turnID: nil, generation: ticket.generation, event: .cancellationAcknowledged)), .applied)
        XCTAssertFalse(machine.remoteCancellationPending)
        XCTAssertEqual(machine.state, .cancelled)
        XCTAssertNil(machine.startTurn())
    }

    func testHiddenPanelDoesNotCancelConversation() {
        var machine = SessionStateMachine(capabilities: [.voiceEvents])
        let session = machine.beginSession()
        let turn = machine.startTurn()
        XCTAssertEqual(machine.apply(.init(sessionID: session, turnID: turn, generation: machine.generation, event: .listeningStarted)), .applied)
        machine.hide()
        XCTAssertFalse(machine.isVisible)
        XCTAssertEqual(machine.state, .listening)
    }

    func testOldSessionIsRejectedEvenIfGenerationIsForgedCurrent() {
        var machine = SessionStateMachine(capabilities: [.voiceEvents])
        let old = machine.beginSession()
        _ = machine.beginSession()
        XCTAssertEqual(machine.apply(.init(sessionID: old, turnID: nil, generation: machine.generation, event: .offline)), .staleSession)
    }

    func testPlaybackCannotStartWithoutCommittedInput() {
        var machine = SessionStateMachine(capabilities: [.voiceEvents])
        let session = machine.beginSession()
        let turn = machine.startTurn()
        XCTAssertEqual(machine.apply(.init(sessionID: session, turnID: turn, generation: machine.generation, event: .speechStarted)), .invalidTransition)
    }
}

final class ActionGateTests: XCTestCase {
    private let focus = FocusSnapshot(processID: 42, fieldID: "document-1:text-field", isEditable: true, isSecure: false)
    private func request(key: String = "dictation-1", generation: UInt64 = 7) -> ActionRequest {
        ActionRequest(kind: .insertText, generation: generation, idempotencyKey: key, intendedFocus: focus)
    }
    func testChangedApplicationNeverInserts() {
        var gate = ActionGate()
        let other = FocusSnapshot(processID: 43, fieldID: focus.fieldID, isEditable: true, isSecure: false)
        XCTAssertEqual(gate.authorize(request(), currentGeneration: 7, permissionGranted: true, currentFocus: other), .refused(.applicationChanged))
        XCTAssertEqual(gate.reservationCount, 0)
    }
    func testChangedFieldInSameApplicationNeverInserts() {
        var gate = ActionGate()
        let other = FocusSnapshot(processID: 42, fieldID: "document-2:text-field", isEditable: true, isSecure: false)
        XCTAssertEqual(gate.authorize(request(), currentGeneration: 7, permissionGranted: true, currentFocus: other), .refused(.fieldChanged))
    }
    func testSecureFieldIsRefusedEvenWhenItBecameSecureAfterCapture() {
        var gate = ActionGate()
        let secure = FocusSnapshot(processID: 42, fieldID: focus.fieldID, isEditable: true, isSecure: true)
        XCTAssertEqual(gate.authorize(request(), currentGeneration: 7, permissionGranted: true, currentFocus: secure), .refused(.secureField))
    }
    func testRepeatNetworkDeliveryCannotDuplicateInsertion() {
        var gate = ActionGate()
        let action = request()
        XCTAssertEqual(gate.authorize(action, currentGeneration: 7, permissionGranted: true, currentFocus: focus), .dispatch(action.id))
        XCTAssertEqual(gate.authorize(request(), currentGeneration: 7, permissionGranted: true, currentFocus: focus), .refused(.duplicate))
    }
    func testCancellationAfterPreflightIsRecheckedBeforeDispatch() {
        var gate = ActionGate()
        let action = request()
        XCTAssertEqual(gate.authorize(action, currentGeneration: 7, permissionGranted: true, currentFocus: focus), .dispatch(action.id))
        XCTAssertEqual(gate.validate(action, currentGeneration: 8, permissionGranted: true, currentFocus: focus), .cancelled)
        XCTAssertEqual(gate.validate(action, currentGeneration: 7, dispatchEnabled: false, permissionGranted: true, currentFocus: focus), .cancelled)
    }
    func testPermissionRevocationAndConsequentialAuthorization() {
        var gate = ActionGate()
        XCTAssertEqual(gate.authorize(request(), currentGeneration: 7, permissionGranted: false, currentFocus: focus), .refused(.permissionMissing))
        let send = ActionRequest(kind: .activateControl, generation: 7, idempotencyKey: "send", intendedFocus: focus, requiresConfirmation: true)
        XCTAssertEqual(gate.authorize(send, currentGeneration: 7, permissionGranted: true, currentFocus: focus), .refused(.confirmationRequired))
    }
    func testCapacityNeverEvictsDeduplicationHistory() {
        var gate = ActionGate(capacity: 1)
        let action = request()
        XCTAssertEqual(gate.authorize(action, currentGeneration: 7, permissionGranted: true, currentFocus: focus), .dispatch(action.id))
        XCTAssertEqual(gate.authorize(request(key: "new"), currentGeneration: 7, permissionGranted: true, currentFocus: focus), .refused(.capacityReached))
        XCTAssertEqual(gate.authorize(action, currentGeneration: 7, permissionGranted: true, currentFocus: focus), .refused(.duplicate))
    }
    func testCoordinateActionRequiresCurrentWindowAndRevision() {
        var gate = ActionGate()
        let time = Date(timeIntervalSince1970: 100)
        let snapshot = ContextSnapshot(processID: 42, windowID: "window-1", displayID: 1, capturedAt: time, revision: 2,
                                       transform: .init(captureFrame: CGRect(x: 0, y: 0, width: 100, height: 100), pixelSize: CGSize(width: 200, height: 200)))
        let action = ActionRequest(kind: .activateControl, generation: 7, idempotencyKey: "click", intendedFocus: focus,
                                   contextID: snapshot.id, usesScreenCoordinates: true)
        XCTAssertEqual(gate.authorize(action, currentGeneration: 7, permissionGranted: true, currentFocus: focus,
                                      context: snapshot, currentContextRevision: 2, currentWindowID: "window-2", now: time), .refused(.staleContext))
        XCTAssertEqual(gate.authorize(action, currentGeneration: 7, permissionGranted: true, currentFocus: focus,
                                      context: snapshot, currentContextRevision: 3, currentWindowID: "window-1", now: time), .refused(.staleContext))
        XCTAssertEqual(gate.authorize(action, currentGeneration: 7, permissionGranted: true, currentFocus: focus,
                                      context: snapshot, currentContextRevision: 2, currentWindowID: "window-1", now: time.addingTimeInterval(4)), .refused(.staleContext))
    }
}

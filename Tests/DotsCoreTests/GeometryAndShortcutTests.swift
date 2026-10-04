import XCTest
@testable import DotsCore

final class GeometryTests: XCTestCase {
    func testRetinaPixelsConvertOnNegativeOriginDisplayAndRoundTrip() throws {
        let transform = CoordinateTransform(captureFrame: CGRect(x: -1440, y: 200, width: 1440, height: 900),
                                            pixelSize: CGSize(width: 2880, height: 1800))
        XCTAssertEqual(transform.appKitPoint(fromImage: .zero), CGPoint(x: -1440, y: 1100))
        let middle = CGPoint(x: 1440, y: 900)
        let converted = try XCTUnwrap(transform.appKitPoint(fromImage: middle))
        XCTAssertEqual(converted, CGPoint(x: -720, y: 650))
        XCTAssertEqual(transform.imagePoint(fromAppKit: converted), middle)
        XCTAssertEqual(transform.appKitRect(fromImage: CGRect(x: 200, y: 100, width: 400, height: 300)),
                       CGRect(x: -1340, y: 900, width: 200, height: 150))
    }
    func testInvalidOrOutsideGeometryDoesNotProduceConfidentTarget() {
        let bad = CoordinateTransform(captureFrame: .zero, pixelSize: .zero)
        XCTAssertNil(bad.appKitPoint(fromNormalized: CGPoint(x: 0.5, y: 0.5)))
        let transform = CoordinateTransform(captureFrame: CGRect(x: 0, y: 0, width: 100, height: 100), pixelSize: CGSize(width: 200, height: 200))
        XCTAssertNil(transform.appKitPoint(fromImage: CGPoint(x: CGFloat.nan, y: 5)))
        XCTAssertNil(transform.appKitPoint(fromNormalized: CGPoint(x: 1.01, y: 0.5)))
        XCTAssertNil(transform.appKitRect(fromImage: CGRect(x: 180, y: 0, width: 30, height: 20)))
    }
    func testContextRejectsTimeTravelMovementAndNavigation() {
        let date = Date(timeIntervalSince1970: 10)
        let context = ContextSnapshot(processID: 1, windowID: "a", displayID: 2, capturedAt: date, revision: 9,
                                      transform: .init(captureFrame: CGRect(x: 0, y: 0, width: 100, height: 100), pixelSize: CGSize(width: 100, height: 100)))
        XCTAssertTrue(context.isFresh(now: date, maxAge: 3, currentRevision: 9, processID: 1, windowID: "a"))
        XCTAssertFalse(context.isFresh(now: date.addingTimeInterval(-1), maxAge: 3, currentRevision: 9, processID: 1, windowID: "a"))
        XCTAssertFalse(context.isFresh(now: date, maxAge: 3, currentRevision: 10, processID: 1, windowID: "a"))
        XCTAssertFalse(context.isFresh(now: date, maxAge: 3, currentRevision: 9, processID: 1, windowID: "b"))
    }
    func testAnnotationCannotCrossContextOrDisplay() {
        let context = ContextSnapshot(processID: 1, windowID: "a", displayID: 2, revision: 0,
                                      transform: .init(captureFrame: CGRect(x: 0, y: 0, width: 100, height: 100), pixelSize: CGSize(width: 100, height: 100)))
        let wrongContext = AnnotationCommand(contextID: ContextID(), displayID: 2, kind: .arrow, imageRect: CGRect(x: 1, y: 1, width: 10, height: 10))
        XCTAssertNil(wrongContext.resolvedRect(in: context))
        let wrongDisplay = AnnotationCommand(contextID: context.id, displayID: 3, kind: .arrow, imageRect: CGRect(x: 1, y: 1, width: 10, height: 10))
        XCTAssertNil(wrongDisplay.resolvedRect(in: context))
    }
}

final class ShortcutGestureTests: XCTestCase {
    func testRegisteredChordFiresOnceUntilReleaseAndIgnoresRepeat() {
        var gestures = ShortcutGestureMachine()
        XCTAssertEqual(gestures.handle(.keyDown(.space, modifiers: [.option], isRepeat: false, time: 0)), [.toggleConversation])
        XCTAssertEqual(gestures.handle(.keyDown(.space, modifiers: [.option], isRepeat: true, time: 0.1)), [])
        XCTAssertEqual(gestures.handle(.keyDown(.space, modifiers: [.option], isRepeat: false, time: 0.2)), [])
        _ = gestures.handle(.keyUp(.space, time: 0.3))
        XCTAssertEqual(gestures.handle(.keyDown(.space, modifiers: [.option], isRepeat: false, time: 0.4)), [.toggleConversation])
    }
    func testModifierGesturesAreOptIn() {
        var gestures = ShortcutGestureMachine()
        XCTAssertEqual(gestures.handle(.modifiers([.control, .option], time: 0)), [])
        XCTAssertEqual(gestures.handle(.holdThresholdReached(time: 1)), [])
    }
    func testControlDoubleTapFiresOnceAndOrdinaryShortcutContaminatesTap() {
        var gestures = ShortcutGestureMachine(modifierGesturesEnabled: true)
        _ = gestures.handle(.modifiers([.control], time: 0))
        _ = gestures.handle(.modifiers([], time: 0.05))
        _ = gestures.handle(.modifiers([.control], time: 0.15))
        XCTAssertEqual(gestures.handle(.modifiers([], time: 0.2)), [.typedSummon])
        _ = gestures.handle(.modifiers([.control], time: 0.25))
        _ = gestures.handle(.keyDown(.other, modifiers: [.control], isRepeat: false, time: 0.26))
        XCTAssertEqual(gestures.handle(.modifiers([], time: 0.3)), [])
        _ = gestures.handle(.modifiers([.control], time: 0.35))
        XCTAssertEqual(gestures.handle(.modifiers([], time: 0.4)), [])
    }
    func testShortHoldDoesNotSubmitAndNormalChordIsCancelled() {
        var gestures = ShortcutGestureMachine(modifierGesturesEnabled: true)
        _ = gestures.handle(.modifiers([.control, .option], time: 0))
        XCTAssertEqual(gestures.handle(.modifiers([], time: 0.05)), [])
        _ = gestures.handle(.modifiers([.control, .option], time: 1))
        _ = gestures.handle(.keyDown(.other, modifiers: [.control, .option], isRepeat: false, time: 1.05))
        XCTAssertEqual(gestures.handle(.holdThresholdReached(time: 1.2)), [])
        XCTAssertEqual(gestures.handle(.modifiers([], time: 1.3)), [])
    }
    func testEscapeAndSleepDiscardHoldInsteadOfSubmitting() {
        var gestures = ShortcutGestureMachine(modifierGesturesEnabled: true)
        _ = gestures.handle(.modifiers([.control, .option], time: 0))
        XCTAssertEqual(gestures.handle(.holdThresholdReached(time: 0.13)), [.beginHold])
        XCTAssertEqual(gestures.handle(.keyDown(.escape, modifiers: [], isRepeat: false, time: 0.2)), [.cancelHold, .stop])
        _ = gestures.handle(.modifiers([.control, .option], time: 1))
        XCTAssertEqual(gestures.handle(.holdThresholdReached(time: 1.2)), [.beginHold])
        XCTAssertEqual(gestures.handle(.reset), [.cancelHold])
        XCTAssertEqual(gestures.handle(.modifiers([], time: 2)), [])
    }
    func testHoldingExtraModifierCancelsRatherThanCommits() {
        var gestures = ShortcutGestureMachine(modifierGesturesEnabled: true)
        _ = gestures.handle(.modifiers([.control, .option], time: 0))
        _ = gestures.handle(.holdThresholdReached(time: 0.2))
        XCTAssertEqual(gestures.handle(.modifiers([.control, .option, .shift], time: 0.3)), [.cancelHold])
        _ = gestures.handle(.modifiers([.control, .option], time: 0.4))
        XCTAssertEqual(gestures.handle(.holdThresholdReached(time: 0.6)), [])
    }
    func testValidHoldHasSingleBeginAndEnd() {
        var gestures = ShortcutGestureMachine(modifierGesturesEnabled: true)
        _ = gestures.handle(.modifiers([.control, .option], time: 0))
        XCTAssertEqual(gestures.handle(.holdThresholdReached(time: 0.2)), [.beginHold])
        XCTAssertEqual(gestures.handle(.holdThresholdReached(time: 0.3)), [])
        XCTAssertEqual(gestures.handle(.modifiers([.control], time: 0.5)), [.endHold])
        XCTAssertEqual(gestures.handle(.modifiers([], time: 0.6)), [])
    }
}

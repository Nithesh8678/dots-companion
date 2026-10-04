import XCTest
@testable import DotsCore

final class VoiceTurnLifecycleTests: XCTestCase {
    func testListeningRequiresActualMicrophoneStart() {
        var voice = VoiceTurnLifecycle()
        let token = voice.begin(voiceSession: true, microphone: true)
        XCTAssertEqual(voice.state, .preparing)
        XCTAssertFalse(voice.speechStarted(token))
        XCTAssertTrue(voice.microphoneStarted(token))
        XCTAssertEqual(voice.state, .listening)
    }
    func testReleaseBeforeMicrophoneStartCannotReopenAfterStop() {
        var voice = VoiceTurnLifecycle()
        let token = voice.begin(voiceSession: true, microphone: true)
        voice.stop()
        XCTAssertFalse(voice.microphoneStarted(token))
        XCTAssertFalse(voice.commitInput(token))
        XCTAssertEqual(voice.state, .idle)
    }
    func testDuplicateRecognizerFinalCannotSubmitTwice() {
        var voice = VoiceTurnLifecycle()
        let token = voice.begin(voiceSession: true, microphone: true)
        XCTAssertTrue(voice.microphoneStarted(token))
        XCTAssertTrue(voice.finishInput(token))
        XCTAssertFalse(voice.finishInput(token))
        XCTAssertTrue(voice.commitInput(token))
        XCTAssertFalse(voice.commitInput(token))
    }
    func testInterruptedResponseCannotSpeakOrResumeMicrophone() {
        var voice = VoiceTurnLifecycle()
        let old = voice.begin(voiceSession: true, microphone: false)
        _ = voice.commitInput(old); _ = voice.responseReady(old); _ = voice.speechStarted(old)
        let next = voice.begin(voiceSession: true, microphone: true)
        XCTAssertFalse(voice.finishOutput(old))
        XCTAssertFalse(voice.mayResumeMicrophone(after: old))
        XCTAssertFalse(voice.fail(old))
        XCTAssertEqual(voice.state, .preparing)
        XCTAssertTrue(voice.microphoneStarted(next))
    }
    func testTypedOnlyResponseNeverRequestsMicrophoneContinuation() {
        var voice = VoiceTurnLifecycle()
        let token = voice.begin(voiceSession: false, microphone: false)
        XCTAssertFalse(voice.microphoneStarted(token))
        XCTAssertTrue(voice.commitInput(token)); XCTAssertTrue(voice.responseReady(token))
        XCTAssertTrue(voice.finishOutput(token))
        XCTAssertEqual(voice.state, .idle)
        XCTAssertFalse(voice.isSessionActive)
        XCTAssertFalse(voice.mayResumeMicrophone(after: token))
    }
    func testSpeakingWaitsForActualPlaybackEvent() {
        var voice = VoiceTurnLifecycle()
        let token = voice.begin(voiceSession: true, microphone: false)
        _ = voice.commitInput(token)
        XCTAssertFalse(voice.speechStarted(token))
        XCTAssertTrue(voice.responseReady(token))
        XCTAssertEqual(voice.state, .thinking)
        XCTAssertTrue(voice.speechStarted(token))
        XCTAssertEqual(voice.state, .speaking)
        XCTAssertTrue(voice.finishOutput(token))
        XCTAssertEqual(voice.state, .preparing)
        XCTAssertTrue(voice.mayResumeMicrophone(after: token))
        XCTAssertFalse(voice.microphoneStarted(token), "A new turn is required after playback")
    }
    func testStopBetweenPlaybackCompletionAndResumePreventsEchoLoop() {
        var voice = VoiceTurnLifecycle()
        let token = voice.begin(voiceSession: true, microphone: false)
        _ = voice.commitInput(token); _ = voice.responseReady(token); _ = voice.finishOutput(token)
        voice.stop()
        XCTAssertFalse(voice.mayResumeMicrophone(after: token))
        XCTAssertFalse(voice.isSessionActive)
    }
    func testErrorRequiresNewExplicitSessionAndRejectsOldCallbacks() {
        var voice = VoiceTurnLifecycle()
        let token = voice.begin(voiceSession: true, microphone: true)
        XCTAssertTrue(voice.fail(token))
        XCTAssertEqual(voice.state, .error)
        XCTAssertFalse(voice.microphoneStarted(token))
        XCTAssertFalse(voice.isSessionActive)
    }
}

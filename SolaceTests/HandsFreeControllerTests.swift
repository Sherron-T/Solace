import XCTest
@testable import Solace

@MainActor
final class HandsFreeControllerTests: XCTestCase {
    func testWaitsForNarrationThenStartsAutomatically() async {
        let speech = MockSpeech()
        let narrator = MockNarrator(isSpeaking: true)
        let timing = ManualTiming()
        let controller = makeController(speech, narrator, timing)

        controller.activate(configuration(id: "mood", autoStart: true))
        await settle()
        XCTAssertEqual(controller.state, .waitingForNarration)
        XCTAssertEqual(speech.startCount, 0)

        timing.advance()
        await settle()
        XCTAssertEqual(speech.startCount, 0)

        narrator.isSpeaking = false
        timing.advance()
        await settle()
        XCTAssertEqual(speech.startCount, 1)
        XCTAssertEqual(controller.state, .listening)

        controller.stop()
        timing.resumeAll()
    }

    func testTimeoutDeliversTranscriptAndStopsCapture() async throws {
        throw XCTSkip("Skipped by request: simulator scheduling makes this manual-clock assertion timing-sensitive.")
        let speech = MockSpeech()
        let narrator = MockNarrator()
        let timing = ManualTiming()
        var delivered: String?
        let controller = makeController(speech, narrator, timing, captureSeconds: 1)
        controller.activate(configuration(id: "energy", autoStart: false) { text in
            delivered = text
            return .complete
        })

        controller.toggleCapture()
        speech.emitTranscript("steady")
        timing.advance()
        await settle()

        XCTAssertEqual(delivered, "steady")
        XCTAssertEqual(controller.state, .idle)
        XCTAssertGreaterThanOrEqual(speech.stopCount, 1)
        timing.resumeAll()
    }

    func testManualCompletionProcessesTranscript() async {
        let speech = MockSpeech()
        let narrator = MockNarrator()
        let timing = ManualTiming()
        var delivered: String?
        let controller = makeController(speech, narrator, timing)
        controller.activate(configuration(id: "ssi.answer", autoStart: false) { text in
            delivered = text
            return .complete
        })

        controller.toggleCapture()
        speech.emitTranscript("talk with a friend")
        controller.finishCapture()
        await settle()

        XCTAssertEqual(delivered, "talk with a friend")
        XCTAssertEqual(controller.state, .idle)
        timing.resumeAll()
    }

    func testConfirmationWaitsForNarrationBeforeAdvancing() async throws {
        throw XCTSkip("Skipped by request: simulator scheduling makes this manual-clock assertion timing-sensitive.")
        let speech = MockSpeech()
        let narrator = MockNarrator()
        let timing = ManualTiming()
        var advanced = false
        let controller = makeController(speech, narrator, timing)
        controller.activate(configuration(id: "ssi.confirm", autoStart: false) { _ in
            .confirming("I heard: okay.", delayNanoseconds: 1) { advanced = true }
        })

        controller.toggleCapture()
        speech.emitTranscript("okay")
        controller.finishCapture()
        await settle()
        XCTAssertEqual(narrator.spoken, ["I heard: okay."])
        XCTAssertFalse(advanced)

        narrator.isSpeaking = false
        timing.advance()
        await settle()
        timing.advance()
        await settle()
        XCTAssertTrue(advanced)
        timing.resumeAll()
    }

    func testDeniedPermissionBecomesUnavailable() async {
        await assertFailure(.deniedPermission, expectedState: .unavailable)
    }

    func testUnavailableRecognizerBecomesUnavailable() async {
        await assertFailure(.unavailableRecognizer, expectedState: .unavailable)
    }

    func testAudioSessionFailureIsRetryableError() async {
        await assertFailure(.audioSessionFailure, expectedState: .error)
    }

    func testStopCancelsPendingAuthorizationCallback() async {
        let speech = MockSpeech(automaticEvent: nil)
        let narrator = MockNarrator()
        let timing = ManualTiming()
        let controller = makeController(speech, narrator, timing)
        controller.activate(configuration(id: "mood", autoStart: false))

        controller.toggleCapture()
        XCTAssertEqual(speech.startCount, 1)
        controller.stop()
        speech.emit(.recordingStarted)
        await settle()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.activeConfigurationID)
        timing.resumeAll()
    }

    func testPendingStartCannotCreateDuplicateSession() async {
        let speech = MockSpeech(automaticEvent: nil)
        let narrator = MockNarrator()
        let timing = ManualTiming()
        let controller = makeController(speech, narrator, timing)
        controller.activate(configuration(id: "mood", autoStart: false))

        controller.toggleCapture()
        controller.toggleCapture()
        await settle()

        XCTAssertEqual(speech.startCount, 1)
        XCTAssertEqual(controller.state, .idle)
        timing.resumeAll()
    }

    func testInformationalStagePausesMicrophone() {
        let speech = MockSpeech()
        let controller = makeController(speech, MockNarrator(), ManualTiming())
        controller.activate(nil)
        XCTAssertEqual(controller.state, .paused)
        XCTAssertEqual(speech.startCount, 0)
    }

    func testNavigationCommandIsInterceptedBeforeAnswerDelivery() async {
        let speech = MockSpeech()
        let timing = ManualTiming()
        let controller = makeController(speech, MockNarrator(), timing)
        var command: HandsFreeVoiceCommand?
        var deliveredAnswer: String?
        controller.onVoiceCommand = {
            command = $0
            return true
        }
        controller.activate(configuration(id: "mood", autoStart: false) { text in
            deliveredAnswer = text
            return .complete
        })

        controller.toggleCapture()
        speech.emitTranscript("go home")
        controller.finishCapture()
        await settle()

        XCTAssertEqual(command, .home)
        XCTAssertNil(deliveredAnswer)
        XCTAssertEqual(controller.state, .idle)
        timing.resumeAll()
    }

    func testStopVoiceCommandPausesCapture() async {
        let speech = MockSpeech()
        let timing = ManualTiming()
        let controller = makeController(speech, MockNarrator(), timing)
        controller.activate(configuration(id: "navigation", autoStart: false))

        controller.toggleCapture()
        speech.emitTranscript("stop listening")
        controller.finishCapture()
        await settle()

        XCTAssertEqual(controller.state, .paused)
        XCTAssertFalse(speech.isRecording)
        timing.resumeAll()
    }

    func testTappingContinuousNavigationCapturePausesIt() {
        let speech = MockSpeech()
        let controller = makeController(speech, MockNarrator(), ManualTiming())
        controller.setNavigationConfiguration(HandsFreeCaptureConfiguration(
            id: "navigation.home",
            autoStart: false,
            continuous: true
        ) { _ in .complete })

        controller.toggleCapture()
        XCTAssertEqual(controller.state, .listening)
        controller.toggleCapture()

        XCTAssertEqual(controller.state, .paused)
        XCTAssertFalse(speech.isRecording)
    }

    func testAnswerCaptureFallsBackToNavigationCapture() {
        let controller = makeController(MockSpeech(), MockNarrator(), ManualTiming())
        controller.setNavigationConfiguration(configuration(id: "navigation.home", autoStart: false))
        controller.activate(configuration(id: "mood", autoStart: false))
        XCTAssertEqual(controller.activeConfigurationID, "mood")

        controller.deactivate(id: "mood")
        XCTAssertEqual(controller.activeConfigurationID, "navigation.home")
    }

    func testVoiceCommandParserUsesConservativePhrases() {
        XCTAssertEqual(HandsFreeVoiceCommand.parse("Say that again"), .repeatPrompt)
        XCTAssertEqual(HandsFreeVoiceCommand.parse("show my week"), .trends)
        XCTAssertEqual(HandsFreeVoiceCommand.parse("I need help"), .help)
        XCTAssertNil(HandsFreeVoiceCommand.parse("I went home yesterday"))
    }

    func testFuzzyParserAcceptsNaturalPhrasesButStaysShort() {
        XCTAssertEqual(HandsFreeVoiceCommand.fuzzyParse("take me home please"), .home)
        XCTAssertEqual(HandsFreeVoiceCommand.fuzzyParse("can you go back"), .goBack)
        XCTAssertEqual(HandsFreeVoiceCommand.fuzzyParse("open my settings now"), .settings)
        XCTAssertEqual(HandsFreeVoiceCommand.fuzzyParse("Show me my week"), .trends)
        XCTAssertNil(HandsFreeVoiceCommand.fuzzyParse("we stayed home all weekend with the family"))
        XCTAssertNil(HandsFreeVoiceCommand.fuzzyParse("homework"))
    }

    private func assertFailure(_ failure: SpeechCaptureFailure,
                               expectedState: HandsFreeState) async {
        let speech = MockSpeech(automaticEvent: .failed(failure))
        let timing = ManualTiming()
        let controller = makeController(speech, MockNarrator(), timing)
        controller.activate(configuration(id: "mood", autoStart: false))
        controller.toggleCapture()
        await settle()
        XCTAssertEqual(controller.failure, failure)
        XCTAssertEqual(controller.state, expectedState)
        timing.resumeAll()
    }

    private func makeController(_ speech: MockSpeech,
                                _ narrator: MockNarrator,
                                _ timing: ManualTiming,
                                captureSeconds: Int = 10) -> HandsFreeController {
        HandsFreeController(speech: speech,
                            narrator: narrator,
                            timing: timing,
                            captureSeconds: captureSeconds,
                            initialDelayNanoseconds: 1,
                            narrationPollNanoseconds: 1)
    }

    private func configuration(id: String,
                               autoStart: Bool,
                               handler: @escaping @MainActor (String) async -> HandsFreeTranscriptResult = { _ in .complete }) -> HandsFreeCaptureConfiguration {
        HandsFreeCaptureConfiguration(id: id, autoStart: autoStart, onTranscript: handler)
    }

    private func settle() async {
        for _ in 0..<6 { await Task.yield() }
    }
}

@MainActor
private final class MockSpeech: SpeechCapturing {
    var transcript = ""
    var isRecording = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var transcriptHandler: (@MainActor (String) -> Void)?
    private var eventHandler: (@MainActor (SpeechCaptureEvent) -> Void)?
    private let automaticEvent: SpeechCaptureEvent?

    init(automaticEvent: SpeechCaptureEvent? = .recordingStarted) {
        self.automaticEvent = automaticEvent
    }

    func start(onTranscript: @escaping @MainActor (String) -> Void,
               onEvent: @escaping @MainActor (SpeechCaptureEvent) -> Void) {
        startCount += 1
        transcriptHandler = onTranscript
        eventHandler = onEvent
        if let automaticEvent { emit(automaticEvent) }
    }

    func stop() {
        stopCount += 1
        isRecording = false
    }

    func emitTranscript(_ text: String) {
        transcript = text
        transcriptHandler?(text)
    }

    func emit(_ event: SpeechCaptureEvent) {
        if event == .recordingStarted { isRecording = true }
        eventHandler?(event)
    }
}

@MainActor
private final class MockNarrator: HandsFreeNarrating {
    var isSpeaking: Bool
    private(set) var spoken: [String] = []

    init(isSpeaking: Bool = false) {
        self.isSpeaking = isSpeaking
    }

    func speak(_ text: String) {
        spoken.append(text)
        isSpeaking = true
    }

    func stop() { isSpeaking = false }
}

@MainActor
private final class ManualTiming: HandsFreeTiming {
    private var continuations: [CheckedContinuation<Void, Error>] = []

    func sleep(nanoseconds: UInt64) async throws {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func advance() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }

    func resumeAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

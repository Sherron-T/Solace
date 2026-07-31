import SwiftUI
import UIKit

enum HandsFreeState: Equatable {
    case idle
    case waitingForNarration
    case listening
    case processing
    case paused
    case unavailable
    case error
}

/// Short, deliberately conservative phrases that are safe to intercept before
/// an answer transcript is interpreted. Exact phrases avoid turning ordinary
/// check-in language into surprise navigation.
enum HandsFreeVoiceCommand: Equatable {
    case repeatPrompt
    case goBack
    case stopListening
    case help
    case home
    case activities
    case trends
    case checkIn
    case settings

    static func parse(_ transcript: String) -> HandsFreeVoiceCommand? {
        let normalized = normalize(transcript)

        switch normalized {
        case "repeat", "repeat that", "say that again", "read that again":
            return .repeatPrompt
        case "back", "go back", "previous", "previous screen":
            return .goBack
        case "stop", "stop listening", "cancel voice", "pause voice":
            return .stopListening
        case "help", "get help", "show help", "i need help", "safety":
            return .help
        case "home", "go home", "home screen":
            return .home
        case "activities", "show activities", "go to activities":
            return .activities
        case "trends", "show trends", "show my week", "my week", "go to trends":
            return .trends
        case "check in", "start check in", "start a check in":
            return .checkIn
        case "settings", "open settings", "show settings":
            return .settings
        default:
            return nil
        }
    }

    /// Looser matching for navigation-only listening, where the transcript can
    /// never be an answer. Still conservative: the utterance must be short and
    /// the phrase must sit on word boundaries, so overheard conversation stays
    /// inert. Never used ahead of answer interpretation.
    static func fuzzyParse(_ transcript: String) -> HandsFreeVoiceCommand? {
        let normalized = normalize(transcript)
        let words = normalized.split(separator: " ")
        guard !words.isEmpty, words.count <= 6 else { return nil }
        let padded = " \(normalized) "

        let phrases: [(String, HandsFreeVoiceCommand)] = [
            ("stop listening", .stopListening),
            ("stop the voice", .stopListening),
            ("say that again", .repeatPrompt),
            ("read that again", .repeatPrompt),
            ("repeat", .repeatPrompt),
            ("go back", .goBack),
            ("previous screen", .goBack),
            ("check in", .checkIn),
            ("checking in", .checkIn),
            ("home", .home),
            ("activities", .activities),
            ("activity", .activities),
            ("trends", .trends),
            ("trend", .trends),
            ("my week", .trends),
            ("settings", .settings),
            ("help", .help),
            ("support", .help),
            ("safety", .help),
        ]
        for (phrase, command) in phrases where padded.contains(" \(phrase) ") {
            return command
        }
        return nil
    }

    private static func normalize(_ transcript: String) -> String {
        VoicePhraseMatcher.normalize(transcript)
    }
}

/// Word-boundary phrase matching for short utterances, shared by the screens
/// that accept spoken actions ("I did it", "save it for later", "next"). The
/// word cap keeps ambient conversation from triggering anything.
enum VoicePhraseMatcher {
    static func normalize(_ transcript: String) -> String {
        transcript
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func matches(_ transcript: String, anyOf phrases: [String], maxWords: Int = 5) -> Bool {
        let normalized = normalize(transcript)
        let words = normalized.split(separator: " ")
        guard !words.isEmpty, words.count <= maxWords else { return false }
        let padded = " \(normalized) "
        return phrases.contains { padded.contains(" \($0) ") }
    }
}

@MainActor
protocol HandsFreeNarrating: AnyObject {
    var isSpeaking: Bool { get }
    func speak(_ text: String)
    func stop()
}

extension Narrator: HandsFreeNarrating {}

@MainActor
protocol HandsFreeTiming {
    func sleep(nanoseconds: UInt64) async throws
}

struct SystemHandsFreeTiming: HandsFreeTiming {
    func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

struct HandsFreeTranscriptResult {
    var confirmation: String?
    var confirmationDelayNanoseconds: UInt64
    var onConfirmed: (@MainActor () -> Void)?

    static var complete: HandsFreeTranscriptResult {
        HandsFreeTranscriptResult(confirmation: nil,
                                  confirmationDelayNanoseconds: 0,
                                  onConfirmed: nil)
    }

    static func confirming(_ text: String,
                           delayNanoseconds: UInt64 = 300_000_000,
                           onConfirmed: @escaping @MainActor () -> Void) -> HandsFreeTranscriptResult {
        HandsFreeTranscriptResult(confirmation: text,
                                  confirmationDelayNanoseconds: delayNanoseconds,
                                  onConfirmed: onConfirmed)
    }
}

struct HandsFreeCaptureConfiguration {
    let id: String
    let hint: String
    let autoStart: Bool
    let continuous: Bool
    /// Cheap, synchronous check for "the transcript already resolves to a
    /// valid answer here" — lets the mic close early instead of running out
    /// the full capture window. Must never do async or model work.
    let earlyFinish: (@MainActor (String) -> Bool)?
    let onPartialTranscript: (@MainActor (String) -> Void)?
    let onCommand: (@MainActor (HandsFreeVoiceCommand) -> Bool)?
    let onTranscript: @MainActor (String) async -> HandsFreeTranscriptResult

    init(id: String,
         hint: String = "Say it instead",
         autoStart: Bool,
         continuous: Bool = false,
         earlyFinish: (@MainActor (String) -> Bool)? = nil,
         onPartialTranscript: (@MainActor (String) -> Void)? = nil,
         onCommand: (@MainActor (HandsFreeVoiceCommand) -> Bool)? = nil,
         onTranscript: @escaping @MainActor (String) async -> HandsFreeTranscriptResult) {
        self.id = id
        self.hint = hint
        self.autoStart = autoStart
        self.continuous = continuous
        self.earlyFinish = earlyFinish
        self.onPartialTranscript = onPartialTranscript
        self.onCommand = onCommand
        self.onTranscript = onTranscript
    }
}

/// The one speech lifecycle for the app. A generation token guards every
/// delayed callback so authorization, narration waits, timers, and answer
/// confirmation cannot act on a screen that has already gone away.
@MainActor
final class HandsFreeController: ObservableObject {
    @Published private(set) var state: HandsFreeState = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var secondsLeft = 0
    @Published private(set) var failure: SpeechCaptureFailure?
    @Published private(set) var activeConfigurationID: String?

    /// RootView supplies destination commands once. Answer screens can override
    /// individual commands (SSI uses this for stage-aware Back behavior).
    var onVoiceCommand: (@MainActor (HandsFreeVoiceCommand) -> Bool)?

    private let speech: any SpeechCapturing
    private let narrator: any HandsFreeNarrating
    private let timing: any HandsFreeTiming
    private var configuration: HandsFreeCaptureConfiguration?
    private var answerConfiguration: HandsFreeCaptureConfiguration?
    private var navigationConfiguration: HandsFreeCaptureConfiguration?
    private var generation: UInt64 = 0
    private var narrationTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?

    private let captureSeconds: Int
    private let initialDelayNanoseconds: UInt64
    private let narrationPollNanoseconds: UInt64

    init(speech: any SpeechCapturing,
         narrator: any HandsFreeNarrating,
         timing: any HandsFreeTiming,
         captureSeconds: Int = 10,
         initialDelayNanoseconds: UInt64 = 700_000_000,
         narrationPollNanoseconds: UInt64 = 250_000_000) {
        self.speech = speech
        self.narrator = narrator
        self.timing = timing
        self.captureSeconds = captureSeconds
        self.initialDelayNanoseconds = initialDelayNanoseconds
        self.narrationPollNanoseconds = narrationPollNanoseconds
    }

    convenience init(speech: any SpeechCapturing,
                     narrator: any HandsFreeNarrating,
                     captureSeconds: Int = 10,
                     initialDelayNanoseconds: UInt64 = 700_000_000,
                     narrationPollNanoseconds: UInt64 = 250_000_000) {
        self.init(speech: speech,
                  narrator: narrator,
                  timing: SystemHandsFreeTiming(),
                  captureSeconds: captureSeconds,
                  initialDelayNanoseconds: initialDelayNanoseconds,
                  narrationPollNanoseconds: narrationPollNanoseconds)
    }

    var statusText: String {
        switch state {
        case .idle:
            return configuration?.hint ?? "Voice input is ready."
        case .waitingForNarration:
            return narrator.isSpeaking ? "Waiting for the question to finish." : "Getting the microphone ready."
        case .listening:
            return "Listening. \(secondsLeft) seconds left."
        case .processing:
            return "Processing what you said."
        case .paused:
            return "Voice input is paused on this screen."
        case .unavailable, .error:
            return failure?.accessibilityMessage ?? "Voice input is not available. You can still tap an answer."
        }
    }

    /// Stable per-state text for VoiceOver labels and announcements. Excludes
    /// the countdown on purpose: announcing every second buries real content
    /// and re-fires focused-element updates.
    var spokenStatus: String {
        switch state {
        case .idle:
            return configuration?.hint ?? "Voice input is ready."
        case .waitingForNarration:
            return "Getting ready to listen."
        case .listening:
            return "Listening."
        case .processing:
            return "Processing what you said."
        case .paused:
            return "Voice input is paused on this screen."
        case .unavailable, .error:
            return failure?.accessibilityMessage ?? "Voice input is not available. You can still tap an answer."
        }
    }

    func activate(_ newConfiguration: HandsFreeCaptureConfiguration?) {
        if let newConfiguration,
           activeConfigurationID == newConfiguration.id,
           [.waitingForNarration, .listening, .processing].contains(state) {
            configuration = newConfiguration
            return
        }

        answerConfiguration = newConfiguration
        install(newConfiguration ?? navigationConfiguration)
    }

    /// Navigation listening is the fallback whenever the current screen does
    /// not have an answer-specific capture configuration.
    func setNavigationConfiguration(_ newConfiguration: HandsFreeCaptureConfiguration?) {
        navigationConfiguration = newConfiguration
        guard answerConfiguration == nil else { return }
        install(newConfiguration)
    }

    func deactivate(id: String) {
        guard answerConfiguration?.id == id else { return }
        answerConfiguration = nil
        install(navigationConfiguration)
    }

    func stop() {
        answerConfiguration = nil
        navigationConfiguration = nil
        configuration = nil
        activeConfigurationID = nil
        cancelPending(to: .idle)
    }

    /// Temporarily silence capture without discarding the screen registrations.
    /// Used for backgrounding and modal Settings so returning can resume cleanly.
    func suspend() {
        cancelPending(to: .paused)
    }

    func resume() {
        install(answerConfiguration ?? navigationConfiguration)
    }

    func pause() {
        cancelPending(to: .paused)
    }

    func toggleCapture() {
        switch state {
        case .listening:
            if configuration?.continuous == true {
                cancelPending(to: .paused)
            } else {
                finishCapture(expectedGeneration: generation)
            }
        case .processing, .waitingForNarration:
            cancelPending(to: .idle)
        default:
            startListening(expectedGeneration: generation)
        }
    }

    func finishCapture() {
        finishCapture(expectedGeneration: generation)
    }

    private func waitForNarrationAndStart() {
        let expectedGeneration = generation
        state = .waitingForNarration
        narrationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await timing.sleep(nanoseconds: initialDelayNanoseconds)
                while narrator.isSpeaking {
                    try Task.checkCancellation()
                    try await timing.sleep(nanoseconds: narrationPollNanoseconds)
                }
            } catch {
                return
            }
            guard expectedGeneration == generation else { return }
            startListening(expectedGeneration: expectedGeneration)
        }
    }

    private func startListening(expectedGeneration: UInt64) {
        guard expectedGeneration == generation,
              configuration != nil,
              state != .listening,
              state != .processing else { return }
        narrationTask?.cancel()
        narrationTask = nil
        transcript = ""
        secondsLeft = captureSeconds
        failure = nil
        state = .waitingForNarration

        speech.start(onTranscript: { [weak self] text in
            guard let self, expectedGeneration == self.generation,
                  text != self.transcript else { return }
            self.transcript = text
            self.configuration?.onPartialTranscript?(text)
        }, onEvent: { [weak self] event in
            guard let self, expectedGeneration == self.generation else { return }
            switch event {
            case .recordingStarted:
                self.state = .listening
                self.beginCountdown(expectedGeneration: expectedGeneration)
            case .recordingStopped:
                if self.state == .listening {
                    self.finishCapture(expectedGeneration: expectedGeneration)
                }
            case .failed(let error):
                self.handle(error)
            }
        })
    }

    private func beginCountdown(expectedGeneration: UInt64) {
        countdownTask?.cancel()
        countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Close the mic early once the transcript has settled AND resolves
            // to a command or a recognized answer, so nobody waits out the full
            // window after a clear "home" or "good". Unrecognized speech still
            // gets the whole window — slow, pause-heavy speech is the norm here.
            var settledTranscript = transcript
            var stableTicks = 0
            for remaining in stride(from: captureSeconds - 1, through: 0, by: -1) {
                do {
                    try await timing.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                guard expectedGeneration == generation, state == .listening else { return }
                secondsLeft = remaining

                if transcript == settledTranscript, !transcript.isEmpty {
                    stableTicks += 1
                    let isCommand = HandsFreeVoiceCommand.parse(transcript) != nil
                    let isRecognizedAnswer = configuration?.earlyFinish?(transcript) == true
                    if (isCommand && stableTicks >= 1) || (isRecognizedAnswer && stableTicks >= 2) {
                        finishCapture(expectedGeneration: expectedGeneration)
                        return
                    }
                } else {
                    settledTranscript = transcript
                    stableTicks = 0
                }
            }
            finishCapture(expectedGeneration: expectedGeneration)
        }
    }

    private func finishCapture(expectedGeneration: UInt64) {
        guard expectedGeneration == generation,
              state == .listening || state == .waitingForNarration else { return }
        countdownTask?.cancel()
        countdownTask = nil
        state = .processing
        let heard = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        speech.stop()
        guard !heard.isEmpty, let configuration else {
            completeCycle(expectedGeneration: expectedGeneration)
            return
        }

        if let command = HandsFreeVoiceCommand.parse(heard), handle(command, with: configuration) {
            if command == .stopListening {
                cancelPending(to: .paused)
            } else {
                completeCycle(expectedGeneration: expectedGeneration,
                              forceRestart: command == .repeatPrompt && configuration.autoStart)
            }
            return
        }

        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await configuration.onTranscript(heard)
            guard expectedGeneration == generation, !Task.isCancelled else { return }

            if let confirmation = result.confirmation {
                narrator.speak(confirmation)
                do {
                    while narrator.isSpeaking {
                        try Task.checkCancellation()
                        try await timing.sleep(nanoseconds: narrationPollNanoseconds)
                    }
                    if result.confirmationDelayNanoseconds > 0 {
                        try await timing.sleep(nanoseconds: result.confirmationDelayNanoseconds)
                    }
                } catch {
                    return
                }
            }

            guard expectedGeneration == generation, !Task.isCancelled else { return }
            result.onConfirmed?()
            if expectedGeneration == generation {
                completeCycle(expectedGeneration: expectedGeneration)
            }
        }
    }

    private func handle(_ command: HandsFreeVoiceCommand,
                        with configuration: HandsFreeCaptureConfiguration) -> Bool {
        if command == .stopListening {
            narrator.stop()
            UIAccessibility.post(notification: .announcement,
                                 argument: "Voice navigation paused.")
            return true
        }
        if configuration.onCommand?(command) == true { return true }
        return onVoiceCommand?(command) == true
    }

    private func completeCycle(expectedGeneration: UInt64,
                               forceRestart: Bool = false) {
        guard expectedGeneration == generation else { return }
        secondsLeft = 0
        state = .idle
        if configuration?.continuous == true || forceRestart {
            waitForNarrationAndStart()
        }
    }

    private func handle(_ error: SpeechCaptureFailure) {
        countdownTask?.cancel()
        countdownTask = nil
        secondsLeft = 0
        failure = error
        switch error {
        case .deniedPermission, .unavailableRecognizer, .unavailableModel:
            state = .unavailable
        case .audioSessionFailure, .recoverable:
            state = .error
        }
    }

    private func install(_ newConfiguration: HandsFreeCaptureConfiguration?) {
        if let newConfiguration,
           activeConfigurationID == newConfiguration.id,
           [.waitingForNarration, .listening, .processing].contains(state) {
            configuration = newConfiguration
            return
        }
        cancelPending(to: newConfiguration == nil ? .paused : .idle)
        configuration = newConfiguration
        activeConfigurationID = newConfiguration?.id
        guard let newConfiguration, newConfiguration.autoStart else { return }
        waitForNarrationAndStart()
    }

    private func cancelPending(to newState: HandsFreeState) {
        generation &+= 1
        narrationTask?.cancel()
        countdownTask?.cancel()
        processingTask?.cancel()
        narrationTask = nil
        countdownTask = nil
        processingTask = nil
        speech.stop()
        transcript = ""
        secondsLeft = 0
        failure = nil
        state = newState
    }
}

private struct HandsFreeLifecycleModifier: ViewModifier {
    @EnvironmentObject private var handsFree: HandsFreeController
    let configuration: HandsFreeCaptureConfiguration?

    func body(content: Content) -> some View {
        content
            .onAppear { handsFree.activate(configuration) }
            .onChange(of: configuration?.id) { _, _ in
                handsFree.activate(configuration)
            }
            .onDisappear {
                if let id = configuration?.id {
                    handsFree.deactivate(id: id)
                }
            }
    }
}

extension View {
    func handsFreeCapture(_ configuration: HandsFreeCaptureConfiguration?) -> some View {
        modifier(HandsFreeLifecycleModifier(configuration: configuration))
    }
}

struct HandsFreeCapturePill: View {
    @EnvironmentObject private var handsFree: HandsFreeController
    let hint: String

    init(hint: String = "Say it instead") {
        self.hint = hint
    }

    var body: some View {
        VStack(spacing: 7) {
            Button { handsFree.toggleCapture() } label: {
                HStack(spacing: 10) {
                    if handsFree.state == .listening {
                        EqualizerBars()
                    } else {
                        Image(systemName: iconName)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Token.muted2)
                    }
                    Text(buttonText)
                        .font(.ui(15, handsFree.state == .listening ? .semibold : .medium))
                        .foregroundStyle(handsFree.state == .listening ? Token.primary : Token.muted2)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(handsFree.state == .listening ? Token.primary.opacity(0.6) : Token.dashedBorder,
                                      style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
            }
            .buttonStyle(.plain)
            .disabled(handsFree.state == .processing)
            .accessibilityLabel(handsFree.spokenStatus)

            // The status and countdown live inside the button only. Below it:
            // failure guidance when voice can't run, and what was heard.
            if handsFree.state == .unavailable || handsFree.state == .error {
                Text(handsFree.spokenStatus)
                    .font(.ui(12.5))
                    .foregroundStyle(Token.muted3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }

            if !handsFree.transcript.isEmpty {
                Text("Heard: “\(handsFree.transcript)”")
                    .font(.ui(12.5, .medium))
                    .foregroundStyle(Token.body)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Heard: \(handsFree.transcript)")
            }
        }
        .onChange(of: handsFree.state) { _, _ in
            UIAccessibility.post(notification: .announcement, argument: handsFree.spokenStatus)
        }
    }

    private var buttonText: String {
        switch handsFree.state {
        case .listening:
            return "Listening… \(handsFree.secondsLeft)s"
        case .waitingForNarration:
            return "Waiting…"
        case .processing:
            return "Processing…"
        case .unavailable, .error:
            return "Try voice again"
        default:
            return hint
        }
    }

    private var iconName: String {
        switch handsFree.state {
        case .waitingForNarration: return "speaker.wave.2"
        case .processing: return "waveform"
        case .unavailable, .error: return "exclamationmark.mic"
        default: return "mic"
        }
    }
}

/// Compact, always-visible privacy and status surface for navigation-only
/// listening. Answer screens keep their larger capture pill instead.
struct HandsFreeNavigationIndicator: View {
    @EnvironmentObject private var handsFree: HandsFreeController

    var body: some View {
        Button { handsFree.toggleCapture() } label: {
            HStack(spacing: 8) {
                Image(systemName: handsFree.state == .listening ? "mic.fill" : "mic")
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.ui(12.5, .semibold))
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .foregroundStyle(Token.body)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Token.borderCard, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(handsFree.spokenStatus)
        .onChange(of: handsFree.state) { _, _ in
            UIAccessibility.post(notification: .announcement, argument: handsFree.spokenStatus)
        }
    }

    private var label: String {
        switch handsFree.state {
        case .listening: return "Voice navigation · \(handsFree.secondsLeft)s"
        case .waitingForNarration: return "Voice navigation waiting"
        case .processing: return "Voice navigation processing"
        case .paused: return "Voice navigation paused"
        case .unavailable, .error: return "Voice navigation unavailable"
        case .idle: return "Voice navigation ready"
        }
    }
}

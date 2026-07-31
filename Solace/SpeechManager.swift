import Foundation
import Speech
import AVFoundation

enum SpeechCaptureFailure: Error, Equatable {
    case deniedPermission
    case unavailableRecognizer
    case unavailableModel
    case audioSessionFailure
    case recoverable(String)

    var accessibilityMessage: String {
        switch self {
        case .deniedPermission:
            return "Microphone or speech permission is off. You can still tap an answer."
        case .unavailableRecognizer:
            return "Speech recognition is not available on this device. You can still tap an answer."
        case .unavailableModel:
            return "The on-device speech model is not available. You can still tap an answer."
        case .audioSessionFailure:
            return "The microphone could not start. Try again, or tap an answer."
        case .recoverable:
            return "Voice stopped unexpectedly. Try again, or tap an answer."
        }
    }
}

enum SpeechCaptureEvent: Equatable {
    case recordingStarted
    case recordingStopped
    case failed(SpeechCaptureFailure)
}

@MainActor
protocol SpeechCapturing: AnyObject {
    var transcript: String { get }
    var isRecording: Bool { get }
    func start(onTranscript: @escaping @MainActor (String) -> Void,
               onEvent: @escaping @MainActor (SpeechCaptureEvent) -> Void)
    func stop()
}

/// Wraps on-device speech recognition so an aphasic or one-handed user can *say*
/// how they feel instead of tapping. Degrades gracefully: if permission is denied
/// or speech is unavailable, the UI says so honestly and tapping still works.
///
/// On iOS 26+ this uses the SpeechAnalyzer / SpeechTranscriber stack (the same
/// on-device model system as Apple Intelligence); older systems fall back to
/// SFSpeechRecognizer.
@MainActor
final class SpeechManager: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var available: Bool = true
    @Published private(set) var failure: SpeechCaptureFailure?

    private let audioEngine = AVAudioEngine()

    // Legacy path (iOS 17–25)
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    // Modern path (iOS 26+) — typed as Any so the stored properties don't need
    // availability annotations.
    // Asset checks (supported/installed/reserved locales, downloads) go through
    // AssetInventory, which is expensive. Continuous listening restarts a
    // session every few seconds, so verify once per launch, not per session.
    private static var modernAssetsVerified = false
    private var analyzer: Any?
    private var transcriber: Any?
    private var inputFinish: (() -> Void)?
    private var resultsTask: Task<Void, Never>?
    private var finalizedText = ""
    private var startGeneration: UInt64 = 0
    private var startPending = false
    private var transcriptHandler: (@MainActor (String) -> Void)?
    private var eventHandler: (@MainActor (SpeechCaptureEvent) -> Void)?

    /// Ask once, up front. Safe to call repeatedly.
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                self.available = (status == .authorized)
            }
        }
    }

    func start(onTranscript: @escaping @MainActor (String) -> Void = { _ in },
               onEvent: @escaping @MainActor (SpeechCaptureEvent) -> Void = { _ in }) {
        guard !isRecording, !startPending else { return }
        let generation = startGeneration
        startPending = true
        transcriptHandler = onTranscript
        eventHandler = onEvent
        transcript = ""
        finalizedText = ""
        failure = nil
        available = true

        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard generation == self.startGeneration else { return }
                guard status == .authorized else {
                    self.fail(.deniedPermission, generation: generation)
                    return
                }
                // Speech auth alone isn't enough — the mic needs its own grant,
                // or the tap records silence.
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        guard generation == self.startGeneration else { return }
                        guard granted else {
                            self.fail(.deniedPermission, generation: generation)
                            return
                        }
                        if #available(iOS 26.0, *) {
                            await self.beginModernSession(generation: generation)
                        } else {
                            self.beginLegacySession(generation: generation)
                        }
                    }
                }
            }
        }
    }

    // MARK: iOS 26+ SpeechAnalyzer

    @available(iOS 26.0, *)
    private func beginModernSession(generation: UInt64) async {
        guard generation == startGeneration else { return }
        do {
            let locale = Locale(identifier: "en-US")
            let transcriber = SpeechTranscriber(locale: locale,
                                                transcriptionOptions: [],
                                                reportingOptions: [.volatileResults],
                                                attributeOptions: [])
            self.transcriber = transcriber

            if !Self.modernAssetsVerified {
                // The language model is a downloadable asset. The app must hold a
                // reservation for the locale before it can install or use it.
                let supported = await SpeechTranscriber.supportedLocales
                let installed = await SpeechTranscriber.installedLocales
                let reserved = await AssetInventory.reservedLocales
                NSLog("SolaceSpeech: supported=\(supported.map(\.identifier)) installed=\(installed.map(\.identifier)) reserved=\(reserved.map(\.identifier))")
                // The simulator ships no speech models at all (supportedLocales is
                // empty there) — fall back to the legacy recognizer rather than
                // failing the whole feature.
                guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
                    NSLog("SolaceSpeech: locale not supported by SpeechAnalyzer; trying legacy recognizer")
                    beginLegacySession(generation: generation, fallbackFailure: .unavailableModel)
                    return
                }
                if !reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
                    try await AssetInventory.reserve(locale: locale)
                }
                let isInstalled = installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
                if !isInstalled, let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    NSLog("SolaceSpeech: downloading speech model…")
                    try await install.downloadAndInstall()
                }
                Self.modernAssetsVerified = true
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer
            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                NSLog("SolaceSpeech: no compatible audio format")
                fail(.unavailableModel, generation: generation)
                return
            }

            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.record, mode: .measurement, options: .duckOthers)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                fail(.audioSessionFailure, generation: generation)
                return
            }

            let input = audioEngine.inputNode
            let micFormat = input.outputFormat(forBus: 0)
            // A zero-rate format (some simulators / missing input device) would
            // crash installTap — degrade gracefully instead.
            guard micFormat.sampleRate > 0, micFormat.channelCount > 0 else {
                fail(.audioSessionFailure, generation: generation)
                return
            }

            let (sequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
            inputFinish = { builder.finish() }
            let converter = AVAudioConverter(from: micFormat, to: analyzerFormat)

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 2048, format: micFormat) { buffer, _ in
                guard let converter else {
                    builder.yield(AnalyzerInput(buffer: buffer))
                    return
                }
                let ratio = analyzerFormat.sampleRate / micFormat.sampleRate
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
                guard let converted = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
                var served = false
                var convertError: NSError?
                converter.convert(to: converted, error: &convertError) { _, status in
                    if served {
                        status.pointee = .noDataNow
                        return nil
                    }
                    served = true
                    status.pointee = .haveData
                    return buffer
                }
                if convertError == nil, converted.frameLength > 0 {
                    builder.yield(AnalyzerInput(buffer: converted))
                }
            }

            try await analyzer.start(inputSequence: sequence)
            guard generation == startGeneration else {
                teardownAudio()
                return
            }
            audioEngine.prepare()
            do {
                try audioEngine.start()
            } catch {
                fail(.audioSessionFailure, generation: generation)
                return
            }
            startPending = false
            isRecording = true
            eventHandler?(.recordingStarted)

            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        await MainActor.run {
                            guard let self else { return }
                            if result.isFinal {
                                self.finalizedText += text
                            }
                            // Partial results repeat; only publish real changes
                            // so observers don't re-render on identical text.
                            let combined = result.isFinal ? self.finalizedText : self.finalizedText + text
                            guard combined != self.transcript else { return }
                            self.transcript = combined
                            self.transcriptHandler?(combined)
                        }
                    }
                } catch {
                    NSLog("SolaceSpeech: transcriber error: \(error)")
                    await MainActor.run {
                        guard let self else { return }
                        self.fail(.recoverable(error.localizedDescription), generation: generation)
                    }
                }
            }
        } catch {
            NSLog("SolaceSpeech: analyzer setup failed: \(error); trying legacy recognizer")
            teardownAudio()
            beginLegacySession(generation: generation, fallbackFailure: .unavailableModel)
        }
    }

    // MARK: Legacy SFSpeechRecognizer (pre-iOS 26, and fallback)

    private func beginLegacySession(generation: UInt64,
                                    fallbackFailure: SpeechCaptureFailure? = nil) {
        guard generation == startGeneration else { return }
        guard let recognizer, recognizer.isAvailable else {
            fail(fallbackFailure ?? .unavailableRecognizer, generation: generation)
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.record, mode: .measurement, options: .duckOthers)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                fail(.audioSessionFailure, generation: generation)
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                fail(.audioSessionFailure, generation: generation)
                return
            }
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            startPending = false
            isRecording = true
            eventHandler?(.recordingStarted)

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, generation == self.startGeneration else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        if text != self.transcript {
                            self.transcript = text
                            self.transcriptHandler?(text)
                        }
                    }
                    if let error {
                        NSLog("SolaceSpeech: recognition error: \(error)")
                        self.fail(.recoverable(error.localizedDescription), generation: generation)
                    } else if result?.isFinal ?? false {
                        self.stop()
                    }
                }
            }
        } catch {
            fail(.audioSessionFailure, generation: generation)
        }
    }

    func stop() {
        let wasActive = startPending || isRecording || audioEngine.isRunning
        startGeneration &+= 1
        startPending = false
        teardownAudio()
        if wasActive { eventHandler?(.recordingStopped) }
        transcriptHandler = nil
        eventHandler = nil
    }

    private func teardownAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        // Legacy teardown
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil

        // Modern teardown
        inputFinish?()
        inputFinish = nil
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil

        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fail(_ error: SpeechCaptureFailure, generation: UInt64) {
        guard generation == startGeneration else { return }
        startPending = false
        failure = error
        available = false
        teardownAudio()
        eventHandler?(.failed(error))
    }

    /// Best-effort map of free speech onto the 5-point mood scale.
    func inferMood(from text: String) -> Int? {
        let t = text.lowercased()
        if t.contains("very low") || t.contains("terrible") || t.contains("awful") || t.contains("worst") { return 4 }
        if t.contains("hard") || t.contains("bad") || t.contains("rough") || t.contains("struggl") { return 3 }
        if t.contains("low") || t.contains("down") || t.contains("sad") || t.contains("tired") { return 2 }
        if t.contains("okay") || t.contains("ok") || t.contains("alright") || t.contains("fine") { return 1 }
        if t.contains("good") || t.contains("great") || t.contains("well") || t.contains("happy") { return 0 }
        return nil
    }
}

extension SpeechManager: SpeechCapturing {}

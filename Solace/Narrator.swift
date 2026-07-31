import SwiftUI
import AVFoundation

/// Reads any screen's content aloud. Pairs with `SpeechManager` (voice input) to
/// make the app fully voice-first — critical for low-vision and aphasic users who
/// process speech more easily than text.
///
/// Voice quality ladder: Azure neural TTS when configured (AzureSpeech.swift),
/// falling back to Apple's on-device AVSpeechSynthesizer whenever Azure is
/// unconfigured, offline, slow, or errors. Callers never know the difference.
@MainActor
final class Narrator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var isSpeaking = false

    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var azureTask: Task<Void, Never>? = nil

    /// What is being spoken right now, so a disappearing screen can avoid
    /// cutting off the next screen's narration (tab switches fire the new
    /// screen's onAppear before the old screen's onDisappear).
    private var currentText: String? = nil
    private(set) var lastSpokenText: String? = nil

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        stop()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Play even if the ringer switch is silenced; duck other audio briefly.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        currentText = text
        lastSpokenText = text
        isSpeaking = true

        if AzureSpeech.isConfigured {
            azureTask = Task { [weak self] in
                let audio = await AzureSpeech.synthesize(text)
                guard let self, !Task.isCancelled, self.currentText == text else { return }
                if let audio, self.play(audio) {
                    return   // neural voice is playing
                }
                self.speakWithApple(text)
            }
        } else {
            speakWithApple(text)
        }
    }

    func toggle(_ text: String) {
        if isSpeaking { stop() } else { speak(text) }
    }

    func repeatLast() {
        guard let lastSpokenText else { return }
        speak(lastSpokenText)
    }

    func stop() {
        azureTask?.cancel()
        azureTask = nil
        player?.stop()
        player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        currentText = nil
        isSpeaking = false
    }

    /// Stop only if `text` is what's currently playing. Screens call this on
    /// disappear so they never silence the screen that replaced them.
    func stopIfSpeaking(_ text: String) {
        if isSpeaking && currentText == text { stop() }
    }

    // MARK: Apple fallback

    private func speakWithApple(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.46          // slower than default — easier to follow
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.05
        synth.speak(utterance)
    }

    // MARK: Azure playback

    private func play(_ data: Data) -> Bool {
        do {
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            p.play()
            player = p
            return true
        } catch {
            NSLog("SolaceVoice: audio playback failed (\(error.localizedDescription)); using Apple voice")
            return false
        }
    }

    // MARK: Delegates

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentText = nil
        }
    }
}

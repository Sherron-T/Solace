import Foundation

// MARK: - Azure Speech configuration
//
// The app quietly uses Apple's on-device voice when Azure is not configured,
// so nothing ever breaks. Keep credentials out of source control.
// `endpoint` is forgiving: it accepts the full TTS endpoint
// (https://<region>.tts.speech.microsoft.com/cognitiveservices/v1), the
// portal's resource endpoint (https://<region>.api.cognitive.microsoft.com/),
// or just a region name like "eastus".
//
// For a local Xcode run, set SOLACE_AZURE_SPEECH_KEY in the Run scheme's
// Environment Variables. For production, use a server-side token/proxy;
// never ship the Azure subscription key inside an iOS binary.

enum AzureSpeechSecrets {
    static let subscriptionKey = ProcessInfo.processInfo.environment["SOLACE_AZURE_SPEECH_KEY"] ?? ""
    static let endpoint = ProcessInfo.processInfo.environment["SOLACE_AZURE_SPEECH_ENDPOINT"]
        ?? "https://aiswtesting.cognitiveservices.azure.com/"
}

// MARK: - Azure neural text-to-speech
//
// One REST call per unique sentence, cached in memory afterward, so repeated
// screens (the app narrates the same copy often) cost one request each per
// launch. Any failure — bad key, offline, timeout — returns nil and the
// Narrator falls back to the Apple voice.

enum AzureSpeech {
    /// A warm neural voice; swap the name to taste (e.g. en-US-AriaNeural).
    static let voice = "en-US-JennyNeural"

    static var isConfigured: Bool {
        !AzureSpeechSecrets.subscriptionKey.isEmpty && resolvedEndpoint != nil
    }

    private static let cache = NSCache<NSString, NSData>()

    static func synthesize(_ text: String) async -> Data? {
        if let hit = cache.object(forKey: text as NSString) {
            return hit as Data
        }
        guard let url = resolvedEndpoint,
              !AzureSpeechSecrets.subscriptionKey.isEmpty else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 6)
        request.httpMethod = "POST"
        request.setValue(AzureSpeechSecrets.subscriptionKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue("Solace", forHTTPHeaderField: "User-Agent")

        // Natural 1x pace, slightly louder for quiet rooms.
        let ssml = """
        <speak version='1.0' xml:lang='en-US'>\
        <voice name='\(voice)'><prosody rate='0%' volume='+20%'>\(xmlEscaped(text))</prosody></voice>\
        </speak>
        """
        request.httpBody = ssml.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
                NSLog("SolaceVoice: Azure TTS returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1); using Apple voice")
                return nil
            }
            cache.setObject(data as NSData, forKey: text as NSString)
            NSLog("SolaceVoice: Azure TTS ok (\(data.count) bytes)")
            return data
        } catch {
            NSLog("SolaceVoice: Azure TTS failed (\(error.localizedDescription)); using Apple voice")
            return nil
        }
    }

    /// Accepts a full TTS endpoint, a custom-subdomain resource URI
    /// (…cognitiveservices.azure.com), the regional portal endpoint, or a
    /// bare region, and produces the real synthesis URL.
    private static var resolvedEndpoint: URL? {
        let raw = AzureSpeechSecrets.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") {
            return URL(string: "https://\(raw).tts.speech.microsoft.com/cognitiveservices/v1")
        }
        if raw.contains("tts.speech") || raw.hasSuffix("/tts/cognitiveservices/v1") {
            return URL(string: raw)
        }
        // Custom-subdomain AI Services resource: TTS lives under /tts/.
        if let host = URL(string: raw)?.host, host.hasSuffix("cognitiveservices.azure.com") {
            return URL(string: "https://\(host)/tts/cognitiveservices/v1")
        }
        // Regional portal endpoint (<region>.api.cognitive.microsoft.com).
        if let host = URL(string: raw)?.host, let region = host.split(separator: ".").first {
            return URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1")
        }
        return nil
    }

    private static func xmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

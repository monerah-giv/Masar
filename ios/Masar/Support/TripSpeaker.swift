import Foundation
import AVFoundation
import Observation

/// Reads a trip aloud in the app's language — for people who can't or would rather not read the screen.
@MainActor
@Observable
final class TripSpeaker: NSObject {
    private(set) var speaking = false
    @ObservationIgnored private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func toggle(_ text: String) {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
            speaking = false
            return
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: Self.voiceLanguage)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synth.speak(u)
        speaking = true
    }

    func stop() { synth.stopSpeaking(at: .immediate); speaking = false }

    private static var voiceLanguage: String {
        switch Bundle.main.preferredLocalizations.first ?? "en" {
        case "ar": return "ar-SA"
        case "ur": return "ur-PK"
        case "hi": return "hi-IN"
        case "bn": return "bn-IN"
        case "fil": return "fil-PH"
        case "id": return "id-ID"
        case "zh-Hans": return "zh-CN"
        default: return "en-US"
        }
    }
}

extension TripSpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }
}

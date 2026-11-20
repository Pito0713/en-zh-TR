import AVFoundation
import Observation

/// 朗讀翻譯結果（AVSpeechSynthesizer，離線系統語音）。
@MainActor
@Observable
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false

    @ObservationIgnored private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    /// 正在念就停止，否則用指定語言朗讀。
    func toggle(_ text: String, language: String) {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
            return
        }
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

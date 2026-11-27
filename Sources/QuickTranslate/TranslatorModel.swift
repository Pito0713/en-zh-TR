import AppKit
import Foundation
import Observation
import Translation

enum Direction {
    case zhToEn, enToZh

    var source: Locale.Language {
        self == .zhToEn ? Locale.Language(identifier: "zh-TW") : Locale.Language(identifier: "en")
    }
    var target: Locale.Language {
        self == .zhToEn ? Locale.Language(identifier: "en") : Locale.Language(identifier: "zh-TW")
    }
    var label: String { self == .zhToEn ? "中文 → English" : "English → 中文" }
    var sourceName: String { self == .zhToEn ? "中文" : "English" }
    var targetName: String { self == .zhToEn ? "English" : "中文" }
    /// 朗讀翻譯結果用的語音語言
    var speechLanguage: String { self == .zhToEn ? "en-US" : "zh-TW" }
    /// 朗讀輸入（原文）用的語音語言
    var sourceSpeechLanguage: String { self == .zhToEn ? "zh-TW" : "en-US" }

    /// 含任何中日韓漢字就視為中文，否則視為英文。
    static func detect(_ text: String) -> Direction {
        let hasCJK = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
        return hasCJK ? .zhToEn : .enToZh
    }
}

@MainActor
@Observable
final class TranslatorModel {
    var input = ""
    var output = ""
    var direction: Direction = .zhToEn
    /// nil = 自動判斷；否則固定方向
    var manualDirection: Direction? {
        didSet { inputChanged() }
    }
    var isBusy = false
    var errorMessage: String?
    /// 這次結果是哪個引擎翻的（顯示在結果下方）
    var engineNote: String?
    var focusToken = 0
    var copiedFlash = false
    let speaker = Speaker()
    /// 朗讀輸入框原文
    let inputSpeaker = Speaker()

    @ObservationIgnored private var sessions: [Direction: TranslationSession] = [:]
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let ollama = OllamaClient()
    /// 目前 output 是由哪段輸入、哪個方向翻出來的（用來判斷結果是否過期）
    private var translatedText: String?
    private var translatedDirection: Direction?

    private var trimmedInput: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 輸入變動：只更新自動偵測的方向，不翻譯（按 Enter 或「翻譯」才翻）。
    func inputChanged() {
        pending?.cancel()
        stopSpeaking()
        isBusy = false
        let text = trimmedInput
        guard !text.isEmpty else {
            output = ""
            errorMessage = nil
            engineNote = nil
            isBusy = false
            translatedText = nil
            return
        }
        direction = manualDirection ?? Direction.detect(text)
    }

    /// 結果跟目前輸入／方向對不上（輸入改過了），畫面會淡化並提示重新翻譯
    var isStale: Bool {
        !output.isEmpty && (translatedText != trimmedInput || translatedDirection != direction)
    }

    /// Enter：結果是最新的就複製，否則翻譯
    func submit() {
        if !output.isEmpty && !isStale && !isBusy {
            copyOutput()
        } else {
            translateNow()
        }
    }

    /// 翻譯目前輸入：優先用本機 Ollama，失敗時退回 Apple 翻譯
    func translateNow() {
        let text = trimmedInput
        guard !text.isEmpty else { return }
        pending?.cancel()
        stopSpeaking()
        let dir = manualDirection ?? Direction.detect(text)
        direction = dir
        pending = Task { [weak self] in
            await self?.translate(text, dir)
        }
    }

    /// 手動鎖定方向但輸入語言對不上時，回傳偵測到的正確方向
    var mismatchedDirection: Direction? {
        guard let m = manualDirection else { return nil }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let detected = Direction.detect(text)
        return detected == m ? nil : detected
    }

    /// ⇄ 把翻譯結果換到輸入框，方向反過來（可用來回譯檢查）。
    func swap() {
        let newInput = output
        if let m = manualDirection {
            manualDirection = (m == .zhToEn) ? .enToZh : .zhToEn
        }
        guard !newInput.isEmpty else { return }
        input = newInput
        inputChanged()
        translateNow()
    }

    private func translate(_ text: String, _ dir: Direction) async {
        isBusy = true
        defer { if !Task.isCancelled { isBusy = false } }

        // 1) 本機 Ollama
        var fallbackReason: String?
        do {
            let result = try await ollama.translate(text, dir)
            guard !Task.isCancelled else { return }
            show(result, for: text, dir, note: ollama.displayName)
            return
        } catch {
            guard !Task.isCancelled else { return }
            if (error as? URLError)?.code == .cancelled { return }
            fallbackReason = (error as? URLError)?.code == .cannotConnectToHost
                ? "Ollama 未啟動" : "Ollama 失敗"
        }

        // 2) 退回 Apple 翻譯
        do {
            let response = try await sessionFor(dir).translate(text)
            guard !Task.isCancelled else { return }
            show(response.targetText, for: text, dir, note: "Apple 翻譯（\(fallbackReason ?? "")）")
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            output = ""
            engineNote = nil
            translatedText = nil
            errorMessage = "翻譯失敗：\(error.localizedDescription)\n請確認 Ollama 已啟動，或到「系統設定 → 一般 → 語言與地區 → 翻譯語言」下載英文與中文（台灣）。"
        }
    }

    private func show(_ result: String, for text: String, _ dir: Direction, note: String) {
        output = result
        errorMessage = nil
        engineNote = note
        translatedText = text
        translatedDirection = dir
    }

    /// 啟動時先各翻一次，把 Apple 翻譯（備援）載入記憶體。Ollama 不預載，按翻譯時才佔記憶體。
    func warmUp() {
        Task {
            for (dir, text) in [(Direction.zhToEn, "你好"), (.enToZh, "hello")] {
                _ = try? await sessionFor(dir).translate(text)
            }
        }
    }

    private func sessionFor(_ dir: Direction) throws -> TranslationSession {
        if let s = sessions[dir] { return s }
        let s = TranslationSession(installedSource: dir.source, target: dir.target)
        sessions[dir] = s
        return s
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        copiedFlash = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.copiedFlash = false
        }
    }

    /// 朗讀 / 停止朗讀翻譯結果
    func toggleSpeak() {
        inputSpeaker.stop()
        speaker.toggle(output, language: direction.speechLanguage)
    }

    /// 朗讀 / 停止朗讀輸入框原文（語言依自動偵測或手動指定的來源語言）
    func toggleSpeakInput() {
        speaker.stop()
        let text = trimmedInput
        let dir = manualDirection ?? Direction.detect(text)
        inputSpeaker.toggle(text, language: dir.sourceSpeechLanguage)
    }

    func stopSpeaking() {
        speaker.stop()
        inputSpeaker.stop()
    }

    /// 叫出視窗時把游標放回輸入框（保留上次內容，⌘A 可全選重打）。
    func focusInput() {
        focusToken += 1
    }
}

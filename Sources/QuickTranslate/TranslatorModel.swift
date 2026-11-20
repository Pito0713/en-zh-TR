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
    var focusToken = 0
    var copiedFlash = false
    let speaker = Speaker()

    @ObservationIgnored private var sessions: [Direction: TranslationSession] = [:]
    @ObservationIgnored private var pending: Task<Void, Never>?

    /// 輸入變動後稍等一下再翻（打字時即時更新，又不會每個字都翻）。
    func inputChanged() {
        pending?.cancel()
        speaker.stop()
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            output = ""
            errorMessage = nil
            isBusy = false
            return
        }
        let dir = manualDirection ?? Direction.detect(text)
        direction = dir
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
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
    }

    private func translate(_ text: String, _ dir: Direction) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let session = try sessionFor(dir)
            let response = try await session.translate(text)
            guard !Task.isCancelled else { return }
            output = response.targetText
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            output = ""
            errorMessage = "翻譯失敗：\(error.localizedDescription)\n請到「系統設定 → 一般 → 語言與地區 → 翻譯語言」下載英文與中文（台灣）。"
        }
    }

    /// 啟動時先各翻一次，把模型載入記憶體，第一次叫出視窗就不會卡。
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
        speaker.toggle(output, language: direction.speechLanguage)
    }

    /// 叫出視窗時把游標放回輸入框（保留上次內容，⌘A 可全選重打）。
    func focusInput() {
        focusToken += 1
    }
}

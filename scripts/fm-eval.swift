// Apple Translation vs Apple Foundation Models 翻譯品質對照（只用來評估，不屬於 App）。
//
// 用法：
//   swiftc -parse-as-library -O scripts/fm-eval.swift -o .build/fm-eval
//   .build/fm-eval                     # 跑內建範例
//   .build/fm-eval my-sentences.txt    # 一行一句，空行與 # 開頭略過
//
// 方向判斷與 App 相同：含漢字 → 中翻英，否則英翻中。

import Foundation
import FoundationModels
import Translation

enum Dir {
    case zhToEn, enToZh
    static func detect(_ t: String) -> Dir {
        t.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
            ? .zhToEn : .enToZh
    }
    var source: Locale.Language { self == .zhToEn ? .init(identifier: "zh-TW") : .init(identifier: "en") }
    var target: Locale.Language { self == .zhToEn ? .init(identifier: "en") : .init(identifier: "zh-TW") }
    var label: String { self == .zhToEn ? "中→英" : "英→中" }
}

let instructions = """
You are a professional translator between English and Traditional Chinese as used in Taiwan (zh-TW).
Rules:
- Translate the user's text into the requested target language. Output ONLY the translation, no notes, no quotes.
- Preserve meaning, tone and register; translate idioms by meaning, not word for word.
- For Chinese output: use Traditional characters and Taiwan vocabulary (e.g. 軟體, 影片, 資訊, 網路, 品質), never Simplified or mainland terms.
- For English output: write natural, idiomatic English.
"""

let samples = [
    // 英→中：慣用語、語氣、台灣用詞
    "It's raining cats and dogs, so let's call it a day.",
    "Can you send me the video and the software update by end of day?",
    "I'm not gonna lie, that presentation was a bit of a train wreck.",
    "Break a leg at your interview tomorrow!",
    "The quality of the network connection depends on your router settings.",
    // 中→英：口語、成語、文化詞
    "這家店的牛肉麵CP值很高，下次再來。",
    "他這個人很龜毛，做事拖拖拉拉的。",
    "你先不要急，船到橋頭自然直。",
    "我等等要去便利商店繳費，順便買杯咖啡。",
    "這份報告我明天前會處理好，再麻煩你幫我看一下。",
]

func loadSentences() -> [String] {
    guard CommandLine.arguments.count > 1 else { return samples }
    let path = CommandLine.arguments[1]
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("讀不到檔案：\(path)"); exit(1)
    }
    return text.split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
}

@main
struct FMEval {
    static func main() async {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        switch model.availability {
        case .available: break
        case .unavailable(let reason):
            print("⚠️ Foundation Models 無法使用：\(reason)")
            print("   需 Apple silicon、系統設定開啟 Apple Intelligence，且模型已下載完成。")
            exit(1)
        }
        let zhOK = model.supportsLocale(Locale(identifier: "zh-TW"))
        print("Foundation Models 可用；支援 zh-TW：\(zhOK ? "是" : "否（結果可能較差）")\n")

        var translators: [Dir: TranslationSession] = [:]
        let options = GenerationOptions(temperature: 0)

        for (i, text) in loadSentences().enumerated() {
            let dir = Dir.detect(text)
            print("[\(i + 1)] \(dir.label)  \(text)")

            // Apple Translation（App 目前用的）
            let ts = translators[dir] ?? TranslationSession(installedSource: dir.source, target: dir.target)
            translators[dir] = ts
            var t0 = Date()
            do {
                let r = try await ts.translate(text)
                print(String(format: "  Translation (%.2fs): ", Date().timeIntervalSince(t0)) + r.targetText)
            } catch {
                print("  Translation 失敗：\(error.localizedDescription)")
            }

            // Foundation Models（每句開新 session，避免前文影響）
            let session = LanguageModelSession(model: model, instructions: instructions)
            let targetName = dir == .zhToEn ? "English" : "Traditional Chinese (Taiwan)"
            t0 = Date()
            do {
                let r = try await session.respond(to: "Translate into \(targetName):\n\(text)", options: options)
                print(String(format: "  Foundation  (%.2fs): ", Date().timeIntervalSince(t0))
                      + r.content.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                print("  Foundation 失敗：\(error)")
            }
            print()
        }
    }
}

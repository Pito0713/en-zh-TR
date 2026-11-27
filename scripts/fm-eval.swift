// Apple Translation vs Apple Foundation Models vs 本機 Ollama 翻譯品質對照（只用來評估，不屬於 App）。
//
// 用法：
//   swiftc -parse-as-library -O scripts/fm-eval.swift -o .build/fm-eval
//   .build/fm-eval                     # 跑內建範例
//   .build/fm-eval my-sentences.txt    # 一行一句，空行與 # 開頭略過
//   OLLAMA_MODELS="qwen3.5:9b,gemma4:12b" .build/fm-eval   # 加比本機 Ollama 模型
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

// MARK: - Ollama（本機 LLM）

struct OllamaError: Error, CustomStringConvertible { let description: String }

func ollamaChat(model: String, system: String, user: String, think: Bool?) async throws -> String {
    var body: [String: Any] = [
        "model": model,
        "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        "stream": false,
        "keep_alive": "10m",
        "options": ["temperature": 0],
    ]
    if let think { body["think"] = think }
    var req = URLRequest(url: URL(string: "http://localhost:11434/api/chat")!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    req.timeoutInterval = 300
    let (data, _) = try await URLSession.shared.data(for: req)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    if let err = json?["error"] as? String { throw OllamaError(description: err) }
    guard let msg = json?["message"] as? [String: Any], let content = msg["content"] as? String else {
        throw OllamaError(description: String(decoding: data, as: UTF8.self))
    }
    // 保險：去掉可能殘留的 <think>…</think>
    let cleaned = content.replacingOccurrences(of: "(?s)<think>.*?</think>", with: "", options: .regularExpression)
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 支援 thinking 的模型關掉思考（快很多）；不支援的就不帶 think 參數。
func ollamaTranslate(model: String, system: String, user: String) async throws -> String {
    do {
        return try await ollamaChat(model: model, system: system, user: user, think: false)
    } catch let e as OllamaError where e.description.lowercased().contains("think") {
        return try await ollamaChat(model: model, system: system, user: user, think: nil)
    }
}

typealias Row = (label: String, seconds: Double, text: String)

func timed(_ label: String, _ work: () async throws -> String) async -> Row {
    let t0 = Date()
    do {
        let out = try await work()
        return (label, Date().timeIntervalSince(t0), out)
    } catch {
        return (label, Date().timeIntervalSince(t0), "❌ 失敗：\(error)")
    }
}

func prompt(_ text: String, _ dir: Dir) -> String {
    let targetName = dir == .zhToEn ? "English" : "Traditional Chinese (Taiwan)"
    return "Translate into \(targetName):\n\(text)"
}

// MARK: - main
//
// 環境變數：
//   OLLAMA_MODELS="qwen3.5:9b,gemma4:12b"  要比較的本機模型（逗號分隔，未設就不跑 Ollama）
//   SKIP_FM=1                               不跑 Foundation Models

@main
struct FMEval {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let sentences = loadSentences()
        let dirs = sentences.map(Dir.detect)
        var rows = Array(repeating: [Row](), count: sentences.count)

        // 1) Apple Translation（App 目前用的）
        var translators: [Dir: TranslationSession] = [:]
        for (i, text) in sentences.enumerated() {
            let dir = dirs[i]
            let ts = translators[dir] ?? TranslationSession(installedSource: dir.source, target: dir.target)
            translators[dir] = ts
            rows[i].append(await timed("Translation") { try await ts.translate(text).targetText })
        }

        // 2) Foundation Models
        if env["SKIP_FM"] == nil {
            let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
            if case .available = model.availability {
                let options = GenerationOptions(temperature: 0)
                for (i, text) in sentences.enumerated() {
                    // 每句開新 session，避免前文影響
                    let session = LanguageModelSession(model: model, instructions: instructions)
                    rows[i].append(await timed("Foundation") {
                        try await session.respond(to: prompt(text, dirs[i]), options: options)
                            .content.trimmingCharacters(in: .whitespacesAndNewlines)
                    })
                }
            } else {
                print("⚠️ Foundation Models 無法使用：\(model.availability)（略過）")
            }
        }

        // 3) Ollama：一次跑完一個模型再換下一個，避免模型在記憶體裡來回載入
        let models = (env["OLLAMA_MODELS"] ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for m in models {
            let short = m.split(separator: "/").last.map(String.init) ?? m
            let t0 = Date()
            _ = try? await ollamaTranslate(model: m, system: instructions, user: "Translate into English:\n你好")
            print(String(format: "[載入 %@：%.1fs]", short, Date().timeIntervalSince(t0)))
            for (i, text) in sentences.enumerated() {
                rows[i].append(await timed(short) {
                    try await ollamaTranslate(model: m, system: instructions, user: prompt(text, dirs[i]))
                })
            }
        }
        print()

        let width = rows.flatMap { $0.map(\.label.count) }.max() ?? 10
        for (i, text) in sentences.enumerated() {
            print("[\(i + 1)] \(dirs[i].label)  \(text)")
            for r in rows[i] {
                let label = r.label.padding(toLength: width, withPad: " ", startingAt: 0)
                print(String(format: "  %@ (%.2fs): ", label, r.seconds) + r.text)
            }
            print()
        }
    }
}

import Foundation

/// 本機 Ollama（預設 qwen3.5:9b）翻譯。完全離線，模型閒置 5 分鐘後 Ollama 會自動釋放記憶體。
/// 換模型：defaults write local.quicktranslate ollamaModel "其他模型名稱"
struct OllamaClient {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static let defaultModel = "qwen3.5:9b"
    var model: String { UserDefaults.standard.string(forKey: "ollamaModel") ?? Self.defaultModel }
    /// 顯示用短名，例如 "qwen3.5:9b"
    var displayName: String { model.split(separator: "/").last.map(String.init) ?? model }

    private let endpoint = URL(string: "http://127.0.0.1:11434/api/chat")!

    private static let instructions = """
    You are a professional translator between English and Traditional Chinese as used in Taiwan (zh-TW).
    Rules:
    - Translate the user's text into the requested target language. Output ONLY the translation, no notes, no quotes.
    - Preserve meaning, tone and register; translate idioms by meaning, not word for word.
    - For Chinese output: use Traditional characters and Taiwan vocabulary (e.g. 軟體, 影片, 資訊, 網路, 品質), never Simplified or mainland terms.
    - For English output: write natural, idiomatic English.
    """

    func translate(_ text: String, _ dir: Direction) async throws -> String {
        let target = dir == .zhToEn ? "English" : "Traditional Chinese (Taiwan)"
        let user = "Translate into \(target):\n\(text)"
        do {
            return try await chat(user, think: false)
        } catch let e as Failure where e.description.lowercased().contains("think") {
            // 不支援 thinking 參數的模型：不帶 think 重送
            return try await chat(user, think: nil)
        }
    }

    private func chat(_ user: String, think: Bool?) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": Self.instructions],
                ["role": "user", "content": user],
            ],
            "stream": false,
            "keep_alive": "5m",
            "options": ["temperature": 0],
        ]
        if let think { body["think"] = think }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60 // 第一次載入模型約 5 秒

        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let err = json?["error"] as? String { throw Failure(description: err) }
        guard let msg = json?["message"] as? [String: Any], let content = msg["content"] as? String else {
            throw Failure(description: "Ollama 回應格式不符")
        }
        let cleaned = content.replacingOccurrences(of: "(?s)<think>.*?</think>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw Failure(description: "Ollama 回傳空白") }
        return cleaned
    }
}

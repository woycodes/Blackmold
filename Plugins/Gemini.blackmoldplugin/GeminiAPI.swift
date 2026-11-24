import BlackmoldKit
import Foundation
import Security

/// The Gemini API key, kept in the login keychain.
enum GeminiKey {
    private static let service = "Blackmold.gemini"
    private static let account = "api-key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static func save(_ key: String) {
        delete()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Blackmold Gemini API key",
            kSecValueData as String: Data(key.utf8),
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// One model the key can use.
struct GeminiModel: Identifiable, Hashable, Codable {
    /// "gemini-2.5-flash", without the "models/" prefix.
    let id: String
    let name: String
}

/// One piece of a turn: text, or a file sent inline (a photo, a voice clip).
enum GeminiPart: Equatable {
    case text(String)
    case file(mimeType: String, data: Data)

    var json: [String: Any] {
        switch self {
        case .text(let text): ["text": text]
        case .file(let mime, let data): ["inlineData": ["mimeType": mime, "data": data.base64EncodedString()]]
        }
    }
}

struct GeminiTurn: Equatable {
    enum Role: String { case user, model }
    var role: Role
    var parts: [GeminiPart]

    var text: String {
        parts.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined()
    }
}

enum GeminiError: LocalizedError {
    case badKey
    case http(Int, String)
    case blocked(String)

    var errorDescription: String? {
        switch self {
        case .badKey: "The API key was not accepted."
        case .http(let code, let message): message.isEmpty ? "Gemini answered with error \(code)." : message
        case .blocked(let reason): "Gemini did not answer (\(reason.lowercased().replacingOccurrences(of: "_", with: " ")))."
        }
    }
}

/// The REST side of the Gemini API: the model list and streamed answers.
enum GeminiAPI {
    static let base = URL(string: "https://generativelanguage.googleapis.com/v1beta/")!

    /// Used when the list cannot be read.
    /// The "latest" aliases follow Google's newest models, so they never retire.
    static let fallbackModels = [
        GeminiModel(id: "gemini-flash-latest", name: "Gemini Flash Latest"),
        GeminiModel(id: "gemini-pro-latest", name: "Gemini Pro Latest"),
        GeminiModel(id: "gemini-flash-lite-latest", name: "Gemini Flash-Lite Latest"),
    ]

    /// 3.8 for "gemini-3.8-flash"; the "latest" aliases sort first.
    static func version(of id: String) -> Double {
        if id.hasSuffix("-latest") { return 100 }
        let number = id.dropFirst("gemini-".count).prefix { $0.isNumber || $0 == "." }
        return Double(number) ?? 0
    }

    private static func request(_ path: String, key: String) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 120
        return request
    }

    /// Chat models and Live models the key can use, newest first as Google lists them.
    static func models(key: String) async throws -> (chat: [GeminiModel], live: [GeminiModel]) {
        var components = URLComponents(url: base.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)

        let list = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["models"] as? [[String: Any]] ?? []
        var chat: [GeminiModel] = []
        var live: [GeminiModel] = []
        for entry in list {
            guard let fullName = entry["name"] as? String else { continue }
            let id = fullName.replacingOccurrences(of: "models/", with: "")
            let methods = entry["supportedGenerationMethods"] as? [String] ?? []
            let model = GeminiModel(id: id, name: entry["displayName"] as? String ?? id)
            guard id.hasPrefix("gemini") else { continue }
            if methods.contains("bidiGenerateContent") { live.append(model) }
            // Only models that chat in text: no speech, image or embedding models.
            let special = ["tts", "image", "embedding", "live", "audio", "robotics", "computer-use",
                           "transcribe", "customtools", "nano-banana"]
            if methods.contains("generateContent"), !special.contains(where: id.contains) {
                chat.append(model)
            }
        }
        let newestFirst = { (a: GeminiModel, b: GeminiModel) in version(of: a.id) > version(of: b.id) }
        return (chat.sorted(by: newestFirst), live.sorted(by: newestFirst))
    }

    /// Streams the answer to `turns`, calling `onText` with each new piece.
    static func stream(turns: [GeminiTurn], model: String, key: String,
                       onText: @escaping @MainActor (String) -> Void) async throws {
        var request = request("models/\(model):streamGenerateContent", key: key)
        request.url = URL(string: request.url!.absoluteString + "?alt=sse")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "contents": turns.map { ["role": $0.role.rawValue, "parts": $0.parts.map(\.json)] },
            "systemInstruction": ["parts": [["text":
                "You answer inside a small panel under the Mac's notch. Keep answers short and to the point unless asked for detail. Use Markdown sparingly."]]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            try check(response, data)
        }
        var gotText = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:"),
                  let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces).data(using: .utf8),
                  let chunk = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let feedback = chunk["promptFeedback"] as? [String: Any], let reason = feedback["blockReason"] as? String {
                throw GeminiError.blocked(reason)
            }
            let candidate = (chunk["candidates"] as? [[String: Any]])?.first
            let parts = (candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            // Thought summaries are left out; only the answer shows.
            let text = parts.filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty {
                gotText = true
                await onText(text)
            }
            if !gotText, let reason = candidate?["finishReason"] as? String, reason != "STOP" {
                throw GeminiError.blocked(reason)
            }
        }
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode != 200 else { return }
        let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
        let message = error?["message"] as? String ?? ""
        if http.statusCode == 400 && message.localizedCaseInsensitiveContains("API key")
            || http.statusCode == 401 || http.statusCode == 403 && message.localizedCaseInsensitiveContains("key") {
            throw GeminiError.badKey
        }
        throw GeminiError.http(http.statusCode, message)
    }
}

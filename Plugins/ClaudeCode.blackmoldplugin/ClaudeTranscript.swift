import Foundation

/// Reads how many tokens Claude has written in the current turn, from the
/// newest Claude Code transcript (~/.claude/projects/**/*.jsonl).
enum ClaudeTranscript {
    private static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)

    /// Output tokens since the last prompt the user typed, or nil without a transcript.
    static func turnOutputTokens() -> Int? {
        guard let file = newestTranscript(), let text = tail(of: file, bytes: 768 * 1024) else { return nil }
        var tokensByMessage: [String: Int] = [:]
        var order: [String] = []

        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = entry["type"] as? String,
                  let message = entry["message"] as? [String: Any] else { continue }

            if type == "user", isTypedPrompt(message["content"]) {
                tokensByMessage.removeAll()
                order.removeAll()
            } else if type == "assistant",
                      let id = message["id"] as? String,
                      let usage = message["usage"] as? [String: Any],
                      let output = usage["output_tokens"] as? Int {
                // A message is written in pieces that repeat its usage; keep the largest.
                if tokensByMessage[id] == nil { order.append(id) }
                tokensByMessage[id] = max(tokensByMessage[id] ?? 0, output)
            }
        }
        return order.reduce(0) { $0 + (tokensByMessage[$1] ?? 0) }
    }

    /// Tool results also arrive as "user" entries; a typed prompt has text.
    private static func isTypedPrompt(_ content: Any?) -> Bool {
        if content is String { return true }
        guard let blocks = content as? [[String: Any]] else { return false }
        return blocks.contains { $0["type"] as? String == "text" }
            && !blocks.contains { $0["type"] as? String == "tool_result" }
    }

    private static func newestTranscript() -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        var newest: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if date > newest?.date ?? .distantPast { newest = (url, date) }
        }
        return newest?.url
    }

    /// The last `bytes` of the file, starting at a whole line.
    private static func tail(of url: URL, bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), var text = String(data: data, encoding: .utf8) else { return nil }
        if start > 0, let firstBreak = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstBreak)...])
        }
        return text
    }
}

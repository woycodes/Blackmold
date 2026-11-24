import Foundation

/// Watches for Claude Code's usage limit and says when it has reset.
///
/// When a limit is hit, Claude Code writes an error entry into the session
/// transcript, e.g. "You've hit your 5-hour limit · resets 7:10pm
/// (Asia/Makassar)". The reset time is read from the newest such entry; once
/// that time has passed, `onReset` is called, once per reset.
@MainActor
final class ClaudeLimitMonitor {
    struct Limit: Equatable {
        let resetsAt: Date
        /// "5-hour", "session", "weekly", …
        let kind: String
    }

    var onReset: ((Limit) -> Void)?
    /// Called again later when it returns false, e.g. while the notch is open.
    var canAnnounce: () -> Bool = { true }

    private(set) var pending: Limit?
    private var scanTimer: Timer?
    private var tickTimer: Timer?
    private static let announcedKey = "claude.limit.announcedReset"
    /// A reset missed by more than this (the Mac was asleep, the app was off) is not announced.
    private static let lateness: TimeInterval = 15 * 60
    private let reader = ClaudeLimitReader()
    private var isScanning = false

    func start() {
        scan()
        let scan = Timer(timeInterval: 90, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
        let tick = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(scan, forMode: .common)
        RunLoop.main.add(tick, forMode: .common)
        scanTimer = scan
        tickTimer = tick
    }

    func stop() {
        scanTimer?.invalidate()
        tickTimer?.invalidate()
    }

    private func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .utility) { [reader] in
            let limit = reader.latest()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isScanning = false
                guard let limit else { return }
                let announced = UserDefaults.standard.double(forKey: Self.announcedKey)
                if limit.resetsAt.timeIntervalSinceReferenceDate > announced + 1 {
                    self.pending = limit
                }
            }
        }
    }

    private func tick() {
        guard let pending, Date() >= pending.resetsAt else { return }
        if Date().timeIntervalSince(pending.resetsAt) > Self.lateness {
            markAnnounced(pending)
            return
        }
        guard canAnnounce() else { return }
        markAnnounced(pending)
        onReset?(pending)
    }

    private func markAnnounced(_ limit: Limit) {
        UserDefaults.standard.set(limit.resetsAt.timeIntervalSinceReferenceDate, forKey: Self.announcedKey)
        pending = nil
    }
}

/// Finds the newest rate-limit entry in recent transcripts. Each file is read
/// once in full, then only what was added since; one scan runs at a time.
final class ClaudeLimitReader: @unchecked Sendable {
    private static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)

    private typealias Found = (stamp: Date, limit: ClaudeLimitMonitor.Limit)
    /// Per transcript: bytes read so far and the newest limit in them.
    private var files: [URL: (offset: UInt64, newest: Found?)] = [:]

    func latest() -> ClaudeLimitMonitor.Limit? {
        let cutoff = Date().addingTimeInterval(-8 * 86400)
        guard let enumerator = FileManager.default.enumerator(
            at: Self.root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }

        var newest: Found?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            guard modified > cutoff else { continue }
            var known = files[url] ?? (0, nil)
            if let (added, end) = Self.read(url, from: known.offset) {
                known.offset = end
                for line in added.split(separator: "\n") where line.contains("\"rate_limit\"") {
                    guard let found = Self.limit(in: line), found.stamp > known.newest?.stamp ?? .distantPast else { continue }
                    known.newest = found
                }
                files[url] = known
            }
            if let found = known.newest, found.stamp > newest?.stamp ?? .distantPast { newest = found }
        }
        return newest?.limit
    }

    private static func limit(in line: Substring) -> Found? {
        guard let data = line.data(using: .utf8),
              let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              entry["error"] as? String == "rate_limit",
              let stampText = entry["timestamp"] as? String,
              let stamp = parseStamp(stampText),
              let message = entry["message"] as? [String: Any],
              let limit = parse(text(of: message["content"]), after: stamp) else { return nil }
        return (stamp, limit)
    }

    /// Whole lines from `offset` on, and where the last of them ends.
    private static func read(_ url: URL, from offset: UInt64) -> (String, UInt64)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        // A rewritten, shorter file starts over.
        let start = offset <= size ? offset : 0
        guard size > start else { return nil }
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let lastBreak = data.lastIndex(of: 0x0A) else { return nil }
        let whole = data[data.startIndex...lastBreak]
        return (String(decoding: whole, as: UTF8.self), start + UInt64(whole.count))
    }

    /// "You've hit your 5-hour limit · resets 7:10pm (Asia/Makassar)", or with
    /// a date: "resets Nov 23, 10pm (Asia/Jakarta)". The time is the next one
    /// after the moment the limit was hit, in that time zone.
    static func parse(_ text: String, after stamp: Date) -> ClaudeLimitMonitor.Limit? {
        guard let resets = text.range(of: "resets ", options: .caseInsensitive) else { return nil }
        let rest = String(text[resets.upperBound...])
        var zone = TimeZone.current
        if let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")"),
           let named = TimeZone(identifier: String(rest[rest.index(after: open)..<close])) {
            zone = named
        }
        let when = rest.split(separator: "(").first.map(String.init) ?? rest

        guard let time = groups(#"(?i)(\d{1,2})(?::(\d{2}))?\s*(am|pm)"#, in: when) else { return nil }
        var hour = Int(time[0] ?? "") ?? 0
        let minute = Int(time[1] ?? "") ?? 0
        let isPM = time[2]?.lowercased() == "pm"
        if hour == 12 { hour = 0 }
        if isPM { hour += 12 }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var resetsAt: Date?
        if let day = groups(#"([A-Za-z]{3})[a-z]*\s+(\d{1,2})\b"#, in: when),
           let month = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
            .firstIndex(of: day[0]?.lowercased() ?? "") {
            var parts = calendar.dateComponents([.year], from: stamp)
            parts.month = month + 1
            parts.day = Int(day[1] ?? "")
            parts.hour = hour
            parts.minute = minute
            resetsAt = calendar.date(from: parts)
            if let date = resetsAt, date < stamp { resetsAt = calendar.date(byAdding: .year, value: 1, to: date) }
        } else {
            resetsAt = calendar.nextDate(
                after: stamp, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime)
        }
        guard let resetsAt else { return nil }

        let kind = groups(#"your (.+?) limit"#, in: text)?[0] ?? "usage"
        return .init(resetsAt: resetsAt, kind: kind)
    }

    /// The capture groups of the first match, nil where a group did not take part.
    private static func groups(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    private static func text(of content: Any?) -> String {
        if let string = content as? String { return string }
        let blocks = content as? [[String: Any]] ?? []
        return blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
    }

    private static func parseStamp(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

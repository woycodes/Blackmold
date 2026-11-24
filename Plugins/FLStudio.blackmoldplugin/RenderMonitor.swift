import AppKit
import ApplicationServices

/// Follows an FL Studio render.
///
/// While rendering, FL Studio shows a small "Rendering to <file>" dialog
/// and titles its main window "Rendering: 6/144", the bar it is on out of
/// the song's length.
///
/// - The dialog is found in the window list by its size. That works from any
///   desktop and needs no permission, so it says whether a render is running.
/// - The title gives the progress. Accessibility reads it while FL Studio is
///   on the current desktop; the window list reads it from any desktop once
///   Screen Recording is allowed. When neither can, the progress carries on
///   at the speed measured so far, short of 100%.
/// - The render is done when the dialog closes after the last bars, or while
///   FL Studio could not be seen. Stopped early in view, it just disappears.
@MainActor
final class FLStudioRenderMonitor {
    var onChange: ((RenderStatus) -> Void)?

    private var timer: Timer?
    private var rendering = false
    /// Progress read from the title, and when, for carrying it on.
    private var samples: [(time: Date, value: Double)] = []
    private var shown: Double?

    func start() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() { timer?.invalidate() }

    private func poll() {
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier?.hasPrefix("com.image-line.flstudio") == true }
            .map(\.processIdentifier)
        guard !pids.isEmpty else {
            if rendering { finish(seen: false) }
            return
        }

        var read: Double?? = nil   // .some(nil): rendering, length not in the title
        var dialog = false
        var seen = false            // a title of FL Studio could be read at all
        for pid in pids {
            let look = Self.look(pid: pid)
            dialog = dialog || look.dialog
            seen = seen || !look.titles.isEmpty
            if read == nil, let found = Self.progress(in: look.titles) { read = found }
        }

        if let read {
            rendering = true
            if let value = read {
                if let last = samples.last, value < last.value { samples = [] }  // a new render
                samples.append((Date(), value))
                if samples.count > 40 { samples.removeFirst() }
                show(value)
            } else {
                show(nil)
            }
        } else if dialog {
            // Rendering, but the title cannot be read from here.
            rendering = true
            show(estimate())
        } else if rendering {
            finish(seen: seen)
        }
    }

    private func show(_ value: Double?) {
        // The ring never runs backwards.
        if let value, let current = shown, value < current, !(samples.count == 1) { return }
        shown = value
        onChange?(.rendering(progress: value))
    }

    /// The last reading carried on at the speed so far, short of the end.
    private func estimate() -> Double? {
        guard let last = samples.last else { return shown }
        guard let first = samples.first, last.time > first.time else { return last.value }
        let speed = (last.value - first.value) / last.time.timeIntervalSince(first.time)
        let value = last.value + speed * Date().timeIntervalSince(last.time)
        return min(0.99, max(last.value, value))
    }

    private func finish(seen: Bool) {
        // In view, a render that ends before its last bars was stopped.
        let finished = !seen || (samples.last?.value ?? shown ?? 0) >= 0.85
        rendering = false
        samples = []
        shown = nil
        onChange?(finished ? .done : .idle)
    }

    // MARK: Reading FL Studio's windows

    private struct Look {
        var titles: [String] = []
        var dialog = false
    }

    private static func look(pid: pid_t) -> Look {
        var look = Look()
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var windows: AnyObject?
        if AXUIElementCopyAttributeValue(app, "AXWindows" as CFString, &windows) == .success {
            for window in windows as? [AXUIElement] ?? [] {
                var title: AnyObject?
                AXUIElementCopyAttributeValue(window, "AXTitle" as CFString, &title)
                if let title = title as? String, !title.isEmpty { look.titles.append(title) }
            }
        }
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in list where (window[kCGWindowOwnerPID as String] as? pid_t) == pid {
            // Names need Screen Recording; without it they are missing.
            let name = window[kCGWindowName as String] as? String ?? ""
            if !name.isEmpty { look.titles.append(name) }
            if name.hasPrefix("Rendering to") { look.dialog = true }
            // The render dialog, known by its size when its name cannot be read.
            if let bounds = window[kCGWindowBounds as String] as? [String: Any],
               let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double,
               (300...360).contains(width), (440...510).contains(height) {
                look.dialog = true
            }
        }
        if look.titles.contains(where: { $0.hasPrefix("Rendering to") }) { look.dialog = true }
        return look
    }

    /// The progress in a "Rendering: n/m" title, if there is one.
    private static func progress(in titles: [String]) -> Double?? {
        for title in titles where title.hasPrefix("Rendering:") {
            let numbers = title.dropFirst("Rendering:".count)
                .split(separator: "/")
                .map { Double($0.trimmingCharacters(in: .whitespaces)) }
            if numbers.count == 2, let done = numbers[0], let total = numbers[1], total > 0 {
                return .some(min(1, done / total))
            }
            return .some(nil)
        }
        return nil
    }
}

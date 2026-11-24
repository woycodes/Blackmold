import AppKit
import BlackmoldKit
import SwiftUI

/// Claude Code on the notch.
///
/// - Claude Code's hooks open blackmold://claude/<thinking|working|waiting|done>;
///   the ears show what it is doing, with a timer or the tokens written.
/// - When a usage limit has reset, the pixel mascot says so.
final class ClaudeCodePlugin: BlackmoldPlugin {
    private let state = ClaudeState()
    private let limit = ClaudeLimitMonitor()
    private var host: PluginHost?
    private var doneTask: Task<Void, Never>?
    private var tokenTimer: Timer?

    init() {}

    func start(_ host: PluginHost) {
        self.host = host
        host.onURL(host: "claude") { [weak self] url in self?.handle(url) }

        limit.canAnnounce = { [weak host] in host?.isOpen == false }
        limit.onReset = { [weak self] _ in self?.announceReset() }
        limit.start()
    }

    func stop() {
        limit.stop()
        doneTask?.cancel()
        tokenTimer?.invalidate()
        tokenTimer = nil
        state.status = .idle
        host?.show(nil)
    }

    // MARK: Hooks

    private func handle(_ url: URL) {
        let next: ClaudeStatus = switch url.lastPathComponent {
        case "thinking": .thinking
        case "working": .working
        case "waiting": .waiting
        case "done": .done
        default: .idle
        }
        doneTask?.cancel()
        if next == .thinking, state.status == .idle || state.status == .done {
            state.turnStart = Date()
            state.tokens = nil
        }
        state.status = next
        updateTokenPolling()
        if next == .done || next == .waiting { host?.tick() }

        guard next != .idle else {
            host?.show(nil)
            return
        }
        host?.show(PluginActivity(priority: 10,
                                  left: { ClaudeLeftEar(state: state) },
                                  right: { ClaudeRightEar(state: state) }))
        // "Done" stays a few seconds, then the ears go back to whatever was there.
        if next == .done {
            doneTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, let self else { return }
                self.state.status = .idle
                self.updateTokenPolling()
                self.host?.show(nil)
            }
        }
    }

    /// Reads the transcript every second while Claude is busy.
    private func updateTokenPolling() {
        let busy = state.status == .thinking || state.status == .working
        guard busy != (tokenTimer != nil) else { return }
        tokenTimer?.invalidate()
        tokenTimer = nil
        guard busy else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                let tokens = ClaudeTranscript.turnOutputTokens()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.state.tokens = tokens }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tokenTimer = timer
        timer.fire()
    }

    // MARK: Limit reset

    private func announceReset() {
        host?.peek(PluginActivity(left: {
            PixelMascot().frame(width: 26, height: 22)
        }, right: {
            Text("Limit reset")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(claudeOrange)
                .lineLimit(1)
                .fixedSize()
        }), for: 4.5)
    }

    // MARK: Settings

    var settingsView: AnyView? {
        AnyView(VStack(alignment: .leading, spacing: 8) {
            Text("Claude Code reports through these hooks in ~/.claude/settings.json:")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(ClaudeHooks.json)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
            Button("Copy hooks") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ClaudeHooks.json, forType: .string)
            }
        })
    }
}

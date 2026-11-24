import BlackmoldKit
import SwiftUI

/// FL Studio renders on the notch: the fruit being sliced in the left ear and
/// a progress ring in the right one; when the render is done the fruit pops
/// and a check draws itself, for a few seconds.
final class FLStudioPlugin: BlackmoldPlugin {
    private let monitor = FLStudioRenderMonitor()
    private var host: PluginHost?
    private var doneTask: Task<Void, Never>?

    init() {}

    func start(_ host: PluginHost) {
        self.host = host
        monitor.onChange = { [weak self] status in self?.show(status) }
        monitor.start()
    }

    func stop() {
        monitor.stop()
        doneTask?.cancel()
        host?.show(nil)
    }

    private func show(_ status: RenderStatus) {
        doneTask?.cancel()
        guard status != .idle else {
            host?.show(nil)
            return
        }
        host?.show(PluginActivity(priority: 20, left: {
            Group {
                if status == .done { FruitMark().modifier(PopIn()) } else { SlicedFruit() }
            }
            .frame(width: 24, height: 24)
            .id(status == .done)
            .transition(.opacity)
        }, right: {
            Group {
                switch status {
                case .done: DoneCheck()
                case .rendering(let progress): ProgressRing(progress: progress)
                case .idle: EmptyView()
                }
            }
            .frame(width: 20, height: 20)
            .id(status == .done)
            .transition(.opacity.combined(with: .scale(scale: 0.6)))
        }))
        if status == .done {
            host?.tick()
            doneTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                self?.host?.show(nil)
            }
        }
    }

    var settingsView: AnyView? {
        AnyView(Text("Shows FL Studio's render progress on the notch while it renders, then a check. Reads FL Studio's window titles through Accessibility; turn on Screen Recording for Blackmold to follow renders on other desktops.")
            .font(.callout)
            .foregroundStyle(.secondary))
    }
}

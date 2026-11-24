import BlackmoldKit
import SwiftUI

/// Start here. Copy this folder, change the id and name in plugin.json, and
/// build on it. Blackmold rebuilds the plugin whenever a file in it changes
/// (Settings › Plugins › Reload, or restart Blackmold).
final class HelloPlugin: BlackmoldPlugin {
    private let counter = Counter()

    init() {}

    func start(_ host: PluginHost) {
        // A short notice on the notch's ears, like the charger one.
        host.peek(PluginActivity(left: {
            Image(systemName: "hand.wave.fill")
                .foregroundStyle(.yellow)
                .frame(width: 24, height: 24)
        }, right: {
            Text("Hello").font(.system(size: 11, weight: .semibold))
        }), for: 2.5)

        // A page of the open notch. Swipe to it, or pick it in search.
        host.addPage(PluginPage(id: "hello", title: "Hello", symbol: "hand.wave") { [counter] in
            HelloPage(counter: counter)
        })
    }
}

@Observable
final class Counter {
    var taps = 0
}

struct HelloPage: View {
    let counter: Counter

    var body: some View {
        VStack(spacing: 12) {
            Text("Hello from a plugin")
                .font(.system(size: 15, weight: .semibold))
            Button("Tapped \(counter.taps) times") { counter.taps += 1 }
                .buttonStyle(.zoom)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

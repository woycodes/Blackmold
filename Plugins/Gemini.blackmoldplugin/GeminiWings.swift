import BlackmoldKit
import SwiftUI

/// Gemini on the closed notch, sized like the Claude activity:
/// - working: the star turns on the left, the time so far on the right;
/// - done: the notch grows by a line like the lyrics and says "Done",
///   just before it opens on the answer;
/// - Live: the star and bars that move with the voices.
struct GeminiLeftEar: View {
    let chat: GeminiChat
    let done: Bool

    var body: some View {
        Group {
            if done { GeminiLogo().modifier(PopIn()) }
            else { GeminiSpinningLogo(spinning: chat.isThinking) }
        }
        .frame(width: 18, height: 18)
        .frame(width: 24, height: 24)
    }
}

struct GeminiRightEar: View {
    let chat: GeminiChat
    let done: Bool

    var body: some View {
        Group {
            if done {
                DoneCheck().frame(width: 18, height: 18)
            } else if let live = chat.live {
                LiveBars(live: live).frame(width: 22, height: 14)
            } else if case .thinking(let since) = chat.phase {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(TimeFormatting.short(context.date.timeIntervalSince(since)))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                        .contentTransition(.numericText())
                }
            }
        }
        .frame(minWidth: 24)
    }
}

/// Four bars that follow the Live voices.
struct LiveBars: View {
    let live: GeminiLive

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let level = CGFloat(live.level)
            HStack(spacing: 2.5) {
                ForEach(0..<4, id: \.self) { index in
                    let wobble = 0.5 + 0.5 * sin(t * 7 + Double(index) * 1.3)
                    Capsule()
                        .fill(Color(red: 0.45, green: 0.68, blue: 1))
                        .frame(width: 3, height: max(3, 14 * (0.2 + 0.8 * level * CGFloat(wobble))))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

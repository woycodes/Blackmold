import BlackmoldKit
import SwiftUI

/// What Claude Code last reported through its hooks.
enum ClaudeStatus: Equatable {
    case idle
    /// A prompt was sent; Claude is reading and planning.
    case thinking
    /// Claude is running tools: editing files, running commands.
    case working
    /// Claude stopped to ask for something.
    case waiting
    /// The turn finished.
    case done
}

let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

/// What Claude Code last reported, with the turn's timer and tokens.
@Observable
final class ClaudeState {
    var status: ClaudeStatus = .idle
    /// When the current turn started, for the thinking timer.
    var turnStart = Date()
    /// Output tokens Claude has written this turn, read from its transcript.
    var tokens: Int?
}

/// Left ear: an animated mark for what Claude is doing.
struct ClaudeLeftEar: View {
    let state: ClaudeState

    var body: some View {
        Group {
            switch state.status {
            case .thinking: ThinkingMark()
            case .working: LaptopMark()
            case .done: DrawnCheck()
            case .waiting, .idle: ClaudeMark(size: 13).opacity(0.9)
            }
        }
        .frame(width: 24, height: 24)
        .id(state.status)
        .transition(.opacity.combined(with: .scale(scale: 0.6)))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.status)
    }
}

/// Right ear, short on purpose: a timer while thinking, tokens while working.
struct ClaudeRightEar: View {
    let state: ClaudeState

    private func label(at date: Date) -> String {
        switch state.status {
        case .thinking: TimeFormatting.short(date.timeIntervalSince(state.turnStart))
        case .working: Self.tokens(state.tokens)
        case .waiting: "Needs you"
        case .done: "Done"
        case .idle: ""
        }
    }

    static func tokens(_ count: Int?) -> String {
        guard let count else { return "…" }
        if count < 1000 { return "\(count)t" }
        return String(format: "%.1fkt", Double(count) / 1000)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(label(at: context.date))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(state.status == .waiting || state.status == .done ? claudeOrange : .white.opacity(0.85))
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
        }
    }
}

/// The eight-armed Claude mark, drawn as rounded spokes.
private struct ClaudeMark: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { arm in
                Capsule()
                    .fill(claudeOrange)
                    .frame(width: size * 0.18, height: size * 0.5)
                    .offset(y: -size * 0.25)
                    .rotationEffect(.degrees(Double(arm) * 45))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Thinking: the mark turns and breathes.
private struct ThinkingMark: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ClaudeMark(size: 14)
                .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 3) * 120))
                .scaleEffect(0.85 + 0.15 * (0.5 + 0.5 * sin(t * 4)))
        }
    }
}

/// Working: the mark hops above a laptop whose keys flicker as it types.
private struct LaptopMark: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .bottom) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 1.5) {
                    ForEach(0..<3, id: \.self) { key in
                        Capsule()
                            .fill(claudeOrange)
                            .frame(width: 2.5, height: 1.5)
                            .opacity(0.3 + 0.7 * max(0, sin(t * 9 + Double(key) * 2)))
                    }
                }
                .offset(y: -6)
                ClaudeMark(size: 8)
                    .offset(y: -15 - 2 * abs(sin(t * 6)))
            }
            .frame(width: 24, height: 24, alignment: .bottom)
        }
    }
}

/// Done: an orange check that draws itself in.
private struct DrawnCheck: View {
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().fill(claudeOrange)
            CheckShape()
                .trim(from: 0, to: progress)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .padding(.horizontal, 5)
                .padding(.vertical, 6)
        }
        .frame(width: 20, height: 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45).delay(0.1)) { progress = 1 }
        }
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// The orange pixel creature: a block body with two eyes, an arm on each
/// side and four legs. It drops in, bounces, then keeps hopping with its
/// legs stepping and its eyes blinking.
struct PixelMascot: View {
    /// 12 × 7 cells: B body, E eye, nothing else drawn.
    private static let body: [String] = [
        "..BBBBBBBB..",
        "..BEBBBBEB..",
        "BBBBBBBBBBBB",
        "BBBBBBBBBBBB",
        "..BBBBBBBB..",
    ]
    private static let legColumns = [2, 4, 7, 9]

    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            Canvas { canvas, size in
                let cell = min(size.width / 12, size.height / 8)
                let width = cell * 12
                let origin = CGPoint(x: (size.width - width) / 2, y: size.height - cell * 8)

                // Drop in from above with a squash on landing, then hop.
                let drop = t < 0.35 ? -(1 - Self.ease(t / 0.35)) * size.height : 0
                let landing = t >= 0.35 && t < 0.6 ? sin((t - 0.35) / 0.25 * .pi) : 0
                let hopPhase = max(0, t - 0.6)
                let hop = abs(sin(hopPhase * 5.2)) * cell * 0.9
                let squash = landing * 0.18 + (hop < cell * 0.15 && t > 0.6 ? 0.08 : 0)
                let blink = (t.truncatingRemainder(dividingBy: 2.6)) > 2.45
                let step = Int(hopPhase * 8) % 2 == 0

                let orange = GraphicsContext.Shading.color(claudeOrange)
                let bodyTop = origin.y + drop - hop + cell * squash * 5
                let bodyCell = CGSize(width: cell * (1 + squash * 0.3), height: cell * (1 - squash))
                let shiftX = origin.x - (bodyCell.width - cell) * 6

                for (row, line) in Self.body.enumerated() {
                    for (column, mark) in line.enumerated() where mark != "." {
                        // A little wave of the arms while hopping.
                        let armLift = (column < 2 || column > 9) && row >= 2 ? (step ? -cell * 0.35 : 0) : 0
                        let rect = CGRect(
                            x: shiftX + CGFloat(column) * bodyCell.width,
                            y: bodyTop + CGFloat(row) * bodyCell.height + armLift,
                            width: bodyCell.width + 0.3, height: bodyCell.height + 0.3)
                        if mark == "E" {
                            canvas.fill(Path(rect), with: orange)
                            let eye = blink ? rect.insetBy(dx: 0, dy: rect.height * 0.4) : rect
                            canvas.fill(Path(eye), with: .color(.black))
                        } else {
                            canvas.fill(Path(rect), with: orange)
                        }
                    }
                }
                // Legs, stepping in pairs while it hops.
                let legTop = bodyTop + CGFloat(Self.body.count) * bodyCell.height
                for (index, column) in Self.legColumns.enumerated() {
                    let lifted = t > 0.6 && (index % 2 == 0) == step
                    let length = cell * (lifted ? 1.4 : 2)
                    canvas.fill(
                        Path(CGRect(x: shiftX + CGFloat(column) * bodyCell.width, y: legTop,
                                    width: bodyCell.width, height: length)),
                        with: orange)
                }
            }
        }
        .onAppear { start = Date() }
    }

    private static func ease(_ x: Double) -> Double {
        let p = min(1, max(0, x))
        return 1 - pow(1 - p, 3)
    }
}

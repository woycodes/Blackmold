import BlackmoldKit
import SwiftUI

/// What FL Studio is doing with a render.
enum RenderStatus: Equatable {
    case idle
    /// Progress 0...1 when FL Studio shows it.
    case rendering(progress: Double?)
    case done
}

private let ringOrange = Color(red: 1, green: 0.55, blue: 0.12)

// MARK: The fruit

/// The orange fruit with three leaves and a stem, drawn as vector shapes in
/// a 24 × 24 box. The body leans the way the FL Studio fruit does.
struct FruitMark: View {
    var body: some View {
        Canvas { context, size in
            let unit = size.width / 24
            context.scaleBy(x: unit, y: unit)
            FruitPaint.draw(in: &context)
        }
    }
}

enum FruitPaint {
    static let orangeDark = Color(red: 0.93, green: 0.33, blue: 0.08)
    static let orangeLight = Color(red: 1, green: 0.7, blue: 0.24)
    static let leafDark = Color(red: 0.24, green: 0.47, blue: 0.16)
    static let leafLight = Color(red: 0.6, green: 0.8, blue: 0.36)

    // Outlines traced from the reference silhouette, in a 24 x 24 box: the
    // body, and the leaves with the stem as one piece. Scripts/trace-fruit.py
    // makes them from a black-on-white image.
    private static let bodyPoints: [CGPoint] = [CGPoint(x: 8.52, y: 7.21), CGPoint(x: 8.77, y: 7.21), CGPoint(x: 8.84, y: 7.28), CGPoint(x: 8.84, y: 8.29), CGPoint(x: 8.9, y: 8.96), CGPoint(x: 9.07, y: 9.79), CGPoint(x: 9.26, y: 10.29), CGPoint(x: 9.58, y: 10.82), CGPoint(x: 10.06, y: 11.4), CGPoint(x: 10.78, y: 11.93), CGPoint(x: 11.22, y: 12.11), CGPoint(x: 11.72, y: 12.21), CGPoint(x: 12.37, y: 12.17), CGPoint(x: 12.97, y: 11.99), CGPoint(x: 13.48, y: 11.73), CGPoint(x: 14.05, y: 11.32), CGPoint(x: 14.56, y: 10.85), CGPoint(x: 15.38, y: 9.9), CGPoint(x: 15.48, y: 9.95), CGPoint(x: 16.47, y: 11.1), CGPoint(x: 16.68, y: 11.42), CGPoint(x: 16.75, y: 11.65), CGPoint(x: 16.57, y: 12.37), CGPoint(x: 16.15, y: 13.55), CGPoint(x: 15.34, y: 15.44), CGPoint(x: 13.92, y: 18.02), CGPoint(x: 12.64, y: 19.91), CGPoint(x: 11.54, y: 21.22), CGPoint(x: 10.99, y: 21.78), CGPoint(x: 10.18, y: 22.44), CGPoint(x: 9.62, y: 22.8), CGPoint(x: 9.05, y: 23.07), CGPoint(x: 8.56, y: 23.22), CGPoint(x: 8.01, y: 23.28), CGPoint(x: 7.32, y: 23.13), CGPoint(x: 6.86, y: 22.83), CGPoint(x: 6.15, y: 22.05), CGPoint(x: 5.81, y: 21.41), CGPoint(x: 5.43, y: 20.19), CGPoint(x: 5.17, y: 18.87), CGPoint(x: 5.06, y: 17.33), CGPoint(x: 5.06, y: 15.87), CGPoint(x: 5.15, y: 14.12), CGPoint(x: 5.3, y: 12.74), CGPoint(x: 5.76, y: 10.41), CGPoint(x: 6.2, y: 8.93), CGPoint(x: 6.67, y: 7.99), CGPoint(x: 7.09, y: 7.52), CGPoint(x: 7.64, y: 7.33)]
    private static let leafPoints: [CGPoint] = [CGPoint(x: 16.61, y: 0.73), CGPoint(x: 15.2, y: 2.22), CGPoint(x: 14.34, y: 3.38), CGPoint(x: 13.66, y: 4.69), CGPoint(x: 13.51, y: 5.2), CGPoint(x: 13.47, y: 5.68), CGPoint(x: 13.57, y: 5.75), CGPoint(x: 14.95, y: 5.68), CGPoint(x: 15.57, y: 5.76), CGPoint(x: 16.15, y: 5.92), CGPoint(x: 16.52, y: 6.08), CGPoint(x: 17.14, y: 6.47), CGPoint(x: 17.6, y: 6.86), CGPoint(x: 17.98, y: 7.27), CGPoint(x: 18.35, y: 7.8), CGPoint(x: 18.63, y: 8.36), CGPoint(x: 18.82, y: 8.96), CGPoint(x: 18.92, y: 9.65), CGPoint(x: 18.88, y: 10.43), CGPoint(x: 18.76, y: 10.96), CGPoint(x: 18.54, y: 11.47), CGPoint(x: 18.27, y: 11.76), CGPoint(x: 18.13, y: 11.77), CGPoint(x: 17.9, y: 11.61), CGPoint(x: 15.92, y: 9.49), CGPoint(x: 15.25, y: 8.93), CGPoint(x: 15.03, y: 9.07), CGPoint(x: 14.53, y: 9.86), CGPoint(x: 14.14, y: 10.32), CGPoint(x: 13.22, y: 11.06), CGPoint(x: 12.65, y: 11.37), CGPoint(x: 12.18, y: 11.5), CGPoint(x: 11.79, y: 11.52), CGPoint(x: 11.31, y: 11.41), CGPoint(x: 10.94, y: 11.22), CGPoint(x: 10.53, y: 10.89), CGPoint(x: 10.12, y: 10.39), CGPoint(x: 9.85, y: 9.81), CGPoint(x: 9.64, y: 9.03), CGPoint(x: 9.51, y: 8.13), CGPoint(x: 9.67, y: 6.58), CGPoint(x: 9.63, y: 6.42), CGPoint(x: 8.22, y: 6.55), CGPoint(x: 5.5, y: 7.02), CGPoint(x: 5.22, y: 7.0), CGPoint(x: 5.09, y: 6.9), CGPoint(x: 5.09, y: 6.42), CGPoint(x: 5.27, y: 5.89), CGPoint(x: 5.66, y: 5.22), CGPoint(x: 6.21, y: 4.55), CGPoint(x: 6.74, y: 4.1), CGPoint(x: 7.25, y: 3.77), CGPoint(x: 8.33, y: 3.39), CGPoint(x: 9.35, y: 3.31), CGPoint(x: 9.99, y: 3.4), CGPoint(x: 10.73, y: 3.64), CGPoint(x: 11.15, y: 3.85), CGPoint(x: 11.58, y: 4.15), CGPoint(x: 12.09, y: 4.6), CGPoint(x: 12.6, y: 5.27), CGPoint(x: 12.74, y: 5.36), CGPoint(x: 12.85, y: 5.34), CGPoint(x: 13.54, y: 4.02), CGPoint(x: 14.62, y: 2.54), CGPoint(x: 15.71, y: 1.37)]

    static let body = smoothPath(bodyPoints)
    static let leaves = smoothPath(leafPoints)
    /// Where the body sits, for cutting it into slices.
    static let bodyBounds = body.boundingRect

    /// A closed curve through every point (Catmull-Rom as cubic curves).
    private static func smoothPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        let count = points.count
        guard count > 2 else { return path }
        path.move(to: points[0])
        for i in 0..<count {
            let p0 = points[(i - 1 + count) % count], p1 = points[i]
            let p2 = points[(i + 1) % count], p3 = points[(i + 2) % count]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }

    static func draw(in context: inout GraphicsContext, bodyOnly: Bool = false) {
        // Body with a soft highlight on its upper left.
        context.fill(body, with: .linearGradient(
            Gradient(colors: [orangeLight, orangeDark]),
            startPoint: CGPoint(x: bodyBounds.minX + 2, y: bodyBounds.minY),
            endPoint: CGPoint(x: bodyBounds.maxX, y: bodyBounds.maxY)))
        var shine = context
        shine.clip(to: body)
        shine.fill(Path(ellipseIn: CGRect(x: bodyBounds.minX + 1.2, y: bodyBounds.minY + 1.6, width: 3, height: 5.5)),
                   with: .color(.white.opacity(0.25)))
        guard !bodyOnly else { return }
        drawLeaves(in: &context)
    }

    static func drawLeaves(in context: inout GraphicsContext) {
        let box = leaves.boundingRect
        context.fill(leaves, with: .linearGradient(
            Gradient(colors: [leafLight, leafDark]),
            startPoint: CGPoint(x: box.minX, y: box.minY), endPoint: CGPoint(x: box.maxX, y: box.maxY)))
    }
}

/// Rendering: a blade sweeps down through the fruit and the body comes apart
/// in slices that slide sideways, then closes up again, over and over.
struct SlicedFruit: View {
    private static let slices = 4
    private static let period = 1.3

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
            Canvas { canvas, size in
                let unit = size.width / 24
                canvas.scaleBy(x: unit, y: unit)

                // Cut lines between y = 9 and y = 22; each opens once the blade has passed it.
                let top = FruitPaint.bodyBounds.minY - 0.5, bottom = FruitPaint.bodyBounds.maxY + 0.5
                let blade = top + (bottom - top) * CGFloat(min(1, t / 0.5))
                let close = t > 0.75 ? CGFloat((t - 0.75) / 0.25) : 0
                for slice in 0..<Self.slices {
                    let y0 = top + (bottom - top) * CGFloat(slice) / CGFloat(Self.slices)
                    let y1 = top + (bottom - top) * CGFloat(slice + 1) / CGFloat(Self.slices)
                    let cut = blade > y0 ? min(1, (blade - y0) / 3) : 0
                    let spread = cut * (1 - close) * (slice.isMultiple(of: 2) ? -1.4 : 1.4)
                    var piece = canvas
                    piece.translateBy(x: spread, y: CGFloat(slice) * 0.5 * cut * (1 - close))
                    piece.clip(to: Path(CGRect(x: 0, y: y0 + 0.25, width: 24, height: y1 - y0 - 0.25)))
                    FruitPaint.draw(in: &piece, bodyOnly: true)
                }
                FruitPaint.drawLeaves(in: &canvas)

                // The blade: a bright line crossing the fruit while it falls.
                if t < 0.55 {
                    var line = Path()
                    line.move(to: CGPoint(x: 2, y: blade - 1.2))
                    line.addLine(to: CGPoint(x: 21, y: blade + 1.2))
                    canvas.stroke(line, with: .color(.white.opacity(0.9 * (1 - t / 0.55))),
                                  style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
                }
            }
        }
    }
}

// MARK: The right ear

/// Orange ring filling with the render; it spins while the progress is unknown.
struct ProgressRing: View {
    let progress: Double?

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: 2.4)
            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, progress)))
                    .stroke(ringOrange, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.25), value: progress)
            } else {
                TimelineView(.animation) { context in
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(ringOrange, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 360))
                }
            }
        }
        .padding(1.5)
    }
}

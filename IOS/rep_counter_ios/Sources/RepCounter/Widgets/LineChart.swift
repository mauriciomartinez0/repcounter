// Minimal chart from the mockups: lines at the top and bottom of the range
// with their values, one ink line, and the sensor dot on the latest point.

import SwiftUI

struct ChartPoint {
    let date: Date
    let value: Double
}

struct LineChart: View {
    let points: [ChartPoint]
    let format: (Double) -> String
    /// Draw as steps (weights move in jumps, not slopes).
    var step = false
    var height: CGFloat = 170
    @Environment(\.colors) private var c

    var body: some View {
        if points.isEmpty {
            Text("Todavía no hay datos.")
                .font(.text(15))
                .foregroundStyle(c.ink2)
                .frame(maxWidth: .infinity)
                .frame(height: height)
        } else {
            let (lo, hi) = range
            VStack(alignment: .leading, spacing: 0) {
                Text(format(hi)).font(.text(11)).foregroundStyle(c.ink2)
                Canvas { ctx, size in
                    draw(ctx, size, lo: lo, hi: hi)
                }
                .frame(height: height)
                .padding(.vertical, 4)
                Text(format(lo)).font(.text(11)).foregroundStyle(c.ink2)
                HStack {
                    Text(formatShortDate(points.first!.date))
                    Spacer()
                    if points.count > 1 { Text(formatShortDate(points.last!.date)) }
                }
                .font(.text(13))
                .foregroundStyle(c.ink2)
                .padding(.top, 10)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gráfica de \(points.count) puntos, de \(format(lo)) a \(format(hi)). "
                + "Último valor \(format(points.last!.value)).")
        }
    }

    private var range: (Double, Double) {
        let values = points.map(\.value)
        var lo = values.min()!
        var hi = values.max()!
        if hi == lo {
            hi += hi == 0 ? 1 : hi * 0.1
            lo -= lo == 0 ? 0 : lo * 0.1
        }
        return (lo, hi)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, lo: Double, hi: Double) {
        let inset: CGFloat = 8 // keeps the end dot inside the box
        var rules = Path()
        rules.move(to: CGPoint(x: 0, y: inset))
        rules.addLine(to: CGPoint(x: size.width, y: inset))
        rules.move(to: CGPoint(x: 0, y: size.height - inset))
        rules.addLine(to: CGPoint(x: size.width, y: size.height - inset))
        ctx.stroke(rules, with: .color(c.line), lineWidth: 1)

        let first = points.first!.date.timeIntervalSince1970
        let last = points.last!.date.timeIntervalSince1970
        let span = max(0.001, last - first)
        let h = size.height - 2 * inset
        let w = size.width - 2 * inset

        func at(_ p: ChartPoint) -> CGPoint {
            let x = points.count == 1
                ? size.width - inset
                : inset + CGFloat((p.date.timeIntervalSince1970 - first) / span) * w
            let y = inset + CGFloat(1 - (p.value - lo) / (hi - lo)) * h
            return CGPoint(x: x, y: y)
        }

        var path = Path()
        for (i, p) in points.enumerated() {
            let o = at(p)
            if i == 0 {
                path.move(to: o)
            } else if step {
                let prev = at(points[i - 1])
                // Hold the previous value, then rise over a short ramp, as drawn.
                let ramp = min(18, (o.x - prev.x) / 2)
                path.addLine(to: CGPoint(x: o.x - ramp, y: prev.y))
                path.addLine(to: o)
            } else {
                path.addLine(to: o)
            }
        }
        ctx.stroke(path, with: .color(c.ink),
                   style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))

        let end = at(points.last!)
        let dot = Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10))
        ctx.fill(dot, with: .color(c.dot))
        ctx.stroke(dot, with: .color(c.dotRing ?? c.dot), lineWidth: 1.5)
    }
}

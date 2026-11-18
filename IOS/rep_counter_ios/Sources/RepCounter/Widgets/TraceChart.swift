// The movement of one set: the height of the weight stack, or the angle,
// over the time of the set. Each rep is one wave. Same look as LineChart:
// rules at the top and bottom of the range with their values, one ink line.

import SwiftUI

struct TraceChart: View {
    let trace: SetTrace
    var height: CGFloat = 72
    @Environment(\.colors) private var c

    private func format(_ v: Double) -> String {
        trace.kind == .height ? "\(formatNumber(v.rounded())) cm" : "\(Int(v.rounded()))°"
    }

    var body: some View {
        let lo = trace.values.min() ?? 0
        let hi = max(lo + 1, trace.values.max() ?? 1)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                AppLabel(trace.kind == .height ? "Recorrido de la pila" : "Ángulo", color: c.ink2, size: 10)
                Spacer()
                Text(format(hi)).font(.text(11)).foregroundStyle(c.ink2)
            }
            Canvas { ctx, size in draw(ctx, size, lo: lo, hi: hi) }
                .frame(height: height)
                .padding(.vertical, 4)
            HStack {
                Text("0 s")
                Spacer()
                Text(format(lo))
                Spacer()
                Text("\(Int(trace.seconds.rounded())) s")
            }
            .font(.text(11))
            .foregroundStyle(c.ink2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(trace.kind == .height ? "Recorrido de la pila" : "Ángulo") durante "
                + "\(Int(trace.seconds.rounded())) segundos, de \(format(lo)) a \(format(hi)).")
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, lo: Double, hi: Double) {
        let inset: CGFloat = 2
        var rules = Path()
        rules.move(to: CGPoint(x: 0, y: inset))
        rules.addLine(to: CGPoint(x: size.width, y: inset))
        rules.move(to: CGPoint(x: 0, y: size.height - inset))
        rules.addLine(to: CGPoint(x: size.width, y: size.height - inset))
        ctx.stroke(rules, with: .color(c.line), lineWidth: 1)

        let values = trace.values
        guard values.count > 1 else { return }
        let h = size.height - 2 * inset
        // At most about one point per pixel: a long set has thousands.
        let stride = max(1, values.count / max(1, Int(size.width)))
        var path = Path()
        for i in Swift.stride(from: 0, to: values.count, by: stride) {
            let x = CGFloat(i) / CGFloat(values.count - 1) * size.width
            let y = inset + CGFloat(1 - (values[i] - lo) / (hi - lo)) * h
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.stroke(path, with: .color(c.ink),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
}

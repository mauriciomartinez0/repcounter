// The movement of one set: the height of the weight stack, or the angle,
// over the time of the set. Each rep is one wave. Same look as LineChart:
// rules at the top and bottom of the range with their values, one ink line.

import SwiftUI

struct TraceChart: View {
    let trace: SetTrace
    var height: CGFloat = 72
    /// Live, on the counter: the width is always this many seconds (the line
    /// grows from the left until it fills them, then scrolls), and the scale
    /// never shrinks below a few cm or degrees, so a still stack is a flat
    /// line instead of magnified noise.
    var liveSeconds: Double?
    @Environment(\.colors) private var c

    private func format(_ v: Double) -> String {
        trace.kind == .height ? "\(formatNumber(v.rounded())) cm" : "\(Int(v.rounded()))°"
    }

    var body: some View {
        let minSpan = liveSeconds == nil ? 1.0 : (trace.kind == .height ? 10 : 20)
        let low = trace.values.min() ?? 0
        let high = trace.values.max() ?? 1
        let pad = max(0, minSpan - (high - low)) / 2
        let lo = trace.kind == .angle ? max(0, low - pad) : low - pad
        let hi = max(lo + minSpan, high + pad)
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
                if let liveSeconds {
                    Text("−\(Int(liveSeconds)) s")
                    Spacer()
                    Text(format(lo))
                    Spacer()
                    Text("ahora")
                } else {
                    Text("0 s")
                    Spacer()
                    Text(format(lo))
                    Spacer()
                    Text("\(Int(trace.seconds.rounded())) s")
                }
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
        // Live: a fixed time scale, so the line moves at a steady pace.
        let span = max(values.count - 1, Int((liveSeconds ?? 0) * Double(trace.sampleHz)))
        var path = Path()
        for i in Swift.stride(from: 0, to: values.count, by: stride) {
            let x = CGFloat(i) / CGFloat(span) * size.width
            let y = inset + CGFloat(1 - (values[i] - lo) / (hi - lo)) * h
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.stroke(path, with: .color(c.ink),
                   style: StrokeStyle(lineWidth: liveSeconds == nil ? 1.5 : 2, lineCap: .round, lineJoin: .round))
        if liveSeconds != nil, let last = values.last {
            // Where the stack (or the limb) is right now.
            let x = CGFloat(values.count - 1) / CGFloat(span) * size.width
            let y = inset + CGFloat(1 - (last - lo) / (hi - lo)) * h
            ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(c.mark))
        }
    }
}

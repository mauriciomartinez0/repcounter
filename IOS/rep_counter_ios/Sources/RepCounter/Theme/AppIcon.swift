// Icons from the style guide: 24 box, 1.75 stroke, round ends, no fill.
// The lime dot (the sensor) only appears in the three placement icons.
//
// The shapes are the same SVG paths the Flutter app uses, parsed into
// SwiftUI paths, so both apps draw identical icons.

import SwiftUI

private enum IconElement {
    /// A stroked path; `filled` also fills it with the ink color.
    case path(String, filled: Bool = false)
    case circle(CGFloat, CGFloat, CGFloat)
    case rect(CGFloat, CGFloat, CGFloat, CGFloat, rx: CGFloat)
    /// The sensor dot: lime fill, dark ring in the light theme.
    case dot(CGFloat, CGFloat, CGFloat)
}

enum AppIconKind: Hashable {
    case back, forward, plus, minus, settings, dragHandle, check, play, pause
    case star, starOutline, arrowUp, arrowDown
    // Equipment type.
    case barbell, dumbbell, machine, bodyweight, cable
    // Sensor placement.
    case placementArm, placementBody, placementEquipment

    private static let starPath =
        "M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.9-5.2-2.8-5.2 2.8 1-5.9-4.3-4.1 5.9-.8z"
    private static let barbellPath = "M2 12h20M4.5 7v10M7.5 9v6M19.5 7v10M16.5 9v6"

    fileprivate var elements: [IconElement] {
        switch self {
        case .back: [.path("M15 5l-7 7 7 7")]
        case .forward: [.path("M9 5l7 7-7 7")]
        case .plus: [.path("M12 5v14M5 12h14")]
        case .minus: [.path("M5 12h14")]
        case .settings:
            [.path("M4 8h10M18 8h2M4 16h2M10 16h10"), .circle(16, 8, 2), .circle(8, 16, 2)]
        case .dragHandle: [.path("M5 9h14M5 15h14")]
        case .check: [.path("M5 12.5l4.5 4.5L19 7.5")]
        case .play: [.path("M9 6.5v11l9-5.5z", filled: true)]
        case .pause: [.path("M9 6v12M15 6v12")]
        case .star: [.path(Self.starPath, filled: true)]
        case .starOutline: [.path(Self.starPath)]
        case .arrowUp: [.path("M12 19V5M6 11l6-6 6 6")]
        case .arrowDown: [.path("M12 5v14M6 13l6 6 6-6")]
        case .barbell: [.path(Self.barbellPath)]
        case .dumbbell:
            [.path("M9 12h6"), .rect(4.5, 7.5, 4.5, 9, rx: 1.25), .rect(15, 7.5, 4.5, 9, rx: 1.25)]
        case .machine:
            [.rect(7, 7, 10, 13, rx: 1.25), .path("M7 11.5h10M7 16h10M12 7V3M9 3h6")]
        case .bodyweight:
            [.circle(12, 4.5, 2), .path("M12 7.5V15M6.5 10h11M12 15l-3.5 6M12 15l3.5 6")]
        case .cable:
            [.circle(12, 6.5, 3.5), .path("M8.5 6.5V18M6 18h5M15.5 6.5V13")]
        case .placementArm:
            [.path("M5 3v8a3 3 0 0 0 3 3h10"), .circle(20, 14, 2), .dot(13, 14, 3)]
        case .placementBody:
            [.circle(12, 5, 2.5), .path("M6.5 21v-6.5a5.5 5.5 0 0 1 11 0V21"), .dot(12, 17.5, 3)]
        case .placementEquipment:
            [.path(Self.barbellPath), .dot(12, 12, 3)]
        }
    }
}

struct AppIcon: View {
    let kind: AppIconKind
    var size: CGFloat = 24
    var color: Color?
    var strokeWidth: CGFloat = 1.75

    @Environment(\.colors) private var c

    init(_ kind: AppIconKind, size: CGFloat = 24, color: Color? = nil, strokeWidth: CGFloat = 1.75) {
        self.kind = kind
        self.size = size
        self.color = color
        self.strokeWidth = strokeWidth
    }

    var body: some View {
        let ink = color ?? c.ink
        let colors = c
        Canvas { ctx, canvasSize in
            let scale = canvasSize.width / 24
            ctx.scaleBy(x: scale, y: scale)
            let stroke = StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
            for element in kind.elements {
                switch element {
                case .path(let d, let filled):
                    let path = SVGPath.parse(d)
                    if filled { ctx.fill(path, with: .color(ink)) }
                    ctx.stroke(path, with: .color(ink), style: stroke)
                case .circle(let cx, let cy, let r):
                    let path = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
                    ctx.stroke(path, with: .color(ink), style: stroke)
                case .rect(let x, let y, let w, let h, let rx):
                    let path = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: rx)
                    ctx.stroke(path, with: .color(ink), style: stroke)
                case .dot(let cx, let cy, let r):
                    let path = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
                    ctx.fill(path, with: .color(colors.dot))
                    if let ring = colors.dotRing {
                        ctx.stroke(path, with: .color(ring), lineWidth: 1.25)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Minimal SVG path parser: the commands the icons use (M L H V A Z, both
/// absolute and relative).
enum SVGPath {
    private static var cache: [String: Path] = [:]

    static func parse(_ d: String) -> Path {
        if let cached = cache[d] { return cached }
        let path = build(tokens: tokenize(d))
        cache[d] = path
        return path
    }

    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(d)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch.isLetter && ch != "e" && ch != "E" {
                tokens.append(.command(ch))
                i += 1
            } else if ch == "-" || ch == "+" || ch == "." || ch.isNumber {
                var j = i
                var text = ""
                if chars[j] == "-" || chars[j] == "+" {
                    text.append(chars[j])
                    j += 1
                }
                var sawDot = false
                while j < chars.count {
                    let c = chars[j]
                    if c.isNumber {
                        text.append(c)
                    } else if c == "." && !sawDot {
                        sawDot = true
                        text.append(c)
                    } else {
                        break
                    }
                    j += 1
                }
                tokens.append(.number(CGFloat(Double(text) ?? 0)))
                i = j
            } else {
                i += 1
            }
        }
        return tokens
    }

    private static func build(tokens: [Token]) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var command: Character = "M"
        var i = 0

        func next() -> CGFloat {
            guard i < tokens.count, case .number(let v) = tokens[i] else { return 0 }
            i += 1
            return v
        }

        while i < tokens.count {
            if case .command(let c) = tokens[i] {
                command = c
                i += 1
                if c == "Z" || c == "z" {
                    path.closeSubpath()
                    current = start
                    continue
                }
            }
            let relative = command.isLowercase
            switch command {
            case "M", "m":
                let x = next(), y = next()
                current = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                start = current
                path.move(to: current)
                // Extra pairs after a move are line-tos.
                command = relative ? "l" : "L"
            case "L", "l":
                let x = next(), y = next()
                current = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addLine(to: current)
            case "H", "h":
                let x = next()
                current.x = relative ? current.x + x : x
                path.addLine(to: current)
            case "V", "v":
                let y = next()
                current.y = relative ? current.y + y : y
                path.addLine(to: current)
            case "A", "a":
                let rx = next(), ry = next()
                _ = next() // rotation; the icons only use circular arcs
                let large = next() != 0
                let sweep = next() != 0
                let x = next(), y = next()
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                addArc(&path, from: current, to: end, radius: max(rx, ry), large: large, sweep: sweep)
                current = end
            default:
                i += 1
            }
        }
        return path
    }

    /// Endpoint-to-center conversion (SVG spec F.6.5) for a circular arc,
    /// drawn as short segments.
    private static func addArc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint,
                               radius: CGFloat, large: Bool, sweep: Bool) {
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        var r = radius
        let d2 = dx * dx + dy * dy
        if d2 > r * r { r = sqrt(d2) }
        var factor = sqrt(max(0, (r * r - d2) / d2))
        if large == sweep { factor = -factor }
        let cx = factor * dy + (p0.x + p1.x) / 2
        let cy = -factor * dx + (p0.y + p1.y) / 2
        let a0 = atan2(p0.y - cy, p0.x - cx)
        var a1 = atan2(p1.y - cy, p1.x - cx)
        if sweep && a1 < a0 { a1 += 2 * .pi }
        if !sweep && a1 > a0 { a1 -= 2 * .pi }
        let steps = 24
        for s in 1...steps {
            let a = a0 + (a1 - a0) * CGFloat(s) / CGFloat(steps)
            path.addLine(to: CGPoint(x: cx + r * cos(a), y: cy + r * sin(a)))
        }
    }
}

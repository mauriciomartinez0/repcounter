// Developer panel: the sets recorded in developer mode, to see what the board
// counted next to what the sensor read and what was really done.

import SwiftUI

struct DevPanelScreen: View {
    @Environment(\.colors) private var c
    private var store: DevCaptureStore { DevCaptureStore.shared }

    private func deleteAll() {
        Task {
            let sure = await confirm(
                title: "¿Borrar todas las capturas?",
                message: "Se borran de este teléfono. Si ya las copiaste a la computadora, allá se quedan.",
                confirmLabel: "Borrar todas"
            )
            if sure { store.deleteAll() }
        }
    }

    var body: some View {
        let captures = store.summaries
        let judged = captures.filter { $0.trueReps != nil }
        let exact = judged.filter { $0.recordedReps == $0.trueReps }.count
        VStack(spacing: 0) {
            BackHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 8)
                    Text("Panel desarrollador")
                        .font(.text(36, .medium))
                        .foregroundStyle(c.ink)
                    Spacer().frame(height: 8)
                    Text("Con el modo desarrollador, cada serie se graba: el acelerómetro tal cual, lo que "
                        + "mandó la placa y lo que contó. Al terminarla, la app te pregunta cuántas hiciste "
                        + "de verdad.")
                        .font(.text(15))
                        .foregroundStyle(c.ink2)
                    Spacer().frame(height: 8)
                    Text("Para analizarlas en la computadora, conecta el iPhone por USB y corre "
                        + "rep_counter_ble/dev/pull_captures.sh.")
                        .font(.text(14))
                        .foregroundStyle(c.ink3)
                    Spacer().frame(height: 24)
                    StatPair {
                        StatCell(label: "Capturas") {
                            NumberWithUnit(value: "\(captures.count)", unit: nil)
                        }
                    } right: {
                        StatCell(label: "Conteo exacto") {
                            NumberWithUnit(value: judged.isEmpty ? "—" : "\(exact)/\(judged.count)", unit: nil)
                        }
                    }
                    Spacer().frame(height: 24)
                    if captures.isEmpty {
                        Text("Todavía no hay capturas. Activa el modo desarrollador y haz una serie.")
                            .font(.text(16))
                            .foregroundStyle(c.ink2)
                    }
                    ForEach(captures) { capture in
                        Pressable(action: { Router.shared.push(.devCapture(capture.id)) },
                                  label: "Abrir la captura de \(capture.exerciseName)") {
                            DevCaptureRow(capture: capture)
                        }
                    }
                    if !captures.isEmpty {
                        Spacer().frame(height: 24)
                        TextAction(label: "Borrar todas", action: deleteAll)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(EdgeInsets(top: 0, leading: kGutter, bottom: 32, trailing: kGutter))
            }
        }
        .onAppear { store.reload() }
    }
}

private struct DevCaptureRow: View {
    let capture: DevCapture
    @Environment(\.colors) private var c

    var body: some View {
        let truth = capture.trueReps
        let off = truth.map { $0 != capture.recordedReps } ?? false
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(capture.exerciseName) · serie \(capture.setNumber)")
                    .font(.text(17, .medium))
                    .foregroundStyle(c.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(truth == nil ? "placa \(capture.liveReps)" : "placa \(capture.liveReps) · real \(truth!)")
                    .font(.text(15, off ? .semibold : .regular))
                    .foregroundStyle(off ? c.ink : c.ink2)
            }
            Text("\(formatDay(capture.createdAt)), \(devClock(capture.createdAt)) · \(Int(capture.duration)) s · "
                + (capture.rawSamples > 0 ? "\(capture.rawSamples) lecturas" : "sin datos crudos"))
                .font(.text(14))
                .foregroundStyle(c.ink3)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bottomRule(c.line)
    }
}

func devClock(_ d: Date) -> String {
    let p = Calendar.current.dateComponents([.hour, .minute, .second], from: d)
    return String(format: "%d:%02d:%02d", p.hour ?? 0, p.minute ?? 0, p.second ?? 0)
}

struct DevCaptureScreen: View {
    let captureId: String
    @Environment(\.colors) private var c
    @State private var capture: DevCapture?

    private func delete() {
        Task {
            let sure = await confirm(title: "¿Borrar esta captura?", message: "Se borra de este teléfono.",
                                     confirmLabel: "Borrar")
            guard sure else { return }
            DevCaptureStore.shared.delete(captureId)
            Router.shared.pop()
        }
    }

    private func setTruth(_ n: Int) {
        DevCaptureStore.shared.update(captureId, trueReps: n)
        capture?.trueReps = n
    }

    var body: some View {
        VStack(spacing: 0) {
            BackHeader {
                ShareLink(item: DevCaptureStore.file(captureId)) {
                    Text("Compartir").font(.text(15, .semibold)).foregroundStyle(c.ink)
                        .padding(.horizontal, 12).frame(height: 44)
                }
                TextAction(label: "Borrar", size: 15, action: delete)
                    .padding(.trailing, 12)
            }
            if let capture {
                ScrollView { DevCaptureDetail(capture: capture, onTruth: setTruth) }
            } else {
                Spacer()
            }
        }
        .onAppear { capture = DevCaptureStore.shared.load(captureId) }
    }
}

private struct DevCaptureDetail: View {
    let capture: DevCapture
    let onTruth: (Int) -> Void
    @Environment(\.colors) private var c

    /// Rep marks: when the board's count went up.
    private var reps: [Double] { capture.events.filter { $0.1 == "rep" }.map(\.0) }

    /// |a| − 1 g in mg, at 104 Hz from rawStart; nil where packets were lost.
    private var magnitude: [(Double, Double)] {
        let raw = capture.raw
        let hz = Double(capture.rawSampleHz)
        var out: [(Double, Double)] = []
        out.reserveCapacity(raw.count / 3)
        var i = 0
        while i + 2 < raw.count {
            if raw[i] != Int16.min {
                let x = Double(raw[i]), y = Double(raw[i + 1]), z = Double(raw[i + 2])
                let g = (x * x + y * y + z * z).squareRoot() * capture.rawGPerCount
                out.append((capture.rawStart + Double(i / 3) / hz, (g - 1) * 1000))
            }
            i += 3
        }
        return out
    }

    /// The board's value (stack speed in cm/s, or the angle).
    private var value: [(Double, Double)] { capture.states.compactMap { $0.count >= 3 ? ($0[0], $0[2]) : nil } }

    private var count: [(Double, Double)] { capture.states.compactMap { $0.count >= 2 ? ($0[0], $0[1]) : nil } }

    /// The stack speed integrated as it is, without any correction: if the
    /// board's velocity drifts, it shows here as a slope.
    private var height: [(Double, Double)] {
        var h = 0.0
        var out: [(Double, Double)] = []
        let v = value
        for k in v.indices {
            if k > 0 { h += (v[k].1 + v[k - 1].1) / 2 * (v[k].0 - v[k - 1].0) }
            out.append((v[k].0, h))
        }
        return out
    }

    var body: some View {
        let stack = profileFollowsHeight(capture.firmwareProfile)
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 8)
            Text(capture.exerciseName)
                .font(.text(30, .medium))
                .foregroundStyle(c.ink)
            Spacer().frame(height: 4)
            Text("Serie \(capture.setNumber) · \(formatDay(capture.createdAt)), \(devClock(capture.createdAt))")
                .font(.text(16))
                .foregroundStyle(c.ink2)
            Spacer().frame(height: 24)
            StatPair {
                StatCell(label: "Contó la placa") {
                    NumberWithUnit(value: "\(capture.liveReps)", unit: nil)
                }
            } right: {
                StatCell(label: "Análisis al cerrar") {
                    NumberWithUnit(value: capture.analysisFound.map(String.init) ?? "—", unit: nil)
                }
            }
            Spacer().frame(height: 20)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    AppLabel("Las que hiciste de verdad")
                    Text("Se guardaron \(capture.recordedReps) en el historial.")
                        .font(.text(13))
                        .foregroundStyle(c.ink3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CountStepper(value: capture.trueReps ?? capture.recordedReps, compact: true, onChanged: onTruth)
            }
            Spacer().frame(height: 28)
            DevSeriesChart(title: "Aceleración: |a| − 1 g", unit: "mg", points: magnitude,
                           duration: capture.duration, marks: reps,
                           empty: "Sin datos crudos: la placa no los mandó (firmware sin modo desarrollador).")
            Spacer().frame(height: 24)
            DevSeriesChart(title: stack ? "Velocidad que calculó la placa" : "Ángulo que calculó la placa",
                           unit: stack ? "cm/s" : "°", points: value, duration: capture.duration, marks: reps,
                           zeroLine: stack)
            if stack {
                Spacer().frame(height: 24)
                DevSeriesChart(title: "Altura (integral de esa velocidad, sin corregir)", unit: "cm",
                               points: height, duration: capture.duration, marks: reps)
            }
            Spacer().frame(height: 24)
            DevSeriesChart(title: "Conteo de la placa", unit: "", points: count, duration: capture.duration,
                           marks: reps, step: true)
            Spacer().frame(height: 28)
            AppLabel("Datos")
            Spacer().frame(height: 4)
            detail("Duración", "\(String(format: "%.1f", capture.duration)) s")
            detail("Perfil del firmware", "\(capture.firmwareProfile)" + (capture.firmwareProfile == kStackProfile ? " (altura)"
                : capture.firmwareProfile == kBarFromTopProfile ? " (altura, desde arriba)" : ""))
            detail("Sensibilidad", "\(capture.sensitivity) %")
            detail("Objetivo", capture.targetReps.map(String.init) ?? "—")
            detail("Lecturas crudas", "\(capture.rawSamples)")
            detail("Paquetes perdidos", capture.rawPackets == 0 ? "—"
                   : "\(capture.rawLostPackets) de \(capture.rawPackets + capture.rawLostPackets)")
            detail("Paquetes de estado", "\(capture.states.count)")
            Spacer().frame(height: 28)
            AppLabel("Eventos")
            Spacer().frame(height: 8)
            ForEach(Array(capture.events.enumerated()), id: \.offset) { _, e in
                HStack {
                    Text(String(format: "%6.2f s", e.0)).font(.text(14)).foregroundStyle(c.ink3)
                        .frame(width: 80, alignment: .leading)
                    Text(Self.eventLabel(e.1, e.2)).font(.text(14)).foregroundStyle(c.ink)
                    Spacer()
                }
                .padding(.vertical, 3)
            }
        }
        .padding(EdgeInsets(top: 0, leading: kGutter, bottom: 32, trailing: kGutter))
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.text(15)).foregroundStyle(c.ink2)
            Spacer()
            Text(value).font(.text(15, .medium)).foregroundStyle(c.ink)
        }
        .frame(height: 40)
        .bottomRule(c.line)
    }

    private static func eventLabel(_ name: String, _ v: Double) -> String {
        let n = Int(v)
        switch name {
        case "calibrating": return "Calibrando"
        case "counting": return "Empieza a contar"
        case "rep": return "Repetición \(n)"
        case "boardReset": return "La placa reinició el conteo"
        case "sensitivity": return "Sensibilidad \(n) %"
        case "restart": return "Reiniciar serie"
        case "finish": return "Fin de la serie: \(n) en vivo"
        case "analysis": return "Análisis: \(n)"
        case "review": return n == 1 ? "Sumó las del análisis" : "Dejó el conteo en vivo"
        case "recorded": return "Guardada con \(n)"
        default: return "\(name) \(v)"
        }
    }
}

/// One signal over the time of the capture: rules at its range with the
/// values, one ink line, and a lime tick where the board counted a rep.
struct DevSeriesChart: View {
    let title: String
    let unit: String
    let points: [(Double, Double)]
    let duration: Double
    var marks: [Double] = []
    var step = false
    var zeroLine = false
    var empty = "Sin datos."
    var height: CGFloat = 120
    @Environment(\.colors) private var c

    private func format(_ v: Double) -> String {
        let s = abs(v) >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
        return unit.isEmpty ? s : "\(s) \(unit)"
    }

    var body: some View {
        let values = points.map(\.1)
        let lo = values.min() ?? 0
        let hi = Swift.max(lo + 1e-6, values.max() ?? 1)
        let span = Swift.max(duration, points.last?.0 ?? 0, 0.001)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                AppLabel(title, color: c.ink2, size: 11)
                Spacer()
                if !points.isEmpty { Text(format(hi)).font(.text(11)).foregroundStyle(c.ink2) }
            }
            if points.isEmpty {
                Text(empty).font(.text(14)).foregroundStyle(c.ink3)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                Canvas { ctx, size in draw(ctx, size, lo: lo, hi: hi, span: span) }
                    .frame(height: height)
                HStack {
                    Text("0 s")
                    Spacer()
                    Text(format(lo))
                    Spacer()
                    Text(String(format: "%.0f s", span))
                }
                .font(.text(11))
                .foregroundStyle(c.ink2)
            }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, lo: Double, hi: Double, span: Double) {
        func x(_ t: Double) -> CGFloat { CGFloat(t / span) * size.width }
        func y(_ v: Double) -> CGFloat { 2 + CGFloat(1 - (v - lo) / (hi - lo)) * (size.height - 4) }
        var rules = Path()
        for yy in [y(lo), y(hi)] {
            rules.move(to: CGPoint(x: 0, y: yy))
            rules.addLine(to: CGPoint(x: size.width, y: yy))
        }
        if zeroLine && lo < 0 && hi > 0 {
            rules.move(to: CGPoint(x: 0, y: y(0)))
            rules.addLine(to: CGPoint(x: size.width, y: y(0)))
        }
        ctx.stroke(rules, with: .color(c.line), lineWidth: 1)
        var ticks = Path()
        for t in marks {
            ticks.move(to: CGPoint(x: x(t), y: 0))
            ticks.addLine(to: CGPoint(x: x(t), y: size.height))
        }
        ctx.stroke(ticks, with: .color(c.mark.opacity(0.7)), lineWidth: 1.5)

        // About two points per pixel: a minute of raw readings is 6000.
        let stride = Swift.max(1, points.count / Swift.max(1, Int(size.width) * 2))
        var path = Path()
        var previous: CGPoint?
        for i in Swift.stride(from: 0, to: points.count, by: stride) {
            let p = CGPoint(x: x(points[i].0), y: y(points[i].1))
            if let previous {
                if step { path.addLine(to: CGPoint(x: p.x, y: previous.y)) }
                path.addLine(to: p)
            } else {
                path.move(to: p)
            }
            previous = p
        }
        ctx.stroke(path, with: .color(c.ink), style: StrokeStyle(lineWidth: 1.25, lineJoin: .round))
    }
}

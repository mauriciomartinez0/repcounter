import SwiftUI

struct SessionRow: View {
    let session: WorkoutSession
    @Environment(\.colors) private var c

    var body: some View {
        Pressable(action: { Router.shared.push(.summary(session, justFinished: false)) }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.text(19, .medium))
                        .foregroundStyle(c.ink)
                        .lineLimit(1)
                    Text("\(formatDay(session.startedAt)) · \(wholeMinutes(session.duration)) min")
                        .font(.text(14))
                        .foregroundStyle(c.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                NumberWithUnit(value: formatNumber(session.volumeKg), unit: "kg", size: 28, unitSize: 13)
            }
            .frame(height: 72)
            .bottomRule(c.line)
        }
    }
}

struct HistoryTab: View {
    private static let visibleSessions = 4
    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c
    @State private var exerciseId: String?

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(title: "Historial")
            let sessions = repo.sessions
            if sessions.isEmpty {
                Text("Aquí aparecerán tus sesiones cuando termines la primera.")
                    .font(.text(17))
                    .foregroundStyle(c.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(kGutter)
            } else {
                let withVelocity = repo.exercisesWithVelocity()
                let selected = withVelocity.first { $0.id == exerciseId } ?? withVelocity.first
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            AppLabel("Sesiones")
                            ForEach(sessions.prefix(Self.visibleSessions)) { SessionRow(session: $0) }
                            if sessions.count > Self.visibleSessions {
                                LinkRow(label: "Ver todas las sesiones (\(sessions.count))") {
                                    Router.shared.push(.allSessions)
                                }
                            }
                        }
                        .padding(.horizontal, kGutter)
                        if let selected {
                            AppLabel("Velocidad media por ejercicio")
                                .padding(EdgeInsets(top: 32, leading: kGutter, bottom: 12, trailing: kGutter))
                            ChipRow {
                                ForEach(withVelocity) { e in
                                    FillChip(label: e.name, selected: e.id == selected.id) { exerciseId = e.id }
                                }
                            }
                            VelocityPanel(exercise: selected)
                                .padding(EdgeInsets(top: 20, leading: kGutter, bottom: 0, trailing: kGutter))
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }
}

private struct VelocityPanel: View {
    let exercise: Exercise
    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c

    var body: some View {
        var points: [ChartPoint] = []
        for (session, sets) in repo.historyFor(exercise.id) {
            let v = sets.compactMap(\.meanVelocity)
            if v.isEmpty { continue }
            points.append(ChartPoint(date: session.startedAt, value: v.reduce(0, +) / Double(v.count)))
        }
        // The chart shows the last twelve sessions.
        let recent = points.count > 12 ? Array(points.suffix(12)) : points
        let latest = recent.last!.value
        let change = recent.count > 1 ? latest - recent[recent.count - 2].value : nil

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(formatVelocity(latest)).font(.number(48)).foregroundStyle(c.ink)
                Text("m/s · última sesión").font(.text(15)).foregroundStyle(c.ink2)
                Spacer(minLength: 0)
                if let change {
                    Text(formatSigned(change, decimals: 2)).font(.text(15, .semibold)).foregroundStyle(c.ink)
                }
            }
            Spacer().frame(height: 12)
            LineChart(points: recent, format: formatVelocity, height: 120)
            Spacer().frame(height: 8)
            Rule()
            LinkRow(label: "Ver todo el progreso") { Router.shared.push(.progress(exercise)) }
        }
    }
}

private struct LinkRow: View {
    let label: String
    let onTap: () -> Void
    @Environment(\.colors) private var c

    var body: some View {
        Pressable(action: onTap) {
            HStack {
                Text(label)
                    .font(.text(16, .semibold))
                    .foregroundStyle(c.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                AppIcon(.forward, color: c.ink)
            }
            .frame(height: 56)
            .bottomRule(c.line)
        }
    }
}

struct AllSessionsScreen: View {
    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader()
            Text("Sesiones")
                .font(.text(36, .medium))
                .foregroundStyle(c.ink)
                .padding(EdgeInsets(top: 8, leading: kGutter, bottom: 16, trailing: kGutter))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(repo.sessions) { SessionRow(session: $0) }
                }
                .padding(.horizontal, kGutter)
            }
        }
    }
}

/// One way of reading a session's sets of an exercise.
enum ProgressMetric: CaseIterable {
    case weight, reps, volume, oneRepMax, velocity, range

    var label: String {
        switch self {
        case .weight: "Peso"
        case .reps: "Repeticiones"
        case .volume: "Volumen"
        case .oneRepMax: "1RM estimado"
        case .velocity: "Velocidad"
        case .range: "Rango"
        }
    }

    var unit: String {
        switch self {
        case .weight, .volume, .oneRepMax: "kg"
        case .reps: "reps"
        case .velocity: "m/s"
        case .range: "°"
        }
    }

    var caption: String {
        switch self {
        case .weight: "Peso máximo por sesión"
        case .reps: "Repeticiones totales por sesión"
        case .volume: "Volumen por sesión"
        case .oneRepMax: "1RM estimado por sesión"
        case .velocity: "Velocidad media por sesión"
        case .range: "Rango de movimiento máximo por sesión"
        }
    }

    var step: Bool { self == .weight }

    func valueOf(_ sets: [SetRecord]) -> Double? {
        switch self {
        case .weight:
            return sets.compactMap(\.weightKg).max()
        case .reps:
            return Double(sets.reduce(0) { $0 + $1.reps })
        case .volume:
            let v = sets.reduce(0) { $0 + $1.volumeKg }
            return v == 0 ? nil : v
        case .oneRepMax:
            // Epley: weight × (1 + reps / 30).
            return sets.compactMap { s in s.weightKg.map { $0 * (1 + Double(s.reps) / 30) } }.max()
        case .velocity:
            let v = sets.compactMap(\.meanVelocity)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        case .range:
            return sets.compactMap(\.rangeDegrees).max()
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .velocity: formatVelocity(v)
        case .weight, .oneRepMax: formatNumber(v, decimals: 1)
        default: formatNumber(v)
        }
    }
}

enum ProgressRange: CaseIterable {
    case weeks4, weeks12, all

    var label: String {
        switch self {
        case .weeks4: "4 semanas"
        case .weeks12: "12 semanas"
        case .all: "Todo"
        }
    }

    var days: Int? {
        switch self {
        case .weeks4: 28
        case .weeks12: 84
        case .all: nil
        }
    }
}

struct ProgressScreen: View {
    let exercise: Exercise
    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c
    @State private var metric: ProgressMetric = .weight
    @State private var range: ProgressRange = .weeks12
    @State private var didSetup = false

    private func stat(_ label: String, _ value: String?, _ footnote: String) -> some View {
        StatCell(label: label, value: {
            NumberWithUnit(value: value ?? "—", unit: value == nil ? nil : metric.unit, size: 28, unitSize: 13)
        }, footnote: footnote)
        .padding(.vertical, 20)
    }

    var body: some View {
        let now = Date()
        var points: [ChartPoint] = []
        for (session, sets) in repo.historyFor(exercise.id) {
            if let days = range.days, Int(now.timeIntervalSince(session.startedAt) / 86400) > days {
                continue
            }
            if let v = metric.valueOf(sets) { points.append(ChartPoint(date: session.startedAt, value: v)) }
        }
        let latest = points.last
        let best = points.reduce(nil as ChartPoint?) { a, b in a == nil || b.value >= a!.value ? b : a }
        let average = points.isEmpty ? nil : points.map(\.value).reduce(0, +) / Double(points.count)
        let change = points.count < 2 ? nil : points.last!.value - points.first!.value

        return VStack(spacing: 0) {
            BackHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(exercise.name)
                        .font(.text(36, .medium))
                        .foregroundStyle(c.ink)
                    Spacer().frame(height: 6)
                    Text("Progreso").font(.text(16)).foregroundStyle(c.ink2)
                    Spacer().frame(height: 20)
                    FlowLayout(spacing: 8, runSpacing: 8) {
                        ForEach(ProgressMetric.allCases, id: \.self) { m in
                            FillChip(label: m.label, selected: m == metric) { metric = m }
                        }
                    }
                    Spacer().frame(height: 24)
                    NumberWithUnit(value: latest.map { metric.format($0.value) } ?? "—",
                                   unit: latest == nil ? nil : metric.unit, size: 64, unitSize: 18)
                    Spacer().frame(height: 6)
                    Text(latest == nil
                        ? "\(metric.caption) · sin datos en este periodo"
                        : "\(metric.caption) · última sesión, \(formatShortDate(latest!.date))")
                        .font(.text(14))
                        .foregroundStyle(c.ink2)
                    Spacer().frame(height: 20)
                    HStack(spacing: 24) {
                        ForEach(ProgressRange.allCases, id: \.self) { r in
                            let on = r == range
                            Pressable(action: { range = r }) {
                                Text(r.label)
                                    .font(.text(15, on ? .semibold : .medium))
                                    .foregroundStyle(on ? c.ink : c.ink2)
                                    .frame(height: 44)
                                    .overlay(alignment: .bottom) {
                                        Rectangle().fill(on ? c.mark : .clear).frame(height: 2)
                                    }
                            }
                        }
                    }
                    Spacer().frame(height: 20)
                    LineChart(points: points, format: metric.format, step: metric.step)
                    Spacer().frame(height: 16)
                    HStack(alignment: .top, spacing: 0) {
                        stat("Mejor marca", best.map { metric.format($0.value) },
                             best.map { formatShortDate($0.date) } ?? "")
                        Rectangle().fill(c.line).frame(width: 1)
                        Spacer().frame(width: 14)
                        stat("Promedio", average.map(metric.format), "por sesión")
                        Rectangle().fill(c.line).frame(width: 1)
                        Spacer().frame(width: 14)
                        stat("Cambio", change.map { ($0 > 0 ? "+" : "") + metric.format($0) },
                             range == .all ? "desde el inicio" : "en \(range.label)")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .topRule(c.line)
                    .bottomRule(c.line)
                }
                .padding(EdgeInsets(top: 8, leading: kGutter, bottom: 32, trailing: kGutter))
            }
        }
        .onAppear {
            guard !didSetup else { return }
            didSetup = true
            // Body-weight exercises have no load; start on something they have.
            let hasWeight = repo.historyFor(exercise.id).contains { ProgressMetric.weight.valueOf($0.1) != nil }
            if !hasWeight { metric = .reps }
        }
    }
}

import SwiftUI

struct SessionRow: View {
    let session: WorkoutSession
    @Environment(\.colors) private var c

    var body: some View {
        Pressable(action: { Router.shared.push(.summary(session, justFinished: false)) },
                  label: "\(session.title), \(formatDay(session.startedAt)). Abrir para ver y editar.") {
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
                AppIcon(.forward, size: 20, color: c.ink3)
            }
            .frame(height: 72)
            .bottomRule(c.line)
        }
    }
}

/// Every session, newest first, and a way to add one the sensor missed.
struct HistoryTab: View {
    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(title: "Historial")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if repo.sessions.isEmpty {
                        Text("Aquí aparecerán tus sesiones cuando termines la primera.")
                            .font(.text(17))
                            .foregroundStyle(c.ink2)
                            .padding(.bottom, 8)
                    } else {
                        Text("Toca una sesión para verla y editarla.")
                            .font(.text(14))
                            .foregroundStyle(c.ink2)
                            .padding(.bottom, 4)
                    }
                    AddSessionRow()
                    ForEach(repo.sessions) { SessionRow(session: $0) }
                }
                .padding(EdgeInsets(top: 0, leading: kGutter, bottom: 24, trailing: kGutter))
            }
        }
    }
}

/// Tab "Progreso": each routine's progress, then the weight of each
/// exercise with its small chart.
struct ProgressTab: View {
    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c

    var body: some View {
        let routines = repo.trainedRoutines()
        let withWeight = repo.exercisesWithWeight()
        VStack(spacing: 0) {
            TabHeader(title: "Progreso")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if routines.isEmpty && withWeight.isEmpty {
                        Text("Aquí verás tu progreso cuando termines tu primera sesión.")
                            .font(.text(17))
                            .foregroundStyle(c.ink2)
                    }
                    if !routines.isEmpty {
                        AppLabel("Por rutina")
                        ForEach(routines, id: \.id) { r in
                            LinkRow(label: r.name) { Router.shared.push(.routineProgress(r.id)) }
                        }
                        Spacer().frame(height: 32)
                    }
                    if !withWeight.isEmpty {
                        AppLabel("Peso por ejercicio")
                        Text("Toca un ejercicio para ver su gráfica completa.")
                            .font(.text(14))
                            .foregroundStyle(c.ink2)
                            .padding(.top, 4)
                        ForEach(withWeight) { WeightRow(exercise: $0) }
                    }
                }
                .padding(EdgeInsets(top: 0, leading: kGutter, bottom: 24, trailing: kGutter))
            }
        }
    }
}

/// One exercise in "Peso por ejercicio": its heaviest weight last session,
/// the change from the session before, and a small chart of the last twelve.
private struct WeightRow: View {
    let exercise: Exercise
    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c

    var body: some View {
        var values: [Double] = []
        for (_, sets) in repo.historyFor(exercise.id) {
            if let kg = ProgressMetric.weight.valueOf(sets) { values.append(kg) }
        }
        let recent = Array(values.suffix(12))
        let latest = recent.last ?? 0
        let change = recent.count > 1 ? latest - recent[recent.count - 2] : nil
        let changeText = change.map { $0 == 0 ? "Igual que la sesión anterior" : formatSigned($0, decimals: 2) + " kg" }
            ?? "Primera sesión"

        return Pressable(action: { Router.shared.push(.progress(exercise)) },
                         label: "\(exercise.name), \(formatKg(latest)) kg. \(changeText). Abrir su progreso.") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.text(19, .medium))
                        .foregroundStyle(c.ink)
                        .lineLimit(1)
                    Text(changeText)
                        .font(.text(14))
                        .foregroundStyle(c.ink2)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Sparkline(values: recent)
                    .frame(width: 56, height: 28)
                NumberWithUnit(value: formatKg(latest), unit: "kg", size: 28, unitSize: 13)
                AppIcon(.forward, size: 20, color: c.ink3)
            }
            .frame(height: 72)
            .bottomRule(c.line)
        }
    }
}

/// Opens "Agregar sesión", for a workout the sensor did not record.
private struct AddSessionRow: View {
    @Environment(\.colors) private var c

    var body: some View {
        Pressable(action: { Router.shared.push(.manualSession) },
                  label: "Agregar una sesión sin el sensor") {
            HStack(spacing: 10) {
                AppIcon(.plus, size: 20, color: c.ink)
                Text("Agregar sesión sin sensor")
                    .font(.text(16, .semibold))
                    .foregroundStyle(c.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 56)
            .bottomRule(c.line)
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
        case .weight: formatKg(v)
        case .oneRepMax: formatNumber(v, decimals: 1)
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

/// One way of reading a whole session of a routine.
enum RoutineMetric: CaseIterable {
    case volume, reps, sets, duration, velocity

    var label: String {
        switch self {
        case .volume: "Volumen"
        case .reps: "Repeticiones"
        case .sets: "Series"
        case .duration: "Duración"
        case .velocity: "Velocidad"
        }
    }

    var unit: String {
        switch self {
        case .volume: "kg"
        case .reps: "reps"
        case .sets: "series"
        case .duration: "min"
        case .velocity: "m/s"
        }
    }

    var caption: String {
        switch self {
        case .volume: "Volumen total por sesión"
        case .reps: "Repeticiones totales por sesión"
        case .sets: "Series por sesión"
        case .duration: "Duración por sesión"
        case .velocity: "Velocidad media por sesión"
        }
    }

    /// The best mark is the largest value; for duration that is just the
    /// longest session, not a better one.
    var bestLabel: String { self == .duration ? "Más larga" : "Mejor marca" }

    func valueOf(_ session: WorkoutSession) -> Double? {
        switch self {
        case .volume:
            let v = session.volumeKg
            return v == 0 ? nil : v
        case .reps:
            return Double(session.sets.reduce(0) { $0 + $1.reps })
        case .sets:
            return Double(session.sets.count)
        case .duration:
            return (session.duration / 60).rounded()
        case .velocity:
            let v = session.sets.compactMap(\.meanVelocity)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
    }

    func format(_ v: Double) -> String {
        self == .velocity ? formatVelocity(v) : formatNumber(v)
    }
}

/// How a routine's sessions add up over time: one chart per metric, the best
/// mark, the average and the change, then its exercises and sessions.
struct RoutineProgressScreen: View {
    private static let visibleSessions = 5
    let routineId: String
    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c
    @State private var metric: RoutineMetric = .volume
    @State private var range: ProgressRange = .weeks12
    @State private var didSetup = false

    private func stat(_ label: String, _ value: String?, _ footnote: String) -> some View {
        StatCell(label: label, value: {
            NumberWithUnit(value: value ?? "—", unit: value == nil ? nil : metric.unit, size: 28, unitSize: 13)
        }, footnote: footnote)
        .padding(.vertical, 20)
    }

    var body: some View {
        let all = repo.sessionsOf(routine: routineId)
        let name = repo.routine(routineId)?.name ?? all.last?.title ?? "Rutina"
        let now = Date()
        var points: [ChartPoint] = []
        for session in all {
            if let days = range.days, Int(now.timeIntervalSince(session.startedAt) / 86400) > days {
                continue
            }
            if let v = metric.valueOf(session) { points.append(ChartPoint(date: session.startedAt, value: v)) }
        }
        let latest = points.last
        let best = points.reduce(nil as ChartPoint?) { a, b in a == nil || b.value >= a!.value ? b : a }
        let average = points.isEmpty ? nil : points.map(\.value).reduce(0, +) / Double(points.count)
        let change = points.count < 2 ? nil : points.last!.value - points.first!.value

        // Exercises done in these sessions, in the routine's order, then any
        // others (alternatives, exercises since removed from the routine).
        var exerciseIds = repo.routine(routineId)?.items.map(\.exerciseId) ?? []
        for session in all.reversed() {
            for id in session.exerciseIds where !exerciseIds.contains(id) { exerciseIds.append(id) }
        }
        let done = Set(all.flatMap(\.exerciseIds))
        let exercises = exerciseIds.filter(done.contains).compactMap(repo.exercise)

        return VStack(spacing: 0) {
            BackHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(.text(36, .medium))
                        .foregroundStyle(c.ink)
                    Spacer().frame(height: 6)
                    Text("Progreso · \(all.count) \(plural(all.count, "sesión", "sesiones"))")
                        .font(.text(16))
                        .foregroundStyle(c.ink2)
                    if all.isEmpty {
                        Text("Aquí verás tu progreso cuando termines esta rutina por primera vez.")
                            .font(.text(17))
                            .foregroundStyle(c.ink2)
                            .padding(.top, 24)
                    } else {
                        Spacer().frame(height: 20)
                        FlowLayout(spacing: 8, runSpacing: 8) {
                            ForEach(RoutineMetric.allCases, id: \.self) { m in
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
                        LineChart(points: points, format: metric.format)
                        Spacer().frame(height: 16)
                        HStack(alignment: .top, spacing: 0) {
                            stat(metric.bestLabel, best.map { metric.format($0.value) },
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

                        if !exercises.isEmpty {
                            AppLabel("Por ejercicio").padding(.top, 32)
                            ForEach(exercises) { e in
                                LinkRow(label: e.name) { Router.shared.push(.progress(e)) }
                            }
                        }

                        AppLabel("Sesiones").padding(.top, 32)
                        ForEach(all.reversed().prefix(Self.visibleSessions)) { SessionRow(session: $0) }
                    }
                }
                .padding(EdgeInsets(top: 8, leading: kGutter, bottom: 32, trailing: kGutter))
            }
        }
        .onAppear {
            guard !didSetup else { return }
            didSetup = true
            // Body-weight routines have no volume; start on something they have.
            if !all.contains(where: { RoutineMetric.volume.valueOf($0) != nil }) { metric = .reps }
        }
    }
}

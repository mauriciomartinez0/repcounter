// "Sesión completada". Also opened from Historial for past sessions.
//
// Right after a workout the sets can still be corrected: tapping an exercise
// opens its sets, so the last set (which has no rest screen after it) can be
// fixed too. Reps and weight can be changed and a set can be deleted, until
// "Listo" uploads the session; after that it is read only. A set can come up short of the plan (12, 10, 9…) and the sensor
// can also miss or double-count a rep; either way the history should hold
// what was really done.

import SwiftUI

struct SummaryScreen: View {
    let justFinished: Bool
    let route: Route
    @State private var session: WorkoutSession

    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c

    init(session: WorkoutSession, justFinished: Bool, route: Route) {
        _session = State(initialValue: session)
        self.justFinished = justFinished
        self.route = route
    }

    private func edit(_ exerciseId: String, _ name: String) {
        Task {
            await editExerciseSets(
                exerciseName: name,
                sets: session.sets.filter { $0.exerciseId == exerciseId }
            ) { corrected in
                // The exercise's sets take their places in order; deleted
                // ones leave their last places empty.
                var remaining = corrected.makeIterator()
                var updated = session
                updated.sets = session.sets.compactMap { s in
                    s.exerciseId == exerciseId ? remaining.next() : s
                }
                session = updated
                repo.saveSession(updated)
            }
        }
    }

    private func close() {
        if justFinished {
            if session.sets.isEmpty {
                // Every set was deleted: there is nothing to keep.
                repo.discardSession(session.id)
            } else {
                // Corrections are over: now it can go to the server.
                repo.commitSession(session.id)
            }
            Router.shared.blocked.remove(route)
            Router.shared.popToFirst()
        } else {
            Router.shared.pop()
        }
    }

    var body: some View {
        let previous = repo.previousSession(session)
        let minutes = wholeMinutes(session.duration)
        let exerciseIds = session.exerciseIds
        let countText = session.plannedExercises > 0
            ? "\(exerciseIds.count) de \(session.plannedExercises) ejercicios"
            : "\(exerciseIds.count) \(plural(exerciseIds.count, "ejercicio", "ejercicios"))"

        VStack(spacing: 0) {
            if !justFinished { BackHeader() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if justFinished {
                        AppLabel("Sesión completada")
                        Spacer().frame(height: 4)
                    }
                    Text(session.title)
                        .font(.text(36, .medium))
                        .foregroundStyle(c.ink)
                    Spacer().frame(height: 6)
                    Text("\(formatDay(session.startedAt)) · \(countText)")
                        .font(.text(16))
                        .foregroundStyle(c.ink2)
                    Spacer().frame(height: 28)
                    StatPair {
                        StatCell(
                            label: "Volumen total",
                            value: {
                                NumberWithUnit(value: formatNumber(session.volumeKg), unit: "kg",
                                               size: 64, unitSize: 18)
                            },
                            footnote: previous.map { "\(formatSigned(session.volumeKg - $0.volumeKg)) kg" },
                            footnoteColor: session.volumeKg >= (previous?.volumeKg ?? 0) ? c.mark : c.ink
                        )
                    } right: {
                        StatCell(
                            label: "Duración",
                            value: { NumberWithUnit(value: "\(minutes)", unit: "min", size: 64, unitSize: 18) },
                            footnote: previous.map {
                                "\(formatSigned(Double(minutes - wholeMinutes($0.duration)))) min"
                            },
                            footnoteColor: c.ink
                        )
                    }
                    if let previous {
                        Spacer().frame(height: 16)
                        Text("Comparado con la última vez: \(formatDayLower(previous.startedAt)).")
                            .font(.text(14))
                            .foregroundStyle(c.ink2)
                    }
                    Spacer().frame(height: 32)
                    AppLabel("Ejercicios")
                    Spacer().frame(height: 4)
                    ForEach(Array(exerciseIds.enumerated()), id: \.element) { i, id in
                        let name = repo.exercise(id)?.name ?? id
                        SummaryExerciseRow(
                            name: name,
                            sets: session.sets.filter { $0.exerciseId == id },
                            last: i == exerciseIds.count - 1,
                            onTap: justFinished ? { edit(id, name) } : nil
                        )
                    }
                    if justFinished {
                        Spacer().frame(height: 16)
                        Text(session.sets.isEmpty
                            ? "Eliminaste todas las series: al tocar Listo no se guarda el entrenamiento."
                            : "Toca un ejercicio para corregir repeticiones y peso, o eliminar series.")
                            .font(.text(14))
                            .foregroundStyle(c.ink3)
                    }
                }
                .padding(EdgeInsets(top: justFinished ? 40 : 8, leading: kGutter, bottom: 24, trailing: kGutter))
            }
            if justFinished {
                PrimaryButton("Listo", action: close)
                    .padding(EdgeInsets(top: 8, leading: kGutter, bottom: 32, trailing: kGutter))
            }
        }
        .blocksBack(route, justFinished)
    }
}

/// How the sets of one exercise went.
///
/// When every set matched (same reps, same weight, target met) it reads like
/// the plan: "4 × 8 · 60 kg". Otherwise each set is listed so a drop-off is
/// visible: "60 kg: 12, 10, 9, 8", or "60 kg: 12, 10 · 55 kg: 9, 8" when the
/// weight changed between sets.
struct SetsDescription {
    let compact: Bool
    let text: String
    /// The target when every set had the same one.
    let target: Int?
    let missedTarget: Bool

    init(_ sets: [SetRecord]) {
        let uniform = sets.allSatisfy {
            $0.reps == sets[0].reps && $0.weightKg == sets[0].weightKg
                && ($0.targetReps == nil || $0.reps >= $0.targetReps!)
        }
        compact = uniform
        text = uniform ? formatSetsSummary(sets.count, sets[0].reps, sets[0].weightKg) : Self.perSet(sets)
        let first = sets[0].targetReps
        target = sets.allSatisfy { $0.targetReps == first } ? first : nil
        missedTarget = sets.contains { $0.targetReps != nil && $0.reps < $0.targetReps! }
    }

    private static func perSet(_ sets: [SetRecord]) -> String {
        // Consecutive sets with the same weight share one label.
        var groups: [(Double?, [Int])] = []
        for s in sets {
            if let last = groups.last, last.0 == s.weightKg {
                groups[groups.count - 1].1.append(s.reps)
            } else {
                groups.append((s.weightKg, [s.reps]))
            }
        }
        return groups.map { kg, reps in
            "\(kg == nil ? "corporal" : "\(formatKg(kg!)) kg"): \(reps.map(String.init).joined(separator: ", "))"
        }.joined(separator: " · ")
    }
}

private struct SummaryExerciseRow: View {
    let name: String
    let sets: [SetRecord]
    let last: Bool
    let onTap: (() -> Void)?
    @Environment(\.colors) private var c

    var body: some View {
        let d = SetsDescription(sets)
        let title = Text(name).font(.text(17, .medium)).foregroundStyle(c.ink).lineLimit(1)
        let row = Group {
            if d.compact {
                HStack(spacing: 12) {
                    title.frame(maxWidth: .infinity, alignment: .leading)
                    Text(d.text).font(.text(15)).foregroundStyle(c.ink2)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        title.frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(sets.count) \(plural(sets.count, "serie", "series"))")
                            .font(.text(15))
                            .foregroundStyle(c.ink2)
                    }
                    (Text(d.text).foregroundColor(c.ink2)
                        + Text(d.missedTarget && d.target != nil ? " · objetivo \(d.target!)" : "")
                        .foregroundColor(c.ink3))
                        .font(.text(15))
                }
                .padding(.vertical, 10)
            }
        }
        .frame(minHeight: 52)
        .bottomRule(c.line, visible: !last)

        if let onTap {
            Pressable(action: onTap, label: "Corregir \(name)") { row }
        } else {
            row
        }
    }
}

// MARK: - Corrections

/// Reps of one set. Returns the corrected count, or nil if dismissed.
@MainActor
func askReps(title: String, initial: Int, target: Int?) async -> Int? {
    await OverlayCenter.shared.sheet { finish in
        AnyView(RepsSheet(title: title, initial: initial, target: target, finish: finish))
    }
}

private struct RepsSheet: View {
    let title: String
    let initial: Int
    let target: Int?
    let finish: (Int?) -> Void
    @Environment(\.colors) private var c
    @State private var value: Int?

    var body: some View {
        let current = value ?? initial
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.text(22, .semibold)).foregroundStyle(c.ink)
            Spacer().frame(height: 4)
            Text(target == nil
                ? "Repeticiones que hiciste en esta serie."
                : "Repeticiones que hiciste. El objetivo era \(target!).")
                .font(.text(16))
                .foregroundStyle(c.ink2)
            Spacer().frame(height: 24)
            CountStepper(value: current) { value = $0 }
                .frame(maxWidth: .infinity)
            Spacer().frame(height: 28)
            PrimaryButton("Listo") { finish(current) }
        }
    }
}

/// All the sets of one exercise in a session, each with its reps and weight,
/// and a way to delete it. `onChanged` receives the full, corrected list
/// every time something changes; a deleted set is simply not in it.
@MainActor
func editExerciseSets(exerciseName: String, sets: [SetRecord], onChanged: @escaping ([SetRecord]) -> Void) async {
    let _: Bool? = await OverlayCenter.shared.sheet { finish in
        AnyView(SetsSheet(exerciseName: exerciseName, initial: sets, onChanged: onChanged) { finish(true) })
    }
}

private struct SetsSheet: View {
    let exerciseName: String
    let initial: [SetRecord]
    let onChanged: ([SetRecord]) -> Void
    let done: () -> Void
    @Environment(\.colors) private var c
    @State private var current: [SetRecord]?

    var body: some View {
        let sets = current ?? initial
        VStack(alignment: .leading, spacing: 0) {
            Text(exerciseName).font(.text(22, .semibold)).foregroundStyle(c.ink)
            Spacer().frame(height: 4)
            Text("Corrige las repeticiones y el peso de cada serie, o elimina las que sobran.")
                .font(.text(16))
                .foregroundStyle(c.ink2)
            Spacer().frame(height: 12)
            // Short lists sit in the sheet as they are; long ones scroll.
            if sets.count > 3 {
                ScrollView { rows(sets) }.frame(height: 400)
            } else {
                rows(sets)
            }
            Spacer().frame(height: 24)
            PrimaryButton("Listo", action: done)
        }
    }

    private func update(_ updated: [SetRecord]) {
        current = updated
        onChanged(updated)
    }

    private func delete(at i: Int, in sets: [SetRecord]) {
        let s = sets[i]
        Task {
            let weight = s.weightKg.map { "\(formatKg($0)) kg" } ?? "peso corporal"
            let sure = await confirm(
                title: "¿Eliminar la serie \(s.setNumber)?",
                message: "Se quita del entrenamiento: \(s.reps) \(plural(s.reps, "repetición", "repeticiones")) "
                    + "con \(weight).",
                confirmLabel: "Eliminar"
            )
            guard sure else { return }
            var updated = sets
            updated.remove(at: i)
            // The sets after it, in the same run, move up one number. A
            // routine can repeat the exercise; the next run keeps its own.
            for j in i..<updated.count {
                guard updated[j].setNumber == s.setNumber + (j - i) + 1 else { break }
                updated[j].setNumber -= 1
            }
            update(updated)
            if updated.isEmpty { done() }
        }
    }

    private func rows(_ sets: [SetRecord]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(sets.enumerated()), id: \.offset) { i, s in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Serie \(s.setNumber)").font(.text(17, .medium)).foregroundStyle(c.ink)
                        if let target = s.targetReps {
                            Text("objetivo \(target)").font(.text(14)).foregroundStyle(c.ink2)
                        }
                        Spacer(minLength: 8)
                        TextAction(label: "Eliminar", size: 14, underline: true) { delete(at: i, in: sets) }
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            AppLabel("Repeticiones")
                            CountStepper(value: s.reps, compact: true) { v in
                                var updated = sets
                                updated[i].reps = v
                                update(updated)
                            }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .leading, spacing: 4) {
                            AppLabel("Peso")
                            WeightStepper(valueKg: s.weightKg, large: false, compact: true) { kg in
                                var updated = sets
                                updated[i].weightKg = kg
                                update(updated)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
                .bottomRule(c.line)
            }
        }
    }
}

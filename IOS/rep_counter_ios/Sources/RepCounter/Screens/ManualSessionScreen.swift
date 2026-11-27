// "Agregar sesión": a workout entered by hand, for when the sensor could not
// be used (it ran out of battery, was forgotten, would not connect). It is
// saved and synced like any other session, just without the sensor's
// readings (velocity, range, movement).

import SwiftUI

struct ManualSessionScreen: View {
    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c

    /// Nil is a free workout.
    @State private var routineId: String?
    @State private var startedAt = Self.defaultStart
    @State private var minutes = 60
    @State private var sets: [SetRecord] = []

    /// An hour ago, on the hour: most sessions are added right after.
    private static var defaultStart: Date {
        let anHourAgo = Date().addingTimeInterval(-3600)
        return Calendar.current.dateInterval(of: .hour, for: anHourAgo)?.start ?? anHourAgo
    }

    /// Exercise ids in the order they come in `sets`.
    private static func exerciseIds(_ sets: [SetRecord]) -> [String] {
        var ids: [String] = []
        for s in sets where !ids.contains(s.exerciseId) { ids.append(s.exerciseId) }
        return ids
    }

    private var routine: Routine? { routineId.flatMap(repo.routine) }

    /// The routine's plan as done sets: every set at its planned reps and
    /// weight, to adjust what changed.
    private func planSets(_ routine: Routine) -> [SetRecord] {
        routine.items.flatMap { item in
            (1...max(1, item.sets)).map { n in
                SetRecord(exerciseId: item.exerciseId, setNumber: min(100, n), reps: item.reps,
                          targetReps: item.reps, weightKg: item.weightKg, meanVelocity: nil,
                          rangeDegrees: nil, completedAt: startedAt)
            }
        }
    }

    private func choose(_ id: String?) {
        guard id != routineId else { return }
        Task {
            if !sets.isEmpty {
                let sure = await confirm(
                    title: "¿Cambiar de rutina?",
                    message: "Se reemplazan los ejercicios y series que ya pusiste.",
                    confirmLabel: "Cambiar"
                )
                guard sure else { return }
            }
            routineId = id
            if let r = id.flatMap(repo.routine) {
                sets = planSets(r)
                minutes = r.estimatedMinutes
            } else {
                sets = []
            }
        }
    }

    private func edit(_ exerciseId: String, _ name: String, sets current: [SetRecord]? = nil) {
        Task {
            await editExerciseSets(
                exerciseName: name,
                sets: current ?? sets.filter { $0.exerciseId == exerciseId }
            ) { corrected in
                sets = replacingSets(of: exerciseId, in: sets, with: corrected)
            }
        }
    }

    /// Starts with one set like the last time the exercise was done.
    private func addExercise() {
        Router.shared.pickExercises(title: "Agregar ejercicio", single: true) { picked in
            guard let exercise = picked.first else { return }
            if sets.contains(where: { $0.exerciseId == exercise.id }) {
                edit(exercise.id, exercise.name)
                return
            }
            let before = repo.historyFor(exercise.id).last?.1.last
            let first = SetRecord(
                exerciseId: exercise.id, setNumber: 1, reps: before?.reps ?? 10, targetReps: nil,
                weightKg: before?.weightKg, meanVelocity: nil, rangeDegrees: nil, completedAt: startedAt
            )
            sets = replacingSets(of: exercise.id, in: sets, with: [first])
            edit(exercise.id, exercise.name, sets: [first])
        }
    }

    private func leave() {
        Task {
            if !sets.isEmpty {
                let sure = await confirm(
                    title: "¿Descartar esta sesión?",
                    message: "No se guarda nada de lo que pusiste.",
                    confirmLabel: "Descartar"
                )
                guard sure else { return }
            }
            Router.shared.pop()
        }
    }

    private func save() {
        // The API rejects sessions that start in the future.
        let start = min(startedAt, Date())
        let end = start.addingTimeInterval(Double(minutes) * 60)
        // Spread the sets over the session, in order, so they keep it when
        // sorted by time.
        let step = sets.count > 1 ? end.timeIntervalSince(start) / Double(sets.count) : 0
        let timed = sets.enumerated().map { i, s in
            SetRecord(exerciseId: s.exerciseId, setNumber: s.setNumber, reps: s.reps,
                      targetReps: s.targetReps, weightKg: s.weightKg, meanVelocity: nil, rangeDegrees: nil,
                      completedAt: start.addingTimeInterval(step * Double(i + 1)))
        }
        let session = WorkoutSession(
            id: newId(), routineId: routine?.id, title: routine?.name ?? "Entrenamiento libre",
            startedAt: start, endedAt: end, sets: timed, plannedExercises: routine?.items.count ?? 0
        )
        repo.saveSession(session)
        repo.commitSession(session.id)
        Router.shared.pop()
        showMessage("Sesión agregada.")
    }

    var body: some View {
        let exerciseIds = Self.exerciseIds(sets)
        VStack(spacing: 0) {
            BackHeader(onBack: leave)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Agregar sesión")
                        .font(.text(36, .medium))
                        .foregroundStyle(c.ink)
                    Spacer().frame(height: 6)
                    Text("Para un entrenamiento que no registró el sensor.")
                        .font(.text(16))
                        .foregroundStyle(c.ink2)

                    AppLabel("Rutina").padding(.top, 28)
                    Spacer().frame(height: 12)
                    FlowLayout(spacing: 8, runSpacing: 8) {
                        FillChip(label: "Libre", selected: routineId == nil) { choose(nil) }
                        ForEach(repo.routines) { r in
                            FillChip(label: r.name, selected: r.id == routineId) { choose(r.id) }
                        }
                    }

                    AppLabel("Cuándo").padding(.top, 28)
                    SessionTimeFields(start: $startedAt, minutes: minutes) { minutes = $0 }

                    AppLabel("Ejercicios").padding(.top, 28)
                    Spacer().frame(height: 4)
                    Text(sets.isEmpty
                        ? "Agrega los ejercicios que hiciste, o elige una rutina para empezar con su plan."
                        : "Toca un ejercicio para cambiar repeticiones y peso, agregar o eliminar series.")
                        .font(.text(14))
                        .foregroundStyle(c.ink2)
                    Spacer().frame(height: 4)
                    ForEach(exerciseIds, id: \.self) { id in
                        let name = repo.exercise(id)?.name ?? id
                        SummaryExerciseRow(name: name, sets: sets.filter { $0.exerciseId == id },
                                           last: false, onTap: { edit(id, name) })
                    }
                    Pressable(action: addExercise, label: "Agregar un ejercicio") {
                        HStack(spacing: 10) {
                            AppIcon(.plus, size: 20, color: c.ink)
                            Text("Agregar ejercicio")
                                .font(.text(16, .semibold))
                                .foregroundStyle(c.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 52)
                    }
                }
                .padding(EdgeInsets(top: 8, leading: kGutter, bottom: 24, trailing: kGutter))
            }
            PrimaryButton("Guardar sesión", action: sets.isEmpty ? nil : save)
                .padding(EdgeInsets(top: 8, leading: kGutter, bottom: 32, trailing: kGutter))
        }
        // The swipe would drop what was entered; the back arrow asks first.
        .blocksBack(.manualSession, !sets.isEmpty)
    }
}

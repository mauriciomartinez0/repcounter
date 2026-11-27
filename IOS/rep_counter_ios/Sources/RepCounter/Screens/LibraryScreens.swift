// "Biblioteca de rutinas": ready-made programs (Data/RoutineLibrary.swift)
// to copy into the user's routines, whole or one day at a time. A copy is an
// ordinary routine: editing it does not touch the library.

import SwiftUI

struct RoutineLibraryScreen: View {
    @Environment(\.colors) private var c

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Biblioteca")
                        .font(.text(36, .medium))
                        .foregroundStyle(c.ink)
                    Spacer().frame(height: 6)
                    Text("Programas conocidos para copiar a tus rutinas. Después los puedes editar como quieras.")
                        .font(.text(16))
                        .foregroundStyle(c.ink2)
                    Spacer().frame(height: 12)
                    ForEach(routineLibrary) { program in
                        Pressable(action: { Router.shared.push(.libraryProgram(program.id)) },
                                  label: "\(program.name), \(program.level.rawValue), \(program.daysPerWeek)") {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(program.name)
                                        .font(.text(22, .medium))
                                        .foregroundStyle(c.ink)
                                        .lineLimit(1)
                                    Text("\(program.level.rawValue) · \(program.daysPerWeek) · "
                                        + "\(program.days.count) \(plural(program.days.count, "rutina", "rutinas"))")
                                        .font(.text(15))
                                        .foregroundStyle(c.ink2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                AppIcon(.forward, size: 20, color: c.ink3)
                            }
                            .frame(height: 88)
                            .bottomRule(c.line)
                        }
                    }
                }
                .padding(EdgeInsets(top: 8, leading: kGutter, bottom: 32, trailing: kGutter))
            }
        }
    }
}

struct LibraryProgramScreen: View {
    let programId: String
    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c

    private var program: RoutineProgram? { routineLibrary.first { $0.id == programId } }

    private func add(_ days: [ProgramDay], of program: RoutineProgram) {
        let known = { (id: String) in repo.exercise(id)?.active == true }
        for day in days {
            repo.saveRoutine(program.routine(day, known: known))
        }
        Router.shared.popToFirst()
        Router.shared.homeTab = 0
        showMessage(days.count == 1
            ? "Rutina agregada a tus rutinas."
            : "\(days.count) rutinas agregadas a tus rutinas.")
    }

    var body: some View {
        if let program {
            VStack(spacing: 0) {
                BackHeader()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(program.name)
                            .font(.text(36, .medium))
                            .foregroundStyle(c.ink)
                        Spacer().frame(height: 6)
                        Text("\(program.level.rawValue) · \(program.daysPerWeek)")
                            .font(.text(16))
                            .foregroundStyle(c.ink2)
                        Spacer().frame(height: 16)
                        Text(program.summary)
                            .font(.text(16))
                            .foregroundStyle(c.ink)
                        ForEach(program.days) { day in
                            DayBlock(program: program, day: day) { add([day], of: program) }
                        }
                    }
                    .padding(EdgeInsets(top: 8, leading: kGutter, bottom: 24, trailing: kGutter))
                }
                PrimaryButton(program.days.count == 1
                    ? "Agregar a mis rutinas"
                    : "Agregar las \(program.days.count) rutinas") { add(program.days, of: program) }
                    .padding(EdgeInsets(top: 8, leading: kGutter, bottom: 32, trailing: kGutter))
            }
        } else {
            Color.clear
        }
    }
}

/// One day of a program: its exercises and plan, and a button to copy only
/// that day.
private struct DayBlock: View {
    let program: RoutineProgram
    let day: ProgramDay
    let onAdd: () -> Void
    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c

    var body: some View {
        let routine = program.routine(day, known: { repo.exercise($0) != nil })
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.name).font(.text(22, .semibold)).foregroundStyle(c.ink)
                    Text(routineSubtitle(routine)).font(.text(14)).foregroundStyle(c.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if program.days.count > 1 {
                    SmallButton("Agregar solo esta", action: onAdd)
                }
            }
            .padding(.bottom, 8)
            ForEach(Array(routine.items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.exercise(item.exerciseId)?.name ?? item.exerciseId)
                        .font(.text(17, .medium))
                        .foregroundStyle(c.ink)
                        .lineLimit(1)
                    let alternatives = item.alternativeIds.compactMap { repo.exercise($0)?.name }
                    if !alternatives.isEmpty {
                        Text("o " + alternatives.joined(separator: ", "))
                            .font(.text(14))
                            .foregroundStyle(c.ink3)
                            .lineLimit(1)
                    }
                    Text("\(item.sets) × \(item.reps) · descanso \(formatClock(item.restSeconds))")
                        .font(.text(14))
                        .foregroundStyle(c.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .topRule(c.line)
            }
        }
        .padding(.top, 32)
    }
}

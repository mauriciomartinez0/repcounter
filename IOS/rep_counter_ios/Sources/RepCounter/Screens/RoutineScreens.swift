import SwiftUI

func routineSubtitle(_ routine: Routine) -> String {
    let n = routine.items.count
    return "\(n) \(plural(n, "ejercicio", "ejercicios")) · \(routine.estimatedMinutes) min"
}

/// "4 × 8 · 60 kg · descanso 2:00".
func routineItemLine(_ item: RoutineItem) -> String {
    "\(item.sets) × \(item.reps) · "
        + (item.weightKg == nil ? "peso corporal" : "\(formatKg(item.weightKg!)) kg")
        + " · descanso \(formatClock(item.restSeconds))"
}

struct RoutinesTab: View {
    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(title: "Rutinas")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Rule()
                    if repo.routines.isEmpty && repo.lastSyncedAt == nil && repo.syncStatus != .idle {
                        Text(repo.syncStatus == .syncing
                            ? "Cargando tus rutinas…"
                            : "No se pudieron cargar tus rutinas. Revisa tu internet; se reintenta solo.")
                            .font(.text(16))
                            .foregroundStyle(c.ink2)
                            .padding(.vertical, 24)
                    }
                    ForEach(repo.routines) { routine in
                        Pressable(action: { Router.shared.push(.routineDetail(routine.id)) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(routine.name)
                                    .font(.text(26, .medium))
                                    .foregroundStyle(c.ink)
                                    .lineLimit(1)
                                Text(routineSubtitle(routine))
                                    .font(.text(15))
                                    .foregroundStyle(c.ink2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 96)
                            .bottomRule(c.line)
                        }
                    }
                    Pressable(action: { Router.shared.push(.routineEditor(nil)) }) {
                        HStack(spacing: 12) {
                            AppIcon(.plus, color: c.ink)
                            Text("Nueva rutina").font(.text(18, .semibold)).foregroundStyle(c.ink)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 72)
                    }
                }
                .padding(.horizontal, kGutter)
            }
            Pressable(action: { Router.shared.homeTab = 1 }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Entrenamiento libre").font(.text(17, .semibold)).foregroundStyle(c.ink)
                    Text("Sin rutina. Eliges ejercicios sobre la marcha.")
                        .font(.text(14))
                        .foregroundStyle(c.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 92)
                .topRule(c.line)
            }
            .padding(.horizontal, kGutter)
        }
    }
}

struct RoutineDetailScreen: View {
    let routineId: String
    @Environment(GymRepository.self) private var repo
    @Environment(SensorService.self) private var sensor
    @Environment(\.colors) private var c

    var body: some View {
        if let routine = repo.routine(routineId) {
            let items = routine.items
            VStack(spacing: 0) {
                BackHeader()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: 8)
                        Text(routine.name)
                            .font(.text(36, .medium))
                            .foregroundStyle(c.ink)
                        Spacer().frame(height: 6)
                        Text(routineSubtitle(routine)).font(.text(16)).foregroundStyle(c.ink2)
                        Spacer().frame(height: 20)
                        HStack(spacing: 8) {
                            SmallButton("Editar") { Router.shared.push(.routineEditor(routine)) }
                            SmallButton("Duplicar") {
                                let copy = repo.duplicateRoutine(routine.id)
                                Router.shared.replaceTop(with: .routineDetail(copy.id))
                                showMessage("Rutina duplicada.")
                            }
                        }
                        Spacer().frame(height: 12)
                        if items.isEmpty {
                            Text("Esta rutina no tiene ejercicios. Agrégalos desde Editar.")
                                .font(.text(16))
                                .foregroundStyle(c.ink2)
                                .padding(.top, 24)
                        }
                        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                            ItemRow(index: i + 1, item: item, exercise: repo.exercise(item.exerciseId),
                                    last: i == items.count - 1)
                        }
                    }
                    .padding(.horizontal, kGutter)
                }
                PrimaryButton("Empezar entrenamiento", action: items.isEmpty ? nil : {
                    startWorkout(WorkoutSpec(kind: .routine(routine)), sensor: sensor)
                })
                .padding(EdgeInsets(top: 16, leading: kGutter, bottom: 32, trailing: kGutter))
            }
        } else {
            // Deleted from the editor.
            Color.clear
        }
    }
}

private struct ItemRow: View {
    let index: Int
    let item: RoutineItem
    let exercise: Exercise?
    let last: Bool
    @Environment(\.colors) private var c

    var body: some View {
        Pressable(action: exercise.map { e in { Router.shared.push(.exerciseDetail(e)) } }) {
            HStack(spacing: 0) {
                Text("\(index)")
                    .font(.number(22))
                    .foregroundStyle(c.ink3)
                    .frame(width: 32, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise?.name ?? "Ejercicio no disponible")
                        .font(.text(19, .medium))
                        .foregroundStyle(c.ink)
                        .lineLimit(1)
                    Text(routineItemLine(item))
                        .font(.text(15))
                        .foregroundStyle(c.ink2)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let exercise { PlacementTag(placement: exercise.placement) }
            }
            .frame(height: 84)
            .topRule(c.line)
            .bottomRule(c.line, visible: last)
        }
    }
}

/// Create or edit a routine. Hold and drag to reorder, swipe left to
/// remove, tap a value to change it.
struct RoutineEditorScreen: View {
    /// Nil creates a new routine.
    let routine: Routine?
    let route: Route

    private struct Entry: Identifiable {
        let id: Int
        var item: RoutineItem
    }

    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c
    @State private var name = ""
    @State private var entries: [Entry] = []
    @State private var nextKey = 0
    @State private var dirty = false
    @State private var saving = false
    @State private var didSetup = false
    @FocusState private var nameFocused: Bool

    private func change(_ apply: () -> Void) {
        apply()
        dirty = true
    }

    private func save() {
        let trimmed = name.trimmed
        if trimmed.isEmpty {
            showMessage("Ponle un nombre a la rutina.")
            return
        }
        saving = true
        repo.saveRoutine(Routine(id: routine?.id ?? "", name: trimmed, items: entries.map(\.item)))
        dirty = false
        Router.shared.pop()
    }

    private func leave() {
        Task {
            if dirty {
                let discard = await confirm(
                    title: "¿Descartar cambios?",
                    message: "Lo que cambiaste en esta rutina no se guardará.",
                    confirmLabel: "Descartar",
                    cancelLabel: "Seguir editando"
                )
                guard discard else { return }
            }
            dirty = false
            Router.shared.pop()
        }
    }

    private func delete() {
        guard let routine else { return }
        Task {
            let ok = await confirm(
                title: "¿Eliminar \"\(routine.name)\"?",
                message: "El historial de sesiones con esta rutina se conserva.",
                confirmLabel: "Eliminar"
            )
            guard ok else { return }
            repo.deleteRoutine(routine.id)
            dirty = false
            Router.shared.popToFirst()
        }
    }

    private func addExercises() {
        let trimmed = name.trimmed
        Router.shared.pickExercises(title: trimmed.isEmpty ? "Agregar ejercicios" : "Agregar a \(trimmed)") {
            picked in
            guard !picked.isEmpty else { return }
            change {
                for exercise in picked {
                    entries.append(Entry(id: nextKey, item: RoutineItem(
                        exerciseId: exercise.id,
                        weightKg: exercise.equipment == .bodyweight ? nil : repo.lastWeight(exercise.id) ?? 20
                    )))
                    nextKey += 1
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: routine == nil ? "Nueva rutina" : "Editar rutina", onCancel: leave,
                        actionLabel: "Guardar", onAction: saving ? nil : save)
            VStack(alignment: .leading, spacing: 4) {
                AppLabel("Nombre")
                TextField("", text: $name, prompt: Text("Nombre de la rutina").foregroundStyle(c.ink3))
                    .font(.text(26, .medium))
                    .foregroundStyle(c.ink)
                    .tint(c.ink)
                    .textInputAutocapitalization(.sentences)
                    .focused($nameFocused)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(nameFocused ? c.ink : c.control)
                            .frame(height: nameFocused ? 1.5 : 1)
                    }
                    .onChange(of: name) { _, _ in if didSetup { dirty = true } }
            }
            .padding(EdgeInsets(top: 12, leading: kGutter, bottom: 16, trailing: kGutter))
            Rule()
            List {
                ForEach($entries) { $entry in
                    EditorRow(
                        name: repo.exercise(entry.item.exerciseId)?.name ?? entry.item.exerciseId,
                        item: entry.item,
                        onChanged: { item in change { entry.item = item } }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(c.bg)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            let id = entry.id
                            change { entries.removeAll { $0.id == id } }
                        } label: {
                            Text("Eliminar")
                        }
                        .tint(c.btnBg)
                    }
                }
                .onMove { from, to in change { entries.move(fromOffsets: from, toOffset: to) } }

                VStack(spacing: 16) {
                    SecondaryButton("Agregar ejercicio", icon: .plus, action: addExercises)
                    if routine != nil {
                        TextAction(label: "Eliminar rutina", action: delete)
                    }
                }
                .padding(EdgeInsets(top: 24, leading: kGutter, bottom: 24, trailing: kGutter))
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(c.bg)
                .moveDisabled(true)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollDismissesKeyboard(.immediately)
        }
        .blocksBack(route, dirty)
        .onAppear {
            guard !didSetup else { return }
            name = routine?.name ?? ""
            entries = (routine?.items ?? []).enumerated().map { Entry(id: $0.offset, item: $0.element) }
            nextKey = entries.count
            DispatchQueue.main.async { didSetup = true }
        }
    }
}

private struct EditorRow: View {
    let name: String
    let item: RoutineItem
    let onChanged: (RoutineItem) -> Void
    @Environment(\.colors) private var c

    var body: some View {
        HStack(spacing: 4) {
            AppIcon(.dragHandle, color: c.ink2)
                .frame(width: 44, height: 64)
                .accessibilityLabel("Mantén presionado y arrastra para reordenar: \(name)")
            VStack(alignment: .leading, spacing: 10) {
                Text(name)
                    .font(.text(17, .medium))
                    .foregroundStyle(c.ink)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Cell(label: "Series", value: "\(item.sets)") {
                        if let v = await askInt("Series", item.sets, min: 1, max: 20) {
                            var copy = item
                            copy.sets = v
                            onChanged(copy)
                        }
                    }
                    Cell(label: "Reps", value: "\(item.reps)") {
                        if let v = await askInt("Repeticiones", item.reps, min: 1, max: 100) {
                            var copy = item
                            copy.reps = v
                            onChanged(copy)
                        }
                    }
                    Cell(label: "Peso", value: item.weightKg == nil ? "Corp." : "\(formatKg(item.weightKg!)) kg") {
                        if let result = await askWeight(item.weightKg) {
                            var copy = item
                            copy.weightKg = result.value
                            onChanged(copy)
                        }
                    }
                    Cell(label: "Descanso", value: formatClock(item.restSeconds)) {
                        if let v = await askRest(item.restSeconds) {
                            var copy = item
                            copy.restSeconds = v
                            onChanged(copy)
                        }
                    }
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, kGutter)
        .frame(height: 116)
        .background(c.bg)
        .bottomRule(c.line)
    }
}

private struct Cell: View {
    let label: String
    let value: String
    let onTap: () async -> Void
    @Environment(\.colors) private var c

    var body: some View {
        Pressable(action: { Task { await onTap() } }, label: "\(label): \(value). Cambiar") {
            VStack(alignment: .leading, spacing: 2) {
                AppLabel(label, color: c.ink2, size: 10).lineLimit(1)
                Text(value)
                    .font(.number(21))
                    .foregroundStyle(c.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 52)
            .background(c.surface, in: RoundedRectangle(cornerRadius: kRadius))
        }
    }
}

// MARK: - Value dialogs

/// Small dialog with one text field. Returns the parsed value, or nil if
/// cancelled.
@MainActor
private func askValue<T>(title: String, initial: String, hint: String, keyboard: UIKeyboardType,
                         error: String, footnote: String? = nil, parse: @escaping (String) -> T?) async -> T? {
    await OverlayCenter.shared.dialog { finish in
        AnyView(ValueDialog(title: title, initial: initial, hint: hint, keyboard: keyboard, error: error,
                            footnote: footnote, parse: parse, finish: finish))
    }
}

private struct ValueDialog<T>: View {
    let title: String
    let initial: String
    let hint: String
    let keyboard: UIKeyboardType
    let error: String
    let footnote: String?
    let parse: (String) -> T?
    let finish: (T?) -> Void

    @Environment(\.colors) private var c
    @State private var text = ""
    @State private var message: String?
    @FocusState private var focused: Bool

    private func submit() {
        if let value = parse(text.trimmed) {
            finish(value)
        } else {
            message = error
        }
    }

    var body: some View {
        AppDialog(title: title) {
            VStack(alignment: .leading, spacing: 0) {
                TextField("", text: $text, prompt: Text(hint).foregroundStyle(c.ink3))
                    .font(.number(40))
                    .foregroundStyle(c.ink)
                    .tint(c.ink)
                    .keyboardType(keyboard)
                    .focused($focused)
                    .onSubmit(submit)
                    .onChange(of: text) { _, value in
                        // Digits and separators only.
                        let filtered = value.filter { "0123456789.,:".contains($0) }
                        if filtered != value { text = filtered }
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(message != nil ? Color.red : (focused ? c.ink : c.control))
                            .frame(height: focused ? 2 : 1)
                    }
                if let message {
                    Text(message).font(.text(12)).foregroundStyle(Color.red).padding(.top, 6)
                }
                if let footnote {
                    Text(footnote).font(.text(14)).foregroundStyle(c.ink2).padding(.top, 8)
                }
            }
        } actions: {
            TextAction(label: "Cancelar") { finish(nil) }
            TextAction(label: "Listo", colorKey: \.ink, weight: .semibold, action: submit)
        }
        .onAppear {
            text = initial
            focused = true
        }
    }
}

@MainActor
private func askInt(_ title: String, _ initial: Int, min: Int, max: Int) async -> Int? {
    await askValue(title: title, initial: "\(initial)", hint: "\(initial)", keyboard: .numberPad,
                   error: "Entre \(min) y \(max).") { text in
        guard let v = Int(text), v >= min, v <= max else { return nil }
        return v
    }
}

/// Wraps the result so "body weight" (nil) can be told apart from cancel.
private struct WeightAnswer {
    let value: Double?
}

@MainActor
private func askWeight(_ initial: Double?) async -> WeightAnswer? {
    await askValue(title: "Peso (kg)", initial: initial.map(formatKg) ?? "", hint: "0", keyboard: .decimalPad,
                   error: "Escribe un peso entre 0 y 500.",
                   footnote: "Déjalo vacío o en 0 para peso corporal.") { text in
        if text.isEmpty { return WeightAnswer(value: nil) }
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")), v >= 0, v <= 500 else { return nil }
        return WeightAnswer(value: v == 0 ? nil : v)
    }
}

@MainActor
private func askRest(_ initial: Int) async -> Int? {
    await askValue(title: "Descanso", initial: formatClock(initial), hint: "1:30",
                   keyboard: .numbersAndPunctuation, error: "Usa minutos:segundos, por ejemplo 1:30.",
                   footnote: "Minutos y segundos, por ejemplo 1:30.") { text in
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        var seconds: Int?
        if parts.count == 1 {
            seconds = Int(parts[0])
        } else if parts.count == 2 {
            let m = parts[0].isEmpty ? 0 : Int(parts[0])
            let s = Int(parts[1])
            if let m, let s, s < 60 { seconds = m * 60 + s }
        }
        guard let seconds, seconds >= 0, seconds <= 900 else { return nil }
        return seconds
    }
}

import SwiftUI

/// "Ejercicios" tab: explore the catalog and open an exercise.
struct CatalogTab: View {
    var body: some View {
        VStack(spacing: 0) {
            TabHeader(title: "Ejercicios")
            ExerciseBrowser { Router.shared.push(.exerciseDetail($0)) }
        }
    }
}

/// Placement icon with its name underneath ("EQUIPO").
struct PlacementTag: View {
    let placement: SensorPlacement
    @Environment(\.colors) private var c

    var body: some View {
        VStack(spacing: 2) {
            AppIcon(placement.icon, color: c.ink)
            Text(placement.label.uppercased())
                .font(.text(11, .semibold))
                .tracking(11 * 0.06)
                .foregroundStyle(c.ink2)
        }
        .frame(width: 52)
    }
}

/// The exercise's thumbnail, or its equipment icon when there is none (an
/// exercise the server added after this build).
struct ExerciseThumbnail: View {
    let exercise: Exercise
    var size: CGFloat = 48
    @Environment(\.colors) private var c

    var body: some View {
        Group {
            if let image = ExerciseImages.image(for: exercise.id) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                AppIcon(exercise.equipment.icon, size: size * 0.5, color: c.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(c.surface)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: kRadius))
        .overlay(RoundedRectangle(cornerRadius: kRadius).strokeBorder(c.line, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    /// Nil hides the checkbox.
    var checked: Bool?
    let onTap: () -> Void
    @Environment(\.colors) private var c

    var body: some View {
        Pressable(action: onTap) {
            HStack(spacing: 0) {
                ExerciseThumbnail(exercise: exercise)
                Spacer().frame(width: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.text(17, .medium))
                        .foregroundStyle(c.ink)
                        .lineLimit(1)
                    Text(exercise.equipment.label)
                        .font(.text(13))
                        .foregroundStyle(c.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 8)
                PlacementTag(placement: exercise.placement)
                if let checked {
                    Spacer().frame(width: 12)
                    AppCheckbox(checked: checked)
                }
            }
            .frame(height: 72)
            .bottomRule(c.line)
        }
    }
}

/// Search, quick picks, equipment filter and muscle groups. Used by the
/// Ejercicios tab (open an exercise) and by the picker (check exercises).
struct ExerciseBrowser: View {
    /// When not nil, rows show a checkbox reflecting this set.
    var selected: Set<String>?
    var showFavorites = true
    var initiallyExpanded: MuscleGroup?
    /// Tap on an exercise or a quick-pick chip.
    let onOpen: (Exercise) -> Void

    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c
    @State private var query = ""
    @State private var equipment: Equipment?
    @State private var expanded: Set<MuscleGroup> = []
    @State private var didSetup = false

    init(selected: Set<String>? = nil, showFavorites: Bool = true, initiallyExpanded: MuscleGroup? = nil,
         onOpen: @escaping (Exercise) -> Void) {
        self.selected = selected
        self.showFavorites = showFavorites
        self.initiallyExpanded = initiallyExpanded
        self.onOpen = onOpen
    }

    private static func fold(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "á", with: "a")
            .replacingOccurrences(of: "é", with: "e")
            .replacingOccurrences(of: "í", with: "i")
            .replacingOccurrences(of: "ó", with: "o")
            .replacingOccurrences(of: "ú", with: "u")
            .replacingOccurrences(of: "ñ", with: "n")
    }

    private static func words(_ s: String) -> [Substring] {
        s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }

    /// Every word typed starts some word of the name, in any order:
    /// "apertura maquina" finds "Aperturas en máquina (pec deck)".
    private static func matches(_ name: String, _ foldedQuery: String) -> Bool {
        let nameWords = words(fold(name))
        return words(foldedQuery).allSatisfy { typed in nameWords.contains { $0.hasPrefix(typed) } }
    }

    private func row(_ e: Exercise) -> some View {
        ExerciseRow(exercise: e, checked: selected.map { $0.contains(e.id) }) { onOpen(e) }
            .padding(.horizontal, kGutter)
    }

    private func section(_ label: String) -> some View {
        AppLabel(label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 24, leading: kGutter, bottom: 8, trailing: kGutter))
    }

    var body: some View {
        let folded = Self.fold(query.trimmed)
        let filtered = repo.exercises.filter {
            $0.active && (equipment == nil || $0.equipment == equipment)
                && (folded.isEmpty || Self.matches($0.name, folded))
        }
        let recents = repo.recentExercises()
        let favorites = repo.favoriteExercises

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                SearchField(text: $query)
                    .padding(.horizontal, kGutter)
                if folded.isEmpty && !recents.isEmpty {
                    section("Recientes")
                    ChipRow {
                        ForEach(recents) { e in
                            OutlineChip(label: e.name, icon: e.equipment.icon) { onOpen(e) }
                        }
                    }
                }
                if folded.isEmpty && showFavorites && !favorites.isEmpty {
                    section("Favoritos")
                    ChipRow {
                        ForEach(favorites) { e in
                            OutlineChip(label: e.name, icon: e.equipment.icon) { onOpen(e) }
                        }
                    }
                }
                section("Equipo")
                ChipRow {
                    ForEach(Equipment.allCases, id: \.self) { eq in
                        FillChip(label: eq.label, selected: equipment == eq, icon: eq.icon, fontSize: 14) {
                            equipment = equipment == eq ? nil : eq
                        }
                    }
                }
                if !folded.isEmpty {
                    section("Resultados")
                    if filtered.isEmpty {
                        Text("Ningún ejercicio coincide con \"\(query)\".")
                            .font(.text(16))
                            .foregroundStyle(c.ink2)
                            .padding(.horizontal, kGutter)
                    }
                    ForEach(filtered) { row($0) }
                } else {
                    section("Grupo muscular")
                    ForEach(MuscleGroup.allCases, id: \.self) { group in
                        let inGroup = filtered.filter { $0.muscleGroup == group }
                        let open = expanded.contains(group)
                        Pressable(action: {
                            if expanded.contains(group) { expanded.remove(group) } else { expanded.insert(group) }
                        }) {
                            HStack {
                                Text(group.label)
                                    .font(.text(19, open ? .semibold : .medium))
                                    .foregroundStyle(c.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(inGroup.count)")
                                    .font(.number(22))
                                    .foregroundStyle(c.ink2)
                            }
                            .frame(height: 56)
                            .bottomRule(open ? c.ink : c.line)
                            .padding(.horizontal, kGutter)
                        }
                        if open {
                            ForEach(inGroup) { row($0) }
                        }
                    }
                }
                // Required by the image license.
                Text("Imágenes © Gym visual — gymvisual.com")
                    .font(.text(12))
                    .foregroundStyle(c.ink3)
                    .padding(EdgeInsets(top: 24, leading: kGutter, bottom: 0, trailing: kGutter))
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .onAppear {
            guard !didSetup else { return }
            didSetup = true
            if let initiallyExpanded { expanded.insert(initiallyExpanded) }
        }
    }
}

/// Exercise detail, option A of the mockups: tutorial behind a button.
/// "Empezar" opens a free workout with this exercise.
struct ExerciseDetailScreen: View {
    let exercise: Exercise
    @Environment(GymRepository.self) private var repo
    @Environment(SensorService.self) private var sensor
    @Environment(\.colors) private var c
    @State private var weight: Double?
    @State private var didSetup = false

    var body: some View {
        let favorite = repo.favoriteIds.contains(exercise.id)
        let hasHistory = repo.lastWeight(exercise.id) != nil

        VStack(spacing: 0) {
            BackHeader {
                IconTapTarget(icon: favorite ? .star : .starOutline,
                              label: favorite ? "Quitar de favoritos" : "Agregar a favoritos") {
                    repo.toggleFavorite(exercise.id)
                }
                Spacer().frame(width: 8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 8)
                    Text(exercise.name)
                        .font(.text(36, .medium))
                        .foregroundStyle(c.ink)
                    Spacer().frame(height: 6)
                    Text("\(exercise.muscleGroup.label) · \(exercise.equipment.label)")
                        .font(.text(16))
                        .foregroundStyle(c.ink2)
                    if ExerciseDemoView.available(exercise) {
                        Spacer().frame(height: 24)
                        ExerciseDemoView(exercise: exercise)
                    }
                    if !exercise.tutorialSteps.isEmpty {
                        Spacer().frame(height: 32)
                        AppLabel("Cómo hacerlo")
                        Spacer().frame(height: 8)
                        StepsList(steps: exercise.tutorialSteps)
                    }
                    Spacer().frame(height: 32)
                    AppLabel("Dónde va el sensor")
                    Spacer().frame(height: 12)
                    SensorDiagram(exercise: exercise)
                    Spacer().frame(height: 16)
                    HStack(alignment: .top, spacing: 12) {
                        AppIcon(exercise.placement.icon, size: 28)
                        (Text("\(exercise.placement.label). ").font(.text(17, .semibold)).foregroundColor(c.ink)
                            + Text(exercise.placementNote).font(.text(17)).foregroundColor(c.ink2))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if exercise.firmwareProfile == kStackProfile {
                        Spacer().frame(height: 16)
                        StackSideMountNote()
                    }
                    Spacer().frame(height: 32)
                    AppLabel(hasHistory ? "Peso · última vez" : "Peso")
                    Spacer().frame(height: 12)
                    WeightStepper(valueKg: weight) { weight = $0 }
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, kGutter)
            }
            PrimaryButton("Empezar") {
                startWorkout(WorkoutSpec(kind: .free(exercise, weightKg: weight)), sensor: sensor)
            }
            .padding(EdgeInsets(top: 8, leading: kGutter, bottom: 32, trailing: kGutter))
        }
        .onAppear {
            guard !didSetup else { return }
            didSetup = true
            weight = repo.lastWeight(exercise.id) ?? (exercise.equipment == .bodyweight ? nil : 20)
        }
    }
}

/// The side of the stack as an alternative mount. The counting does not care
/// how the sensor is turned, only that it moves with the stack and does not
/// shift after calibration: in simulation up to 2-3° of slip is harmless, and
/// from 4° it starts losing slow reps.
struct StackSideMountNote: View {
    @Environment(\.colors) private var c

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppLabel("Si no se puede arriba", color: c.ink2)
            Text("Pégalo de costado, en la placa superior o en cualquiera por encima del pasador: las de "
                + "abajo no se mueven. Cuenta igual, sin importar cómo quede girado.")
                .font(.text(16))
                .foregroundStyle(c.ink)
            Text("Que quede plano y firme. Si con los golpes se desliza o queda torcido, el conteo se "
                + "desajusta: vuelve a pegarlo y empieza el ejercicio de nuevo para que se recalibre.")
                .font(.text(15))
                .foregroundStyle(c.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(c.surface, in: RoundedRectangle(cornerRadius: kRadius))
    }
}

/// "Agregar a Empuje": check exercises and return them in the order they
/// were checked. With `single`, the first tap returns that exercise.
struct ExercisePickerScreen: View {
    let request: PickerRequest
    @Environment(GymRepository.self) private var repo
    @State private var order: [String] = []

    private func toggle(_ exercise: Exercise) {
        if request.single {
            Router.shared.finishPicker(request, [exercise])
            return
        }
        if let index = order.firstIndex(of: exercise.id) {
            order.remove(at: index)
        } else {
            order.append(exercise.id)
        }
    }

    var body: some View {
        let n = order.count
        VStack(spacing: 0) {
            ModalHeader(title: request.title)
            Spacer().frame(height: 16)
            ExerciseBrowser(selected: request.single ? nil : Set(order), showFavorites: false,
                            initiallyExpanded: .chest, onOpen: toggle)
            if !request.single {
                PrimaryButton(n == 0 ? "Agregar ejercicios" : "Agregar \(n) \(n == 1 ? "ejercicio" : "ejercicios")",
                              action: n == 0 ? nil : {
                                  Router.shared.finishPicker(request, order.compactMap(repo.exercise))
                              })
                    .padding(EdgeInsets(top: 16, leading: kGutter, bottom: 32, trailing: kGutter))
            }
        }
    }
}

/// Numbered steps ("Cómo hacerlo").
struct StepsList: View {
    let steps: [String]
    @Environment(\.colors) private var c

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 0) {
                    Text("\(i + 1)")
                        .font(.number(26))
                        .foregroundStyle(c.ink3)
                        .frame(width: 32, alignment: .leading)
                    Text(step)
                        .font(.text(17))
                        .foregroundStyle(c.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 16)
                .bottomRule(c.line, visible: i != steps.count - 1)
            }
        }
    }
}

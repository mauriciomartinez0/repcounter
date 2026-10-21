import SwiftUI

/// Makes sure the sensor is connected, then opens the workout.
@MainActor
func startWorkout(_ spec: WorkoutSpec, sensor: SensorService) {
    if sensor.connected {
        Router.shared.push(.workout(spec))
    } else {
        Router.shared.push(.connection(then: spec))
    }
}

/// Calibración → Contador → Descanso → … → Resumen, driven by the
/// controller's phase.
struct WorkoutFlowScreen: View {
    let spec: WorkoutSpec
    let route: Route

    @Environment(GymRepository.self) private var repo
    @Environment(SensorService.self) private var sensor
    @Environment(\.colors) private var c
    @State private var workout: WorkoutController?
    @State private var closing = false

    private func close() {
        guard let workout, !closing else { return }
        closing = true
        let session = workout.finish()
        workout.dispose()
        Router.shared.blocked.remove(route)
        guard let session else {
            Router.shared.pop()
            return
        }
        tick()
        Router.shared.replaceTop(with: .summary(session, justFinished: true))
    }

    private func askToEnd() {
        guard let workout else { return }
        let hasSets = !workout.records.isEmpty || workout.reps > 0
        Task {
            let end = await confirm(
                title: "¿Terminar entrenamiento?",
                message: hasSets
                    ? "Se guardan las series que ya hiciste."
                    : "Todavía no hay series; no se guardará nada.",
                confirmLabel: "Terminar",
                cancelLabel: "Seguir"
            )
            if end && !closing { close() }
        }
    }

    private func pickExercise() {
        Router.shared.pickExercises(title: "Cambiar ejercicio", single: true) { picked in
            if let first = picked.first { workout?.changeExercise(first) }
        }
    }

    var body: some View {
        Group {
            if let workout {
                let hit = workout.phase == .counting && workout.targetReached
                Group {
                    switch workout.phase {
                    case .calibrating: CalibrationView(workout: workout)
                    case .counting: CounterView(workout: workout)
                    case .analyzing: AnalyzingView(workout: workout)
                    case .reviewing: ReviewView(workout: workout)
                    case .resting: RestView(workout: workout, onChangeExercise: pickExercise, onEnd: askToEnd)
                    case .finished: Color.clear
                    }
                }
                .background((hit ? c.hitBg : c.bg).ignoresSafeArea().animation(.linear(duration: 0.2), value: hit))
                .onChange(of: workout.phase) { _, phase in
                    if phase == .finished && !closing { close() }
                }
            } else {
                Color.clear
            }
        }
        .blocksBack(route, true)
        .onAppear {
            guard workout == nil else { return }
            let controller: WorkoutController
            switch spec.kind {
            case .routine(let routine):
                controller = WorkoutController(routine: routine, repository: repo, sensor: sensor)
            case .free(let exercise, let weightKg):
                controller = WorkoutController(freeExercise: exercise, weightKg: weightKg,
                                               repository: repo, sensor: sensor)
            }
            workout = controller
            controller.start()
        }
        .onDisappear {
            // Only when the workout leaves the stack, not when the picker or
            // the connection screen covers it.
            if !Router.shared.path.contains(route) {
                workout?.dispose()
                Router.shared.blocked.remove(route)
            }
        }
    }
}

private struct CalibrationView: View {
    let workout: WorkoutController
    @Environment(SensorService.self) private var sensor
    @Environment(\.colors) private var c

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(workout.exercise.name)
                    .font(.text(16))
                    .foregroundStyle(c.ink2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SensorBadge()
            }
            .frame(height: 48)
            FirmwareCheckBanner(workout: workout)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text("Quédate quieto en posición de inicio")
                    .font(.text(44))
                    .foregroundStyle(c.ink)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: 48)
                if sensor.connected {
                    // The board does not report progress; this fills over the
                    // usual time and waits near the end for its confirmation.
                    CalibrationTrack().id(workout.exercise.id)
                    Spacer().frame(height: 12)
                    AppLabel("Calibrando sensor", alignment: .center)
                } else {
                    Text("El sensor está desconectado.")
                        .font(.text(18))
                        .foregroundStyle(c.ink2)
                        .multilineTextAlignment(.center)
                    Spacer().frame(height: 20)
                    SecondaryButton("Conectar sensor") { Router.shared.push(.connection(then: nil)) }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(EdgeInsets(top: 0, leading: kGutter, bottom: 40, trailing: kGutter))
    }
}

private struct CalibrationTrack: View {
    @Environment(\.colors) private var c
    @State private var value = 0.0

    var body: some View {
        ProgressTrack(value: value, fill: c.mark)
            .onAppear {
                withAnimation(.linear(duration: 1.5)) { value = 0.9 }
            }
    }
}

private struct CounterView: View {
    let workout: WorkoutController
    @Environment(SensorService.self) private var sensor
    @Environment(\.colors) private var c
    @State private var lastAngle = 0.0
    @State private var rising = true

    var body: some View {
        let angle = min(90, max(0, sensor.state.angleDegrees))
        let threshold = Double(workout.exercise.thresholdDegrees)
        let hit = workout.targetReached
        // Profile 2: the sensor rides a weight stack and the board sends its
        // vertical speed (cm/s, positive up) where the angle usually goes.
        let stack = workout.exercise.firmwareProfile == kStackProfile

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Pressable(action: workout.restartSet) {
                    Text("REINICIAR")
                        .font(.text(13, .semibold))
                        .tracking(13 * 0.08)
                        .foregroundStyle(c.ink2)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .overlay(RoundedRectangle(cornerRadius: kRadius).strokeBorder(c.control, lineWidth: 1))
                }
                Spacer()
                SensorBadge()
            }
            .frame(height: 48)
            if !workout.isFree {
                Spacer().frame(height: 20)
                Text(workout.exercise.name)
                    .font(.text(20, .medium))
                    .foregroundStyle(c.ink)
                Spacer().frame(height: 4)
                Text("Serie \(workout.setNumber) de \(workout.totalSets ?? 0) · objetivo \(workout.targetReps ?? 0)")
                    .font(.text(20))
                    .foregroundStyle(c.ink2)
            }
            Pressable(action: workout.finishSet,
                      label: "\(workout.reps) repeticiones. Toca para terminar la serie.") {
                VStack(spacing: 28) {
                    Text("\(workout.reps)")
                        .font(.number(360))
                        .tracking(-7.2)
                        .foregroundStyle(hit ? c.hitInk : c.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.05)
                        .frame(maxHeight: .infinity)
                    // Not in the mockups: free training needs a way to close a
                    // set, and in a routine it closes early.
                    AppLabel(hit ? "Toca para terminar o sigue sumando" : "Toca el número para terminar la serie",
                             color: c.ink3, alignment: .center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 16)
            }
            if stack {
                FirmwareCheckBanner(workout: workout)
                    .padding(.bottom, 12)
                StackSpeed(cmPerSecond: sensor.state.angleDegrees)
            } else {
                HStack(spacing: 8) {
                    AppIcon(rising ? .arrowUp : .arrowDown, size: 18, color: c.ink2, strokeWidth: 2)
                    Text(rising ? "SUBIENDO" : "BAJANDO")
                        .font(.text(14, .semibold))
                        .tracking(14 * 0.08)
                        .foregroundStyle(c.ink2)
                    Spacer()
                    Text("\(Int(angle.rounded()))°").font(.number(28)).foregroundStyle(c.ink)
                }
                Spacer().frame(height: 12)
                // The live angle is the signal the counter runs on. Seeing it makes
                // a missed rep diagnosable instead of mysterious: if the bar never
                // reaches the threshold mark, the range of motion is short.
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(c.track).frame(height: 4).offset(y: 8)
                        Rectangle()
                            .fill(angle >= threshold ? c.mark : c.ink)
                            .frame(width: w * angle / 90, height: 4)
                            .offset(y: 8)
                        Rectangle()
                            .fill(c.mark)
                            .frame(width: 2, height: 20)
                            .offset(x: w * threshold / 90 - 1)
                    }
                }
                .frame(height: 20)
                Spacer().frame(height: 12)
                HStack {
                    Text("0°")
                    Spacer()
                    Text("Umbral \(Int(threshold.rounded()))°")
                    Spacer()
                    Text("90°")
                }
                .font(.text(13))
                .foregroundStyle(c.ink3)
            }
        }
        .padding(EdgeInsets(top: 0, leading: kGutter, bottom: 40, trailing: kGutter))
        .onChange(of: sensor.state.angleDegrees) { _, raw in
            // Direction from the angle trend, with a little hysteresis so noise
            // at the top or bottom does not flicker the arrow.
            let value = min(90, max(0, raw))
            if value > lastAngle + 0.8 {
                rising = true
                lastAngle = value
            } else if value < lastAngle - 0.8 {
                rising = false
                lastAngle = value
            }
        }
        .onChange(of: workout.reps) { old, new in
            if new > old { tick() }
        }
    }
}

/// Firmware profile that follows a weight stack (cable and selector machines).
let kStackProfile = 2

/// Warns when the exercise counts on the weight stack but the board stays on
/// another profile: firmware older than profile 2 ignores the request and
/// keeps counting by tilt, which cannot count a stack. The board reports its
/// profile in every packet; a short grace period covers the command in flight.
private struct FirmwareCheckBanner: View {
    let workout: WorkoutController
    @Environment(SensorService.self) private var sensor
    @Environment(\.colors) private var c
    @State private var confirmed = false

    private var mismatch: Bool {
        sensor.connected && workout.exercise.firmwareProfile == kStackProfile
            && sensor.state.exerciseId != kStackProfile
    }

    var body: some View {
        Group {
            if confirmed {
                VStack(alignment: .leading, spacing: 6) {
                    AppLabel("Firmware del sensor desactualizado", color: c.ink)
                    Text("Este ejercicio cuenta sobre la pila de pesas y el sensor no conoce ese modo: "
                        + "sigue contando por inclinación, así que el conteo no es fiable. Carga el firmware "
                        + "nuevo en la placa y vuelve a empezar el ejercicio.")
                        .font(.text(15))
                        .foregroundStyle(c.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(c.surface, in: RoundedRectangle(cornerRadius: kRadius))
                .overlay(RoundedRectangle(cornerRadius: kRadius).strokeBorder(c.ink, lineWidth: 1.5))
            }
        }
        .task(id: mismatch) {
            guard mismatch else {
                confirmed = false
                return
            }
            try? await Task.sleep(for: .milliseconds(1500))
            if !Task.isCancelled && mismatch { confirmed = true }
        }
    }
}

/// The set closed and the board is going over it. Usually under a second.
private struct AnalyzingView: View {
    let workout: WorkoutController
    @Environment(\.colors) private var c

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(workout.exercise.name)
                    .font(.text(16))
                    .foregroundStyle(c.ink2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SensorBadge()
            }
            .frame(height: 48)
            Spacer(minLength: 0)
            Text("\(workout.reps)")
                .font(.number(200))
                .foregroundStyle(c.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.1)
            Spacer().frame(height: 24)
            ProgressView().tint(c.ink2)
            Spacer().frame(height: 12)
            AppLabel("Revisando la serie", alignment: .center)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 0, leading: kGutter, bottom: 40, trailing: kGutter))
    }
}

/// The end-of-set analysis found reps the live count missed. The user
/// confirms them or keeps the live count; nothing is added without asking.
private struct ReviewView: View {
    let workout: WorkoutController
    @Environment(\.colors) private var c

    var body: some View {
        let review = workout.review ?? SetReview(live: workout.reps, found: workout.reps)
        let extra = review.extra
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(workout.exercise.name)
                    .font(.text(16))
                    .foregroundStyle(c.ink2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SensorBadge()
            }
            .frame(height: 48)
            Spacer().frame(height: 24)
            AppLabel("Revisión de la serie")
            Spacer().frame(height: 8)
            Text(extra == 1 ? "Encontramos 1 repetición más" : "Encontramos \(extra) repeticiones más")
                .font(.text(36, .medium))
                .foregroundStyle(c.ink)
            Spacer().frame(height: 12)
            Text("Al terminar, el sensor repasó toda la serie y contó repeticiones que el conteo "
                + "en vivo no registró, por ejemplo alguna lenta o a medio recorrido.")
                .font(.text(17))
                .foregroundStyle(c.ink2)
            Spacer(minLength: 24)
            StatPair {
                StatCell(label: "En vivo") {
                    NumberWithUnit(value: "\(review.live)", unit: "reps", size: 64, unitSize: 18)
                }
            } right: {
                StatCell(label: "Con la revisión") {
                    NumberWithUnit(value: "\(review.found)", unit: "reps", size: 64, unitSize: 18, color: c.mark)
                }
            }
            Spacer(minLength: 24)
            PrimaryButton(extra == 1 ? "Sumar 1 · quedan \(review.found)" : "Sumar \(extra) · quedan \(review.found)") {
                workout.resolveReview(addFound: true)
            }
            Spacer().frame(height: 12)
            SecondaryButton("Dejar \(review.live)") {
                workout.resolveReview(addFound: false)
            }
        }
        .padding(EdgeInsets(top: 0, leading: kGutter, bottom: 32, trailing: kGutter))
        .onAppear { tick() }
    }
}

/// Live readout for the weight-stack profile: which way the stack is going and
/// how fast. There is no angle or threshold to show; a rep is a full trip up
/// and back down.
private struct StackSpeed: View {
    let cmPerSecond: Double
    @Environment(\.colors) private var c

    var body: some View {
        // A few cm/s either way is noise, not movement.
        let direction = cmPerSecond > 3 ? 1 : (cmPerSecond < -3 ? -1 : 0)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if direction != 0 {
                    AppIcon(direction > 0 ? .arrowUp : .arrowDown, size: 18, color: c.ink2, strokeWidth: 2)
                }
                Text(direction > 0 ? "SUBIENDO" : (direction < 0 ? "BAJANDO" : "PILA QUIETA"))
                    .font(.text(14, .semibold))
                    .tracking(14 * 0.08)
                    .foregroundStyle(c.ink2)
                Spacer()
                NumberWithUnit(value: formatVelocity(abs(cmPerSecond) / 100), unit: "m/s", size: 28, unitSize: 13)
            }
            Text("Sensor sobre la pila de pesas: cuenta cada subida y bajada completa.")
                .font(.text(13))
                .foregroundStyle(c.ink3)
        }
    }
}

private struct RestView: View {
    let workout: WorkoutController
    let onChangeExercise: () -> Void
    let onEnd: () -> Void
    @Environment(\.colors) private var c

    var body: some View {
        let last = workout.lastRecord
        let next = workout.next
        let total = workout.restTotal
        let velocity = workout.lastSetVelocity

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Descanso")
                    .font(.text(20, .medium))
                    .foregroundStyle(c.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SensorBadge()
            }
            .frame(height: 48)
            if workout.isFree, let last {
                Text("\(workout.exercise.name) · serie \(last.setNumber)")
                    .font(.text(16))
                    .foregroundStyle(c.ink2)
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(formatClock(total == nil ? workout.restElapsed : workout.restRemaining))
                    .font(.number(200))
                    .foregroundStyle(c.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.1)
                Spacer().frame(height: 16)
                if let total {
                    ProgressTrack(value: Double(workout.restElapsed) / Double(max(1, total)))
                    Spacer().frame(height: 10)
                    HStack {
                        Text(formatClock(min(total, max(0, workout.restElapsed))))
                        Spacer()
                        Text(formatClock(total))
                    }
                    .font(.text(13))
                    .foregroundStyle(c.ink3)
                } else {
                    AppLabel("Tiempo de descanso", alignment: .center)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            StatPair {
                StatCell(label: "Repeticiones") {
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        repsValue(last)
                        // Not in the mockups: the sensor can miss a rep, and a
                        // set that came up short should be recorded as it was.
                        if let last {
                            TextAction(label: "Corregir", size: 14, underline: true) {
                                Task {
                                    if let reps = await askReps(
                                        title: "\(workout.exercise.name) · serie \(last.setNumber)",
                                        initial: last.reps, target: last.targetReps
                                    ) {
                                        workout.setLastReps(reps)
                                    }
                                }
                            }
                        }
                    }
                }
            } right: {
                StatCell(label: "Velocidad media") {
                    NumberWithUnit(value: velocity.map(formatVelocity) ?? "—", unit: velocity == nil ? nil : "m/s")
                }
            }
            if let note = workout.analysisNote {
                Text(note.message)
                    .font(.text(13))
                    .foregroundStyle(c.ink2)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                AppLabel("Peso usado").frame(maxWidth: .infinity, alignment: .leading)
                WeightStepper(valueKg: last?.weightKg, large: false) { workout.setLastWeight($0) }
            }
            .frame(height: 96)
            if workout.isFree {
                PrimaryButton("Siguiente serie", action: workout.startNextSet)
                Spacer().frame(height: 12)
                SecondaryButton("Cambiar ejercicio", action: onChangeExercise)
                TextAction(label: "Terminar entrenamiento", action: onEnd)
                    .frame(maxWidth: .infinity)
            } else if let next {
                Rule()
                Spacer().frame(height: 24)
                AppLabel("Sigue")
                Spacer().frame(height: 6)
                Text("\(next.exercise.name) · serie \(next.setNumber) de \(next.totalSets ?? 0)")
                    .font(.text(20, .medium))
                    .foregroundStyle(c.ink)
                Spacer().frame(height: 6)
                Text("\(next.targetReps ?? 0) repeticiones · "
                    + (next.weightKg == nil ? "peso corporal" : "\(formatKg(next.weightKg!)) kg"))
                    .font(.text(16))
                    .foregroundStyle(c.ink2)
                Spacer().frame(height: 12)
                HStack {
                    Text("Empieza sola al terminar el descanso.")
                        .font(.text(13))
                        .foregroundStyle(c.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Not in the mockups: skipping the rest is a common need.
                    TextAction(label: "Empezar ya", colorKey: \.ink, weight: .semibold, size: 14,
                               action: workout.startNextSet)
                }
            }
        }
        .padding(EdgeInsets(top: 0, leading: kGutter, bottom: 32, trailing: kGutter))
    }

    private func repsValue(_ last: SetRecord?) -> some View {
        let reps = last?.reps ?? 0
        let met = last?.targetReps != nil && reps >= last!.targetReps!
        var text = Text("\(reps)").font(.number(40)).foregroundColor(met ? c.mark : c.ink)
        if let target = last?.targetReps {
            text = text + Text(" / \(target)").font(.number(40)).foregroundColor(c.ink2)
        }
        return text.lineLimit(1).minimumScaleFactor(0.5)
    }
}

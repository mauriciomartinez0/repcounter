// State of a workout in progress: which exercise and set comes next, what the
// sensor counted, and the rest timer between sets. The screens in
// WorkoutFlowScreen.swift only render this.

import Foundation
import Observation

enum WorkoutPhase {
    case calibrating, counting
    /// The set closed; the board is analysing it (weight stack only).
    case analyzing
    /// The analysis found reps the live count missed; the user decides.
    case reviewing
    case resting, finished
}

/// What happened with the end-of-set analysis of the last set, shown on the
/// rest screen so it is clear whether the second count ran at all.
enum AnalysisNote: Equatable {
    /// It found the same reps as the live count.
    case matched(Int)
    /// It found fewer; the live count stays (it is never lowered).
    case fewer(found: Int, live: Int)
    /// The user added the reps it found.
    case added(extra: Int, total: Int)
    /// The user kept the live count.
    case keptLive(live: Int, found: Int)
    /// The board has no analysis. `knowsStack`: it does count on the stack,
    /// so it is likely iOS remembering the old firmware's services.
    case unsupported(knowsStack: Bool)
    /// The board answered that it had nothing recorded for this set.
    case notRecorded
    /// No answer in time.
    case noAnswer

    var message: String {
        switch self {
        case .matched(let n):
            return "Revisión de la serie: coincide con el conteo en vivo (\(n))."
        case .fewer(let found, let live):
            return "Revisión de la serie: contó \(found); se mantiene el conteo en vivo (\(live))."
        case .added(let extra, let total):
            return "Revisión de la serie: sumaste \(extra) \(plural(extra, "repetición", "repeticiones")) (\(total) en total)."
        case .keptLive(let live, let found):
            return "Revisión de la serie: encontró \(found); dejaste el conteo en vivo (\(live))."
        case .unsupported(let knowsStack):
            return knowsStack
                ? "Revisión de la serie no disponible. Si ya cargaste el firmware más reciente, olvida el "
                    + "sensor en Ajustes → Bluetooth del iPhone para que iOS vuelva a leerlo."
                : "Revisión de la serie no disponible: el sensor necesita el firmware más reciente."
        case .notRecorded:
            return "Revisión de la serie: el sensor no tenía la serie grabada."
        case .noAnswer:
            return "Revisión de la serie: el sensor no respondió a tiempo."
        }
    }
}

/// Reps the end-of-set analysis found beyond the live count.
struct SetReview: Equatable {
    let live: Int
    let found: Int
    var extra: Int { found - live }
}

/// What the next set will be, for the "Sigue" block on the rest screen.
struct PlannedSet {
    let exercise: Exercise
    let setNumber: Int
    var totalSets: Int?
    var targetReps: Int?
    var weightKg: Double?
}

/// A timer on the main run loop that also fires while scrolling.
@MainActor
final class MainTimer {
    private var timer: Timer?

    func schedule(after seconds: TimeInterval, repeats: Bool = false, _ block: @escaping @MainActor () -> Void) {
        cancel()
        let timer = Timer(timeInterval: seconds, repeats: repeats) { _ in
            MainActor.assumeIsolated { block() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
@Observable
final class WorkoutController {
    /// Seconds without a new rep, once the target is reached, before the set
    /// closes on its own.
    static let autoFinishDelay: TimeInterval = 3

    @ObservationIgnored let repository: GymRepository
    @ObservationIgnored let sensor: SensorService
    /// Where the grip lift of each exercise is kept; without it the setting
    /// lasts only for this workout.
    @ObservationIgnored let settings: SettingsController?
    let routine: Routine?
    let startedAt: Date

    /// Generated here, not by the server, so a workout done without signal
    /// already has its final id and uploading it twice stores it once.
    @ObservationIgnored private let sessionId = newId()
    private(set) var exercise: Exercise
    private(set) var records: [SetRecord] = []

    private(set) var phase: WorkoutPhase = .calibrating
    private var itemIndex = 0
    private(set) var setNumber = 1

    /// Weight changes made during the workout, per routine item.
    private var weightOverrides: [Int: Double?] = [:]
    private var freeWeight: Double?

    // Live tracking of the current set.
    @ObservationIgnored private var lastRepCount = 0
    @ObservationIgnored private var maxAngle = 0.0
    @ObservationIgnored private var velocities: [Double] = []
    @ObservationIgnored private var sawUncalibrated = false
    @ObservationIgnored private let autoFinish = MainTimer()
    @ObservationIgnored private let calibrationFallback = MainTimer()

    // Rest.
    private var restStartedAt: Date?
    @ObservationIgnored private let restTicker = MainTimer()
    private(set) var next: PlannedSet?
    private(set) var review: SetReview?
    /// Outcome of the analysis of the set just finished (weight stack only).
    private(set) var analysisNote: AnalysisNote?
    private var restItemIndex = 0
    /// Bumped by the rest ticker so the clock on screen refreshes.
    private var now = Date()

    @ObservationIgnored private var started = false
    @ObservationIgnored private var disposed = false
    @ObservationIgnored private var listener: UUID?

    init(routine: Routine, repository: GymRepository, sensor: SensorService,
         settings: SettingsController? = nil) {
        self.repository = repository
        self.sensor = sensor
        self.settings = settings
        self.routine = routine
        exercise = repository.exercise(routine.items[0].exerciseId)!
        startedAt = Date()
    }

    init(freeExercise: Exercise, weightKg: Double?, repository: GymRepository, sensor: SensorService,
         settings: SettingsController? = nil) {
        self.repository = repository
        self.sensor = sensor
        self.settings = settings
        routine = nil
        exercise = freeExercise
        freeWeight = weightKg
        startedAt = Date()
    }

    var isFree: Bool { routine == nil }
    var lastRecord: SetRecord? { records.last }

    var item: RoutineItem? { routine?.items[itemIndex] }
    var totalSets: Int? { item?.sets }
    var targetReps: Int? { item?.reps }

    var weightKg: Double? {
        if isFree { return freeWeight }
        if let override = weightOverrides[itemIndex] { return override }
        return item!.weightKg
    }

    var reps: Int { max(0, sensor.state.repCount) }

    private var gripLift: [String: Int] = [:]

    /// How far the stack rises when the user takes the handle on this
    /// exercise. Moves of that size are not counted as reps.
    var gripLiftCm: Int { gripLift[exercise.id] ?? settings?.gripLiftCm(exercise.id) ?? 0 }

    func setGripLift(_ cm: Int) {
        let value = min(kMaxGripLiftCm, max(0, cm))
        gripLift[exercise.id] = value
        settings?.setGripLiftCm(exercise.id, value)
        sensor.setGripLift(value)
    }
    var targetReached: Bool { targetReps != nil && reps >= targetReps! }

    /// Seconds since the rest started.
    var restElapsed: Int {
        guard let start = restStartedAt else { return 0 }
        return Int(now.timeIntervalSince(start))
    }

    /// Planned rest of the set just finished; nil in free training.
    var restTotal: Int? {
        if isFree || records.isEmpty { return nil }
        return routine!.items[restItemIndex].restSeconds
    }

    var restRemaining: Int { max(0, (restTotal ?? 0) - restElapsed) }

    /// Mean velocity of the last finished set.
    var lastSetVelocity: Double? { lastRecord?.meanVelocity }

    func start() {
        guard !started else { return }
        started = true
        listener = sensor.addListener { [weak self] in self?.onSensor() }
        beginExercise()
    }

    private func beginExercise() {
        phase = .calibrating
        sawUncalibrated = false
        resetTracking()
        sensor.setExercise(exercise.firmwareProfile)
        if onStack { sensor.setGripLift(gripLiftCm) }
        sensor.rezero()
        // If the board recaptures so fast that we never see it uncalibrated,
        // trust its flag after a short wait.
        calibrationFallback.schedule(after: 2) { [weak self] in
            self?.sawUncalibrated = true
            self?.onSensor()
        }
    }

    private func resetTracking() {
        lastRepCount = 0
        maxAngle = 0
        velocities.removeAll()
        autoFinish.cancel()
    }

    private func onSensor() {
        if disposed { return }
        let state = sensor.state
        switch phase {
        case .calibrating:
            if !state.referenceCaptured { sawUncalibrated = true }
            if sawUncalibrated && state.referenceCaptured {
                calibrationFallback.cancel()
                // Change phase before resetting: the reset notifies right back.
                phase = .counting
                resetTracking()
                sensor.resetCount()
            }
        case .counting:
            maxAngle = max(maxAngle, state.angleDegrees)
            if state.repCount > lastRepCount {
                lastRepCount = state.repCount
                if let v = state.lastRepVelocity { velocities.append(v) }
                if targetReached {
                    autoFinish.schedule(after: Self.autoFinishDelay) { [weak self] in self?.finishSet() }
                }
            } else if state.repCount < lastRepCount {
                // The board was reset (button or reconnect).
                resetTracking()
            }
        case .analyzing, .reviewing, .resting, .finished:
            break
        }
    }

    /// "Reiniciar": start the current set over.
    func restartSet() {
        resetTracking()
        sensor.resetCount()
    }

    /// Weight stack: the board sends the stack's speed where the angle goes.
    var onStack: Bool { exercise.firmwareProfile == kStackProfile }

    /// Close the current set and move to rest, or to the end of the workout.
    /// On the weight stack the board first analyses the set; if it finds reps
    /// the live count missed, the user confirms them before the set is saved.
    func finishSet() {
        guard phase == .counting else { return }
        autoFinish.cancel()
        let live = reps
        analysisNote = nil
        guard onStack else {
            recordSet(reps: live)
            return
        }
        guard sensor.supportsSetAnalysis else {
            analysisNote = .unsupported(knowsStack: sensor.state.exerciseId == kStackProfile)
            recordSet(reps: live)
            return
        }
        phase = .analyzing
        Task { [weak self] in
            guard let self else { return }
            let analysis = await self.sensor.analyzeSet()
            guard self.phase == .analyzing, !self.disposed else { return }
            guard let analysis else {
                self.analysisNote = .noAnswer
                self.recordSet(reps: live)
                return
            }
            guard analysis.status != .unavailable else {
                self.analysisNote = .notRecorded
                self.recordSet(reps: live)
                return
            }
            // The count is only ever corrected upwards.
            if analysis.found > live {
                self.review = SetReview(live: live, found: analysis.found)
                self.phase = .reviewing
            } else {
                self.analysisNote = analysis.found == live
                    ? .matched(live) : .fewer(found: analysis.found, live: live)
                self.recordSet(reps: live)
            }
        }
    }

    /// The user's answer on the review screen.
    func resolveReview(addFound: Bool) {
        guard phase == .reviewing, let review else { return }
        self.review = nil
        analysisNote = addFound
            ? .added(extra: review.extra, total: review.found)
            : .keptLive(live: review.live, found: review.found)
        recordSet(reps: addFound ? review.found : review.live)
    }

    private func recordSet(reps: Int) {
        // A set with fewer reps than planned, even zero, is still a set: the
        // history should show where the effort dropped off.
        records.append(SetRecord(
            exerciseId: exercise.id,
            setNumber: setNumber,
            reps: reps,
            targetReps: targetReps,
            weightKg: weightKg,
            meanVelocity: velocities.isEmpty ? nil : velocities.reduce(0, +) / Double(velocities.count),
            // On the stack the "angle" is a speed, not a range of motion.
            rangeDegrees: !onStack && maxAngle > 0 ? maxAngle : nil,
            completedAt: Date()
        ))
        restItemIndex = itemIndex

        next = planNext()
        if next == nil {
            // The last set has no rest screen to show the analysis on.
            if let analysisNote { showMessage(analysisNote.message) }
            phase = .finished
            return
        }
        phase = .resting
        restStartedAt = Date()
        now = Date()
        restTicker.schedule(after: 0.25, repeats: true) { [weak self] in
            guard let self else { return }
            self.now = Date()
            if !self.isFree && self.restRemaining <= 0 { self.startNextSet() }
        }
    }

    private func planNext() -> PlannedSet? {
        guard let routine else {
            return PlannedSet(exercise: exercise, setNumber: setNumber + 1, weightKg: freeWeight)
        }
        let current = routine.items[itemIndex]
        if setNumber < current.sets {
            return PlannedSet(exercise: exercise, setNumber: setNumber + 1, totalSets: current.sets,
                              targetReps: current.reps, weightKg: weightKg)
        }
        if itemIndex + 1 < routine.items.count {
            let nextItem = routine.items[itemIndex + 1]
            guard let nextExercise = repository.exercise(nextItem.exerciseId) else { return nil }
            return PlannedSet(exercise: nextExercise, setNumber: 1, totalSets: nextItem.sets,
                              targetReps: nextItem.reps, weightKg: nextItem.weightKg)
        }
        return nil
    }

    /// End the rest and start the planned set. Recalibrates when the
    /// exercise changes, since the sensor probably moved.
    func startNextSet() {
        guard phase == .resting, let planned = next else { return }
        restTicker.cancel()
        restStartedAt = nil
        next = nil
        let sameExercise = planned.exercise.id == exercise.id
        // In a routine, set 1 always means the next item, even if it repeats
        // the same exercise.
        if !isFree && planned.setNumber == 1 { itemIndex += 1 }
        setNumber = planned.setNumber
        exercise = planned.exercise
        if sameExercise {
            phase = .counting
            resetTracking()
            sensor.resetCount()
        } else {
            beginExercise()
        }
    }

    /// Free training: switch exercise during the rest.
    func changeExercise(_ newExercise: Exercise) {
        restTicker.cancel()
        restStartedAt = nil
        next = nil
        exercise = newExercise
        setNumber = 1
        freeWeight = repository.lastWeight(newExercise.id)
        beginExercise()
    }

    /// "Peso usado" on the rest screen corrects the set just done and carries
    /// over to the following sets of the same exercise.
    func setLastWeight(_ kg: Double?) {
        guard var last = records.popLast() else { return }
        last.weightKg = kg
        records.append(last)
        if last.exerciseId == exercise.id {
            if isFree {
                freeWeight = kg
            } else {
                weightOverrides[itemIndex] = .some(kg)
            }
        }
        if let planned = next, planned.exercise.id == last.exerciseId {
            next = PlannedSet(exercise: planned.exercise, setNumber: planned.setNumber,
                              totalSets: planned.totalSets, targetReps: planned.targetReps, weightKg: kg)
        }
    }

    /// "Corregir" on the rest screen: the sensor can miss or double-count a
    /// rep, and the history should hold what was really done.
    func setLastReps(_ reps: Int) {
        guard reps >= 0, var last = records.popLast() else { return }
        last.reps = reps
        records.append(last)
    }

    /// Ends the workout. Returns the saved session, or nil when no set was
    /// completed.
    func finish() -> WorkoutSession? {
        // A set in progress with reps counts. Ending the workout does not wait
        // for the analysis: the set keeps its live count.
        if phase == .counting && reps > 0 {
            autoFinish.cancel()
            recordSet(reps: reps)
        } else if phase == .reviewing, let review {
            recordSet(reps: review.live)
        } else if phase == .analyzing {
            recordSet(reps: reps)
        }
        phase = .finished
        stopTimers()
        sensor.removeListener(listener)
        listener = nil
        if records.isEmpty { return nil }
        let session = WorkoutSession(
            id: sessionId,
            routineId: routine?.id,
            title: routine?.name ?? "Entrenamiento libre",
            startedAt: startedAt,
            endedAt: Date(),
            sets: records,
            plannedExercises: routine?.items.count ?? 0
        )
        repository.saveSession(session)
        return session
    }

    private func stopTimers() {
        autoFinish.cancel()
        restTicker.cancel()
        calibrationFallback.cancel()
    }

    func dispose() {
        disposed = true
        stopTimers()
        sensor.removeListener(listener)
        listener = nil
    }
}

// Domain models. They serialize to JSON with the same shape the backend API
// uses (camelCase, ISO 8601 dates with time zone), exactly like the Flutter
// app, so both share the server and the offline files' format.

import Foundation

typealias JSON = [String: Any]

struct DecodeError: Error {
    let field: String
}

/// Explicit JSON null for optionals: the API expects the key to be present.
func orNull<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }

func jsonInt(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }
func jsonDouble(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
func jsonString(_ v: Any?) -> String? { v as? String }
func jsonBool(_ v: Any?) -> Bool? { (v as? NSNumber)?.boolValue }

func require<T>(_ v: T?, _ field: String) throws -> T {
    guard let v else { throw DecodeError(field: field) }
    return v
}

/// Dates go to the API in UTC with an explicit zone; the API rejects dates
/// without one. They come back in UTC with up to microseconds.
enum ISODate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(_ date: Date) -> String { withFraction.string(from: date) }

    static func parse(_ raw: Any?) -> Date? {
        guard var s = raw as? String else { return nil }
        // Keep milliseconds only: the formatter rejects longer fractions.
        if let dot = s.firstIndex(of: ".") {
            var end = s.index(after: dot)
            while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
            var digits = String(s[s.index(after: dot)..<end])
            digits = String(digits.prefix(3))
            while digits.count < 3 { digits += "0" }
            s.replaceSubrange(dot..<end, with: "." + digits)
        }
        // A date without a zone is taken as UTC.
        if !s.hasSuffix("Z") && s.range(of: #"[+-]\d\d:?\d\d$"#, options: .regularExpression) == nil {
            s += "Z"
        }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }
}

enum MuscleGroup: String, CaseIterable, Hashable {
    case chest, back, legs, shoulders, arms, core

    var label: String {
        switch self {
        case .chest: "Pecho"
        case .back: "Espalda"
        case .legs: "Piernas"
        case .shoulders: "Hombros"
        case .arms: "Brazos"
        case .core: "Core"
        }
    }
}

enum Equipment: String, CaseIterable, Hashable {
    case barbell, dumbbell, machine, bodyweight, cable

    var label: String {
        switch self {
        case .barbell: "Barra"
        case .dumbbell: "Mancuerna"
        case .machine: "Máquina"
        case .bodyweight: "Peso corporal"
        case .cable: "Polea"
        }
    }

    var icon: AppIconKind {
        switch self {
        case .barbell: .barbell
        case .dumbbell: .dumbbell
        case .machine: .machine
        case .bodyweight: .bodyweight
        case .cable: .cable
        }
    }
}

/// Where the sensor goes. Also decides which counting profile the firmware
/// uses (see `Exercise.firmwareProfile`).
enum SensorPlacement: String, CaseIterable, Hashable {
    case arm, body, equipment

    var label: String {
        switch self {
        case .arm: "Brazo"
        case .body: "Cuerpo"
        case .equipment: "Equipo"
        }
    }

    var hint: String {
        switch self {
        case .arm: "Antebrazo o muñeca"
        case .body: "Cintura o mochila"
        case .equipment: "Barra o máquina"
        }
    }

    var icon: AppIconKind {
        switch self {
        case .arm: .placementArm
        case .body: .placementBody
        case .equipment: .placementEquipment
        }
    }
}

struct Exercise: Hashable, Identifiable {
    let id: String
    let name: String
    let muscleGroup: MuscleGroup
    let equipment: Equipment
    let placement: SensorPlacement

    /// "Sobre la barra, en el centro."
    let placementNote: String

    /// Exercise id the board understands (CMD_SET_EXERCISE): 0 sensor on the
    /// arm (or a bar that turns), 1 on the body, 2 weight stack or a bar that
    /// starts low, 3 a bar that starts high (bench press, squat).
    var firmwareProfile = 0

    /// Angle the movement has to pass for a rep to count.
    var thresholdDegrees = 70

    var tutorialSteps: [String] = []
    var tutorialSeconds = 0
    var videoUrl: String?

    /// Retired exercises stay in the catalog so history keeps their name, but
    /// are not offered for new workouts.
    var active = true

    var hasTutorial: Bool { !tutorialSteps.isEmpty || videoUrl != nil }

    func toJSON() -> JSON {
        [
            "id": id,
            "name": name,
            "muscleGroup": muscleGroup.rawValue,
            "equipment": equipment.rawValue,
            "placement": placement.rawValue,
            "placementNote": placementNote,
            "firmwareProfile": firmwareProfile,
            "thresholdDegrees": thresholdDegrees,
            "tutorialSteps": tutorialSteps,
            "tutorialSeconds": tutorialSeconds,
            "videoUrl": orNull(videoUrl),
            "active": active,
        ]
    }

    init(id: String, name: String, muscleGroup: MuscleGroup, equipment: Equipment,
         placement: SensorPlacement, placementNote: String, firmwareProfile: Int = 0,
         thresholdDegrees: Int = 70, tutorialSteps: [String] = [], tutorialSeconds: Int = 0,
         videoUrl: String? = nil, active: Bool = true) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.placement = placement
        self.placementNote = placementNote
        self.firmwareProfile = firmwareProfile
        self.thresholdDegrees = thresholdDegrees
        self.tutorialSteps = tutorialSteps
        self.tutorialSeconds = tutorialSeconds
        self.videoUrl = videoUrl
        self.active = active
    }

    init(json j: JSON) throws {
        id = try require(jsonString(j["id"]), "id")
        name = try require(jsonString(j["name"]), "name")
        muscleGroup = try require(MuscleGroup(rawValue: jsonString(j["muscleGroup"]) ?? ""), "muscleGroup")
        equipment = try require(Equipment(rawValue: jsonString(j["equipment"]) ?? ""), "equipment")
        placement = try require(SensorPlacement(rawValue: jsonString(j["placement"]) ?? ""), "placement")
        placementNote = try require(jsonString(j["placementNote"]), "placementNote")
        firmwareProfile = jsonInt(j["firmwareProfile"]) ?? 0
        thresholdDegrees = jsonInt(j["thresholdDegrees"]) ?? 70
        tutorialSteps = (j["tutorialSteps"] as? [Any])?.compactMap { $0 as? String } ?? []
        tutorialSeconds = jsonInt(j["tutorialSeconds"]) ?? 0
        videoUrl = jsonString(j["videoUrl"])
        active = jsonBool(j["active"]) ?? true
    }
}

/// How a machine or cable carries its weight. The catalog says the usual one,
/// but gyms differ (a lat pulldown can be plate loaded, a leg press can have
/// a stack), and it decides how the sensor counts: on a stack it follows the
/// height of the plates (profile 2), on plates it follows the tilt of the
/// lever arm (profile 0).
enum MachineLoad: String, CaseIterable, Hashable {
    case stack, plates

    var label: String {
        switch self {
        case .stack: "Pila de pesas"
        case .plates: "Discos"
        }
    }

    var firmwareProfile: Int { self == .stack ? kStackProfile : 0 }

    var placementNote: String {
        switch self {
        case .stack: "Encima de la pila de pesas, pegado a la placa superior."
        case .plates: "En el brazo de la máquina, cerca del agarre."
        }
    }
}

extension Exercise {
    /// The board counts by the height of a stack or a bar (profiles 2 and 3).
    var followsHeight: Bool { profileFollowsHeight(firmwareProfile) }

    /// The sensor rides a weight stack, not a bar: profile 2 on a machine or
    /// cable other than a Smith.
    var onWeightStack: Bool {
        firmwareProfile == kStackProfile && equipment != .barbell && !id.hasPrefix("smith-")
    }

    /// Machines and cables where the sensor goes on the equipment. Smith
    /// machines are a guided bar, so they keep the bar placement.
    var canChooseLoad: Bool {
        (equipment == .machine || equipment == .cable) && placement == .equipment && !id.hasPrefix("smith-")
    }

    /// Nil when the exercise has no stack or plates to choose from.
    var load: MachineLoad? {
        guard canChooseLoad else { return nil }
        return firmwareProfile == kStackProfile ? .stack : .plates
    }

    /// The same exercise loaded the other way: counting profile and sensor
    /// note follow the load.
    func withLoad(_ load: MachineLoad) -> Exercise {
        guard canChooseLoad, load != self.load else { return self }
        return Exercise(id: id, name: name, muscleGroup: muscleGroup, equipment: equipment,
                        placement: placement, placementNote: load.placementNote,
                        firmwareProfile: load.firmwareProfile, thresholdDegrees: thresholdDegrees,
                        tutorialSteps: tutorialSteps, tutorialSeconds: tutorialSeconds,
                        videoUrl: videoUrl, active: active)
    }
}

/// One exercise inside a routine, with its plan.
struct RoutineItem: Hashable {
    let exerciseId: String
    var sets = 3
    var reps = 10
    /// Nil means body weight.
    var weightKg: Double?
    var restSeconds = 90

    /// Exercises that can be done instead, with the same plan ("Elevaciones
    /// laterales en polea" when the machine is taken). In order, without the
    /// main one or repeats.
    var alternativeIds: [String] = [] {
        didSet { alternativeIds = Self.clean(alternativeIds, main: exerciseId) }
    }

    /// The main exercise first, then the alternatives.
    var optionIds: [String] { [exerciseId] + alternativeIds }

    static let maxAlternatives = 10

    private static func clean(_ ids: [String], main: String) -> [String] {
        var seen: Set<String> = [main]
        return Array(ids.filter { seen.insert($0).inserted }.prefix(maxAlternatives))
    }

    func toJSON() -> JSON {
        [
            "exerciseId": exerciseId,
            "sets": sets,
            "reps": reps,
            "weightKg": orNull(weightKg),
            "restSeconds": restSeconds,
            "alternativeIds": alternativeIds,
        ]
    }

    init(exerciseId: String, sets: Int = 3, reps: Int = 10, weightKg: Double? = nil, restSeconds: Int = 90,
         alternativeIds: [String] = []) {
        self.exerciseId = exerciseId
        self.sets = sets
        self.reps = reps
        self.weightKg = weightKg
        self.restSeconds = restSeconds
        self.alternativeIds = Self.clean(alternativeIds, main: exerciseId)
    }

    init(json j: JSON) throws {
        exerciseId = try require(jsonString(j["exerciseId"]), "exerciseId")
        sets = try require(jsonInt(j["sets"]), "sets")
        reps = try require(jsonInt(j["reps"]), "reps")
        weightKg = jsonDouble(j["weightKg"])
        restSeconds = try require(jsonInt(j["restSeconds"]), "restSeconds")
        // Absent in routines saved before alternatives existed.
        alternativeIds = Self.clean((j["alternativeIds"] as? [Any])?.compactMap { $0 as? String } ?? [],
                                    main: exerciseId)
    }
}

struct Routine: Hashable, Identifiable {
    var id: String
    var name: String
    var items: [RoutineItem]

    /// When it was last edited on a phone. If two phones edit the same routine
    /// offline, the later edit wins.
    var editedAt: Date?

    /// Rough length: about a minute per set (work plus setup), the planned
    /// rest, and five minutes to warm up and move between stations.
    var estimatedMinutes: Int {
        var seconds = 300
        for item in items {
            seconds += item.sets * (60 + item.restSeconds)
        }
        let minutes = Double(seconds) / 60
        return min(600, max(5, Int((minutes / 5).rounded()) * 5))
    }

    func toJSON() -> JSON {
        var j: JSON = [
            "id": id,
            "name": name,
            "items": items.map { $0.toJSON() },
        ]
        if let editedAt { j["editedAt"] = ISODate.string(editedAt) }
        return j
    }

    init(id: String, name: String, items: [RoutineItem], editedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.items = items
        self.editedAt = editedAt
    }

    init(json j: JSON) throws {
        id = try require(jsonString(j["id"]), "id")
        name = try require(jsonString(j["name"]), "name")
        items = try (try require(j["items"] as? [Any], "items")).map {
            try RoutineItem(json: try require($0 as? JSON, "item"))
        }
        editedAt = ISODate.parse(j["editedAt"])
    }
}

/// The movement of one set, recorded from the board's packets: the height of
/// the weight stack, or the angle of the limb or bar. Drawn on the summary.
struct SetTrace: Hashable {
    enum Kind: String {
        /// Weight stack: height above where the set started, in cm.
        case height
        /// Any other exercise: the angle the board reports, in degrees.
        case angle
    }

    let kind: Kind
    let sampleHz: Int
    let values: [Double]

    var seconds: Double { Double(max(0, values.count - 1)) / Double(sampleHz) }

    func toJSON() -> JSON { ["kind": kind.rawValue, "sampleHz": sampleHz, "values": values] }

    init(kind: Kind, sampleHz: Int, values: [Double]) {
        self.kind = kind
        self.sampleHz = sampleHz
        self.values = values
    }

    init(json j: JSON) throws {
        kind = try require(Kind(rawValue: jsonString(j["kind"]) ?? ""), "kind")
        sampleHz = try require(jsonInt(j["sampleHz"]), "sampleHz")
        values = (j["values"] as? [Any] ?? []).compactMap(jsonDouble)
    }
}

/// One finished set, as counted by the sensor.
struct SetRecord: Hashable {
    let exerciseId: String
    /// Renumbered when an earlier set is deleted on the summary.
    var setNumber: Int
    var reps: Int
    var targetReps: Int?
    var weightKg: Double?

    /// Mean concentric velocity in m/s. Nil when the sensor did not report it.
    var meanVelocity: Double?

    /// Largest angle reached during the set.
    var rangeDegrees: Double?
    /// Moves with the session when its date is corrected.
    var completedAt: Date

    /// Nil for sets recorded before the app kept it.
    var trace: SetTrace?

    var volumeKg: Double { (weightKg ?? 0) * Double(reps) }

    func toJSON() -> JSON {
        [
            "exerciseId": exerciseId,
            "setNumber": setNumber,
            "reps": reps,
            "targetReps": orNull(targetReps),
            "weightKg": orNull(weightKg),
            "meanVelocity": orNull(meanVelocity),
            "rangeDegrees": orNull(rangeDegrees),
            "completedAt": ISODate.string(completedAt),
            "trace": orNull(trace?.toJSON()),
        ]
    }

    init(exerciseId: String, setNumber: Int, reps: Int, targetReps: Int?, weightKg: Double?,
         meanVelocity: Double?, rangeDegrees: Double?, completedAt: Date, trace: SetTrace? = nil) {
        self.exerciseId = exerciseId
        self.setNumber = setNumber
        self.reps = reps
        self.targetReps = targetReps
        self.weightKg = weightKg
        self.meanVelocity = meanVelocity
        self.rangeDegrees = rangeDegrees
        self.completedAt = completedAt
        self.trace = trace
    }

    init(json j: JSON) throws {
        exerciseId = try require(jsonString(j["exerciseId"]), "exerciseId")
        setNumber = try require(jsonInt(j["setNumber"]), "setNumber")
        reps = try require(jsonInt(j["reps"]), "reps")
        targetReps = jsonInt(j["targetReps"])
        weightKg = jsonDouble(j["weightKg"])
        meanVelocity = jsonDouble(j["meanVelocity"])
        rangeDegrees = jsonDouble(j["rangeDegrees"])
        completedAt = try require(ISODate.parse(j["completedAt"]), "completedAt")
        trace = try (j["trace"] as? JSON).map { try SetTrace(json: $0) }
    }
}

struct WorkoutSession: Hashable, Identifiable {
    let id: String
    var routineId: String?

    /// Routine name, or "Entrenamiento libre".
    let title: String
    /// Can be corrected from the summary (a session added by hand on the
    /// wrong day).
    var startedAt: Date
    var endedAt: Date
    var sets: [SetRecord]

    /// How many exercises the routine had, for "5 de 5 ejercicios".
    var plannedExercises = 0

    /// Last correction from Historial. If two phones correct it offline, the
    /// later one wins.
    var editedAt: Date?

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    var volumeKg: Double { sets.reduce(0) { $0 + $1.volumeKg } }

    /// The same session starting at `start` and lasting `minutes`. The sets
    /// move with it, keeping their order and their distance from the start
    /// (squeezed if the session got shorter).
    func rescheduled(start: Date, minutes: Int) -> WorkoutSession {
        var moved = self
        let end = start.addingTimeInterval(Double(minutes) * 60)
        moved.startedAt = start
        moved.endedAt = end
        let oldLength = max(1, duration)
        let newLength = end.timeIntervalSince(start)
        for i in moved.sets.indices {
            let offset = min(max(0, sets[i].completedAt.timeIntervalSince(startedAt)), oldLength)
            moved.sets[i].completedAt = start.addingTimeInterval(min(offset, newLength))
        }
        return moved
    }

    /// Exercise ids in the order they were first done.
    var exerciseIds: [String] {
        var seen: [String] = []
        for s in sets where !seen.contains(s.exerciseId) {
            seen.append(s.exerciseId)
        }
        return seen
    }

    func toJSON() -> JSON {
        var j: JSON = [
            "id": id,
            "routineId": orNull(routineId),
            "title": title,
            "startedAt": ISODate.string(startedAt),
            "endedAt": ISODate.string(endedAt),
            "plannedExercises": plannedExercises,
            "sets": sets.map { $0.toJSON() },
        ]
        if let editedAt { j["editedAt"] = ISODate.string(editedAt) }
        return j
    }

    init(id: String, routineId: String?, title: String, startedAt: Date, endedAt: Date,
         sets: [SetRecord], plannedExercises: Int = 0) {
        self.id = id
        self.routineId = routineId
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sets = sets
        self.plannedExercises = plannedExercises
    }

    init(json j: JSON) throws {
        id = try require(jsonString(j["id"]), "id")
        routineId = jsonString(j["routineId"])
        title = try require(jsonString(j["title"]), "title")
        startedAt = try require(ISODate.parse(j["startedAt"]), "startedAt")
        endedAt = try require(ISODate.parse(j["endedAt"]), "endedAt")
        plannedExercises = jsonInt(j["plannedExercises"]) ?? 0
        editedAt = ISODate.parse(j["editedAt"])
        sets = try (try require(j["sets"] as? [Any], "sets")).map {
            try SetRecord(json: try require($0 as? JSON, "set"))
        }
    }
}

struct UserProfile: Hashable {
    let id: String
    let name: String
    let email: String

    func toJSON() -> JSON { ["id": id, "name": name, "email": email] }

    init(id: String, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }

    init(json j: JSON) throws {
        id = try require(jsonString(j["id"]), "id")
        name = try require(jsonString(j["name"]), "name")
        email = try require(jsonString(j["email"]), "email")
    }
}

func newId() -> String { UUID().uuidString.lowercased() }

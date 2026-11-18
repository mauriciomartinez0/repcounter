// Developer mode: a recording of one real set, to compare what the board
// counted with what was really done.
//
// Each set becomes one JSON file in Documents/captures, which is shared with
// the computer (UIFileSharingEnabled): rep_counter_ble/dev/pull_captures.sh
// copies them over USB and analyze_capture.py takes them apart. A file holds:
//
//   - raw: the accelerometer as the board read it, 104 Hz, x y z interleaved
//     in counts (rawGPerCount g each), starting rawStart seconds into the
//     capture; lost packets are filled with -32768. Only with firmware that
//     streams it.
//   - states: every state packet, [t, count, value, profile, flags], t in
//     seconds since the capture started; value is the angle, or the stack
//     speed in cm/s on profile 2; flags: 1 going up, 2 calibrated.
//   - events: [t, name, value]: calibrating, counting, rep, sensitivity,
//     restart, finish, analysis, review, recorded.
//   - the counts: live, what the analysis found, what was recorded, and
//     trueReps, what the user says they really did.

import Foundation
import Observation

struct DevCapture: Identifiable {
    var id: String
    var createdAt: Date
    var exerciseId: String
    var exerciseName: String
    var firmwareProfile: Int
    var setNumber: Int
    var targetReps: Int?
    var sensitivity: Int
    var liveReps = 0
    var analysisFound: Int?
    var recordedReps = 0
    var trueReps: Int?
    var notes = ""
    var duration: Double = 0
    var rawSampleHz = 104
    var rawGPerCount = 0.122 / 1000
    var raw: [Int16] = []
    var rawStart: Double = 0
    var rawPackets = 0
    var rawLostPackets = 0
    var states: [[Double]] = []
    var events: [(Double, String, Double)] = []

    var rawSamples: Int { raw.count / 3 }

    func toJSON() -> JSON {
        [
            "version": 1,
            "id": id,
            "createdAt": ISODate.string(createdAt),
            "app": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "exerciseId": exerciseId,
            "exerciseName": exerciseName,
            "firmwareProfile": firmwareProfile,
            "setNumber": setNumber,
            "targetReps": orNull(targetReps),
            "sensitivity": sensitivity,
            "liveReps": liveReps,
            "analysisFound": orNull(analysisFound),
            "recordedReps": recordedReps,
            "trueReps": orNull(trueReps),
            "notes": notes,
            "duration": duration,
            "rawSampleHz": rawSampleHz,
            "rawGPerCount": rawGPerCount,
            "rawStart": rawStart,
            "rawPackets": rawPackets,
            "rawLostPackets": rawLostPackets,
            "raw": raw.map { Int($0) },
            "states": states,
            "events": events.map { [$0.0, $0.1, $0.2] as [Any] },
        ]
    }

    init(id: String, createdAt: Date, exerciseId: String, exerciseName: String, firmwareProfile: Int,
         setNumber: Int, targetReps: Int?, sensitivity: Int) {
        self.id = id
        self.createdAt = createdAt
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.firmwareProfile = firmwareProfile
        self.setNumber = setNumber
        self.targetReps = targetReps
        self.sensitivity = sensitivity
    }

    init(json j: JSON) throws {
        id = try require(jsonString(j["id"]), "id")
        createdAt = try require(ISODate.parse(j["createdAt"]), "createdAt")
        exerciseId = jsonString(j["exerciseId"]) ?? ""
        exerciseName = jsonString(j["exerciseName"]) ?? exerciseId
        firmwareProfile = jsonInt(j["firmwareProfile"]) ?? 0
        setNumber = jsonInt(j["setNumber"]) ?? 1
        targetReps = jsonInt(j["targetReps"])
        sensitivity = jsonInt(j["sensitivity"]) ?? 50
        liveReps = jsonInt(j["liveReps"]) ?? 0
        analysisFound = jsonInt(j["analysisFound"])
        recordedReps = jsonInt(j["recordedReps"]) ?? 0
        trueReps = jsonInt(j["trueReps"])
        notes = jsonString(j["notes"]) ?? ""
        duration = jsonDouble(j["duration"]) ?? 0
        rawSampleHz = jsonInt(j["rawSampleHz"]) ?? 104
        rawGPerCount = jsonDouble(j["rawGPerCount"]) ?? 0.122 / 1000
        rawStart = jsonDouble(j["rawStart"]) ?? 0
        rawPackets = jsonInt(j["rawPackets"]) ?? 0
        rawLostPackets = jsonInt(j["rawLostPackets"]) ?? 0
        raw = (j["raw"] as? [Any] ?? []).compactMap { jsonInt($0).map { Int16(clamping: $0) } }
        states = (j["states"] as? [Any] ?? []).compactMap { ($0 as? [Any])?.compactMap(jsonDouble) }
        events = (j["events"] as? [Any] ?? []).compactMap { item in
            guard let e = item as? [Any], e.count >= 3, let t = jsonDouble(e[0]), let name = e[1] as? String
            else { return nil }
            return (t, name, jsonDouble(e[2]) ?? 0)
        }
    }
}

/// The capture files. Loaded on demand: they hold thousands of samples.
@MainActor
@Observable
final class DevCaptureStore {
    static let shared = DevCaptureStore()

    /// Newest first, without their samples (`raw` and `states` empty).
    private(set) var summaries: [DevCapture] = []

    nonisolated static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("captures", isDirectory: true)
    }

    nonisolated static func file(_ id: String) -> URL { folder.appendingPathComponent("\(id).json") }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil))
            ?? []
        summaries = files.filter { $0.pathExtension == "json" }
            .compactMap { url -> DevCapture? in
                guard var c = Self.read(url) else { return nil }
                c.raw = []
                c.states = []
                return c
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func load(_ id: String) -> DevCapture? { Self.read(Self.file(id)) }

    private nonisolated static func read(_ url: URL) -> DevCapture? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? JSON
        else { return nil }
        return try? DevCapture(json: json)
    }

    func save(_ capture: DevCapture) {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: capture.toJSON()) {
            try? data.write(to: Self.file(capture.id), options: .atomic)
        }
        reload()
    }

    /// What the user says they really did, and notes.
    func update(_ id: String, trueReps: Int?, notes: String? = nil) {
        guard var c = load(id) else { return }
        c.trueReps = trueReps
        if let notes { c.notes = notes }
        save(c)
    }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: Self.file(id))
        reload()
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: Self.folder)
        reload()
    }
}

/// Records one set at a time while a workout runs in developer mode. The
/// workout tells it what happens; the packets come straight from the sensor.
@MainActor
final class DevCaptureRecorder {
    private let sensor: SensorService
    private var current: DevCapture?
    private var startedAt = Date()
    private var lastSequence: UInt16?

    init(sensor: SensorService) {
        self.sensor = sensor
        sensor.onStatePacket = { [weak self] state in self?.state(state) }
        sensor.onRawPacket = { [weak self] sequence, samples in self?.raw(sequence, samples) }
        sensor.setRawStream(true)
    }

    private var t: Double { Date().timeIntervalSince(startedAt) }

    /// A new set starts recording (calibration included, when there is one).
    func begin(_ exercise: Exercise, setNumber: Int, targetReps: Int?, sensitivity: Int) {
        startedAt = Date()
        lastSequence = nil
        current = DevCapture(
            id: Self.fileId(startedAt, exercise.id, setNumber), createdAt: startedAt,
            exerciseId: exercise.id, exerciseName: exercise.name, firmwareProfile: exercise.firmwareProfile,
            setNumber: setNumber, targetReps: targetReps, sensitivity: sensitivity)
    }

    func event(_ name: String, _ value: Double = 0) {
        current?.events.append((t, name, value))
    }

    /// The set was recorded: saves the file. Returns its id.
    @discardableResult
    func finish(live: Int, analysisFound: Int?, recorded: Int) -> String? {
        guard var c = current else { return nil }
        current = nil
        c.events.append((t, "recorded", Double(recorded)))
        c.duration = t
        c.liveReps = live
        c.analysisFound = analysisFound
        c.recordedReps = recorded
        DevCaptureStore.shared.save(c)
        return c.id
    }

    /// The workout ended or left: nothing more is recorded.
    func stop() {
        current = nil
        sensor.setRawStream(false)
        sensor.onStatePacket = nil
        sensor.onRawPacket = nil
    }

    private func state(_ s: DeviceState) {
        let flags = (s.inUpPhase ? 1.0 : 0) + (s.referenceCaptured ? 2.0 : 0)
        current?.states.append([(t * 1000).rounded() / 1000, Double(s.repCount),
                                s.angleDegrees, Double(s.exerciseId), flags])
    }

    private func raw(_ sequence: UInt16, _ samples: [Int16]) {
        guard current != nil else { return }
        if let last = lastSequence {
            let gap = Int(sequence &- last) - 1
            if gap > 0 && gap < 1000 {
                current?.rawLostPackets += gap
                // Keep the timing: a lost packet leaves its samples as gaps
                // the analysis can see (Int16.min) instead of closing them up.
                current?.raw.append(contentsOf: Array(repeating: Int16.min, count: gap * samples.count))
            }
        }
        if lastSequence == nil {
            // The readings were taken a moment before the packet arrived.
            current?.rawStart = max(0, t - Double(samples.count / 3) / 104)
        }
        lastSequence = sequence
        current?.rawPackets += 1
        current?.raw.append(contentsOf: samples)
    }

    private static func fileId(_ date: Date, _ exerciseId: String, _ set: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "\(f.string(from: date))_\(exerciseId)_s\(set)"
    }
}

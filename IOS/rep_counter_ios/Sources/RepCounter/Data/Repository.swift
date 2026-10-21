// The user's data from the API, usable without network.
//
// Every change is applied to the local copy first (the screen updates right
// away, even in a gym with no signal) and queued in an "outbox". Sync pushes
// the outbox and then pulls what changed on the server, in the order the API
// expects (see rep_counter_api/README.md):
//
//   catalog → routines → sessions → favorites → pull routines → pull sessions
//   → pull favorites
//
// The API makes retries safe: ids are generated here and uploading the same
// session twice stores it once. So a change only leaves the outbox when the
// server confirmed it or refused it for good.

import Foundation
import Observation

enum SyncStatus { case idle, syncing, offline, error }

/// A change waiting to reach the server.
private final class Op {
    /// putRoutine, deleteRoutine, uploadSession, favorite.
    let type: String
    let id: String
    /// favorite: true to add, false to remove.
    let on: Bool?
    /// uploadSession: false while the summary can still correct it.
    var ready: Bool

    init(_ type: String, _ id: String, on: Bool? = nil, ready: Bool = true) {
        self.type = type
        self.id = id
        self.on = on
        self.ready = ready
    }

    func toJSON() -> JSON { ["type": type, "id": id, "on": orNull(on), "ready": ready] }

    static func fromJSON(_ j: JSON) -> Op? {
        guard let type = jsonString(j["type"]), let id = jsonString(j["id"]) else { return nil }
        return Op(type, id, on: jsonBool(j["on"]), ready: jsonBool(j["ready"]) ?? true)
    }
}

/// Thrown when the user changed mid-sync; the rest of that sync is dropped.
private struct UserChanged: Error {}

@MainActor
@Observable
final class GymRepository {
    private static let batchSize = 50
    private static let catalogFile = "catalog.json"

    @ObservationIgnored let api: ApiClient
    @ObservationIgnored let store: FileLocalStore
    @ObservationIgnored var debounce: Duration = .milliseconds(800)
    @ObservationIgnored var retryEvery: Duration = .seconds(30)

    private var userId: String?
    private(set) var exercises: [Exercise] = seedExercises
    @ObservationIgnored private var catalogEtag: String?
    private(set) var routines: [Routine] = []
    /// Newest first.
    private(set) var sessions: [WorkoutSession] = []
    private(set) var favoriteIds: Set<String> = []
    private var outbox: [Op] = []
    @ObservationIgnored private var routinesCursor: String?
    @ObservationIgnored private var sessionsCursor: String?

    private(set) var syncStatus: SyncStatus = .idle
    /// Changes made on this phone that the server does not have yet.
    var pendingChanges: Int { outbox.count }
    private(set) var lastSyncedAt: Date?
    /// Something the server refused for good (shown in Ajustes).
    private(set) var syncIssue: String?

    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var again = false
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    init(api: ApiClient, store: FileLocalStore) {
        self.api = api
        self.store = store
    }

    // MARK: - Local copy

    private func file(_ name: String) -> String { "users/\(userId ?? "")/\(name).json" }

    private func readJSON(_ name: String) -> Any? {
        guard let raw = store.read(name), let data = raw.data(using: .utf8) else { return nil }
        // A damaged file is refetched from the server.
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private func writeJSON(_ name: String, _ value: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8)
        else { return }
        store.write(name, text)
    }

    func load() {
        // Catalog shared by all users. Until the first download, the copy that
        // ships with the app.
        if let catalog = readJSON(Self.catalogFile) as? JSON,
           let list = catalog["exercises"] as? [Any] {
            let parsed = list.compactMap { ($0 as? JSON).flatMap { try? Exercise(json: $0) } }
            if !parsed.isEmpty {
                catalogEtag = jsonString(catalog["etag"])
                exercises = parsed
            }
        }
    }

    /// Loads the data of `userId` (nil when signed out).
    func switchUser(_ userId: String?) {
        guard userId != self.userId else { return }
        debounceTask?.cancel()
        retryTask?.cancel()
        self.userId = userId
        routines = []
        sessions = []
        favoriteIds = []
        outbox = []
        routinesCursor = nil
        sessionsCursor = nil
        syncIssue = nil
        lastSyncedAt = nil
        syncStatus = .idle

        guard userId != nil else { return }
        routines = (readJSON(file("routines")) as? [Any] ?? [])
            .compactMap { ($0 as? JSON).flatMap { try? Routine(json: $0) } }
        sessions = (readJSON(file("sessions")) as? [Any] ?? [])
            .compactMap { ($0 as? JSON).flatMap { try? WorkoutSession(json: $0) } }
        favoriteIds = Set((readJSON(file("favorites")) as? [Any] ?? []).compactMap { $0 as? String })
        outbox = (readJSON(file("outbox")) as? [Any] ?? [])
            .compactMap { ($0 as? JSON).flatMap(Op.fromJSON) }
        // The app closed before "Listo": those workouts are final now.
        for op in outbox { op.ready = true }
        if let cursors = readJSON(file("cursors")) as? JSON {
            routinesCursor = jsonString(cursors["routines"])
            sessionsCursor = jsonString(cursors["sessions"])
            lastSyncedAt = ISODate.parse(cursors["lastSyncedAt"])
        }
        Task { await sync() }
    }

    /// Deletes this phone's copy of the current user's data, pending changes
    /// included. Used when signing out.
    func discardUserData() {
        guard let userId else { return }
        switchUser(nil)
        store.deleteAll("users/\(userId)")
    }

    private func saveRoutines() { writeJSON(file("routines"), routines.map { $0.toJSON() }) }
    private func saveSessions() { writeJSON(file("sessions"), sessions.map { $0.toJSON() }) }
    private func saveFavorites() { writeJSON(file("favorites"), Array(favoriteIds)) }
    private func saveOutbox() { writeJSON(file("outbox"), outbox.map { $0.toJSON() }) }
    private func saveCursors() {
        writeJSON(file("cursors"), [
            "routines": orNull(routinesCursor),
            "sessions": orNull(sessionsCursor),
            "lastSyncedAt": orNull(lastSyncedAt.map(ISODate.string)),
        ])
    }

    // MARK: - Derived data

    func exercise(_ id: String) -> Exercise? { exercises.first { $0.id == id } }

    func routine(_ id: String) -> Routine? { routines.first { $0.id == id } }

    func duplicateRoutine(_ id: String) -> Routine {
        var copy = routine(id)!
        copy.id = ""
        copy.name = "\(copy.name) (copia)"
        return saveRoutine(copy)
    }

    /// Exercises done most recently, newest first.
    func recentExercises(limit: Int = 6) -> [Exercise] {
        var ids: [String] = []
        outer: for session in sessions {
            for set in session.sets.reversed() {
                if !ids.contains(set.exerciseId) { ids.append(set.exerciseId) }
                if ids.count >= limit { break outer }
            }
        }
        return ids.compactMap(exercise)
    }

    var favoriteExercises: [Exercise] { exercises.filter { favoriteIds.contains($0.id) } }

    /// Weight used the last time this exercise was done.
    func lastWeight(_ exerciseId: String) -> Double? {
        for session in sessions {
            for set in session.sets.reversed() where set.exerciseId == exerciseId && set.weightKg != nil {
                return set.weightKg
            }
        }
        return nil
    }

    /// The session of the same routine that came before `session`.
    func previousSession(_ session: WorkoutSession) -> WorkoutSession? {
        guard let routineId = session.routineId else { return nil }
        return sessions.first {
            $0.id != session.id && $0.routineId == routineId && $0.startedAt < session.startedAt
        }
    }

    /// Exercises that have at least one set with a velocity reading, most
    /// recently done first.
    func exercisesWithVelocity() -> [Exercise] {
        var ids: [String] = []
        for session in sessions {
            for set in session.sets where set.meanVelocity != nil && !ids.contains(set.exerciseId) {
                ids.append(set.exerciseId)
            }
        }
        return ids.compactMap(exercise)
    }

    /// Every session that included `exerciseId`, oldest first, paired with its
    /// sets of that exercise.
    func historyFor(_ exerciseId: String) -> [(WorkoutSession, [SetRecord])] {
        var result: [(WorkoutSession, [SetRecord])] = []
        for session in sessions.reversed() {
            let sets = session.sets.filter { $0.exerciseId == exerciseId }
            if !sets.isEmpty { result.append((session, sets)) }
        }
        return result
    }

    // MARK: - Changes made on this phone

    private func enqueue(_ op: Op, replaces: ((Op) -> Bool)? = nil) {
        if let replaces { outbox.removeAll(where: replaces) }
        outbox.append(op)
    }

    @discardableResult
    func saveRoutine(_ routine: Routine) -> Routine {
        var saved = routine
        if saved.id.isEmpty { saved.id = newId() }
        saved.editedAt = Date()
        replaceRoutine(saved)
        let id = saved.id
        enqueue(Op("putRoutine", id), replaces: { $0.type == "putRoutine" && $0.id == id })
        saveRoutines()
        saveOutbox()
        scheduleSync()
        return saved
    }

    func deleteRoutine(_ id: String) {
        routines.removeAll { $0.id == id }
        enqueue(Op("deleteRoutine", id), replaces: {
            ($0.type == "putRoutine" || $0.type == "deleteRoutine") && $0.id == id
        })
        saveRoutines()
        saveOutbox()
        scheduleSync()
    }

    /// Saves locally. The upload waits for `commitSession` so corrections on
    /// the summary go up together with the session.
    func saveSession(_ session: WorkoutSession) {
        guard userId != nil else { return }
        var all = sessions.filter { $0.id != session.id }
        all.insert(session, at: 0)
        all.sort { $0.startedAt > $1.startedAt }
        sessions = all
        let queued = outbox.contains { $0.type == "uploadSession" && $0.id == session.id }
        if !queued { enqueue(Op("uploadSession", session.id, ready: false)) }
        saveSessions()
        saveOutbox()
    }

    /// A finished workout can still be corrected on the summary; it is
    /// uploaded once the user taps "Listo".
    func commitSession(_ sessionId: String) {
        for op in outbox where op.type == "uploadSession" && op.id == sessionId {
            op.ready = true
        }
        saveOutbox()
        scheduleSync(immediately: true)
    }

    func toggleFavorite(_ exerciseId: String) {
        guard userId != nil else { return }
        let on = !favoriteIds.contains(exerciseId)
        if on { favoriteIds.insert(exerciseId) } else { favoriteIds.remove(exerciseId) }
        enqueue(Op("favorite", exerciseId, on: on), replaces: { $0.type == "favorite" && $0.id == exerciseId })
        saveFavorites()
        saveOutbox()
        scheduleSync()
    }

    // MARK: - Sync

    private func scheduleSync(immediately: Bool = false) {
        debounceTask?.cancel()
        let delay = immediately ? .zero : debounce
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    func sync() async {
        guard userId != nil else { return }
        if let running {
            // A change arrived mid-sync: run once more when this one ends.
            again = true
            await running.value
            return
        }
        let task = Task { await syncLoop() }
        running = task
        await task.value
        running = nil
    }

    private func syncLoop() async {
        repeat {
            again = false
            await syncOnce()
        } while again && syncStatus == .idle
    }

    private func syncOnce() async {
        guard let user = userId else { return }
        retryTask?.cancel()
        syncStatus = .syncing
        let check: () throws -> Void = { [weak self] in
            if self?.userId != user { throw UserChanged() }
        }

        do {
            try await pullCatalog()
            try check()
            try await pushRoutines(check)
            try await pushSessions(check)
            try await pushFavorites(check)
            try await pullRoutines(check)
            try await pullSessions(check)
            try await pullFavorites(check)
            syncStatus = .idle
            lastSyncedAt = Date()
            saveCursors()
        } catch is UserChanged {
            return
        } catch is NetworkError {
            syncStatus = .offline
            retryLater()
        } catch let error as ApiError {
            if userId != user { return }
            // 401 here means the session ended; AuthController already reacted.
            syncStatus = error.status == 401 ? .idle : .error
            if error.status != 401 {
                syncIssue = error.message
                retryLater()
            }
        } catch {
            if userId != user { return }
            syncStatus = .error
            retryLater()
        }
    }

    private func retryLater() {
        retryTask?.cancel()
        let delay = retryEvery
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    private func pullCatalog() async throws {
        var headers: [String: String] = [:]
        if let catalogEtag { headers["If-None-Match"] = "\"\(catalogEtag)\"" }
        let response = try await api.get("/exercises", headers: headers, auth: false)
        if response.status == 304 { return }
        let body = try require(response.body as? JSON, "catalog")
        let list = try require(body["exercises"] as? [Any], "exercises")
        let parsed = try list.map { try Exercise(json: try require($0 as? JSON, "exercise")) }
        catalogEtag = jsonString(body["version"])
        exercises = parsed
        writeJSON(Self.catalogFile, ["etag": orNull(catalogEtag), "exercises": list])
    }

    /// Takes `op` out of the queue and saves the queue right away, so a crash
    /// after a confirmed upload does not resend it (harmless, but wasteful).
    private func done(_ op: Op) {
        outbox.removeAll { $0 === op }
        saveOutbox()
    }

    private func pushRoutines(_ check: () throws -> Void) async throws {
        for op in outbox where op.type == "putRoutine" || op.type == "deleteRoutine" {
            try check()
            if op.type == "deleteRoutine" {
                do {
                    _ = try await api.delete("/routines/\(op.id)")
                } catch let error as ApiError where error.isPermanent {
                    // Already gone or refused for good: nothing to retry.
                }
                try check()
                done(op)
                continue
            }
            guard let local = routine(op.id) else {
                done(op)
                continue
            }
            do {
                let response = try await api.put("/routines/\(op.id)", body: [
                    "name": local.name,
                    "items": local.items.map { $0.toJSON() },
                    "editedAt": ISODate.string(local.editedAt ?? Date()),
                ] as JSON)
                try check()
                let result = response.body as? JSON ?? [:]
                if jsonBool(result["applied"]) == false, let remote = result["routine"] as? JSON {
                    // Another phone edited it later: keep that version.
                    replaceRoutine(try Routine(json: remote))
                }
            } catch let error as ApiError {
                try check()
                if error.status == 410 {
                    // Deleted on another phone.
                    routines.removeAll { $0.id == op.id }
                } else if error.isPermanent {
                    syncIssue = "No se pudo guardar la rutina \"\(local.name)\": \(error.message)"
                } else {
                    throw error
                }
            }
            done(op)
            saveRoutines()
        }
    }

    private func replaceRoutine(_ routine: Routine) {
        if let index = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[index] = routine
        } else {
            routines.append(routine)
        }
    }

    private func pushSessions(_ check: () throws -> Void) async throws {
        let ready = outbox.filter { $0.type == "uploadSession" && $0.ready }
        var i = 0
        while i < ready.count {
            let chunk = Array(ready[i..<min(i + Self.batchSize, ready.count)])
            i += Self.batchSize
            let byId = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let sendable = chunk.filter { byId[$0.id] != nil }
            for op in chunk where byId[op.id] == nil { done(op) }
            if sendable.isEmpty { continue }
            let response = try await api.post("/sessions/batch", body: [
                "sessions": sendable.map { byId[$0.id]!.toJSON() },
            ] as JSON)
            try check()
            let results = (response.body as? JSON)?["results"] as? [Any] ?? []
            for case let r as JSON in results {
                guard let op = sendable.first(where: { $0.id == jsonString(r["id"]) }) else { continue }
                if jsonString(r["status"]) == "rejected" {
                    let error = r["error"] as? JSON ?? [:]
                    let session = byId[op.id]!
                    let day = Calendar.current.component(.day, from: session.startedAt)
                    let month = Calendar.current.component(.month, from: session.startedAt)
                    syncIssue = "No se pudo guardar el entrenamiento \"\(session.title)\" del "
                        + "\(day)/\(month): \(jsonString(error["message"]) ?? "datos inválidos")"
                }
                done(op)
            }
        }
    }

    private func pushFavorites(_ check: () throws -> Void) async throws {
        for op in outbox where op.type == "favorite" {
            try check()
            do {
                if op.on == true {
                    _ = try await api.put("/favorites/\(op.id)")
                } else {
                    _ = try await api.delete("/favorites/\(op.id)")
                }
            } catch let error as ApiError where error.isPermanent {
                // Unknown exercise or similar: drop it.
            }
            try check()
            done(op)
        }
    }

    private func pendingRoutine(_ id: String) -> Bool {
        outbox.contains { ($0.type == "putRoutine" || $0.type == "deleteRoutine") && $0.id == id }
    }

    private func pullRoutines(_ check: () throws -> Void) async throws {
        var query: [String: String] = [:]
        if let routinesCursor { query["since"] = routinesCursor }
        let response = try await api.get("/routines", query: query)
        try check()
        let body = try require(response.body as? JSON, "routines")
        let incoming = (body["routines"] as? [Any] ?? []).compactMap { $0 as? JSON }
        if routinesCursor == nil {
            // First sync on this phone: the server list, plus local routines that
            // have not reached it yet.
            let local = Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let incomingIds = Set(incoming.compactMap { jsonString($0["id"]) })
            var merged: [Routine] = []
            for r in incoming {
                let id = jsonString(r["id"]) ?? ""
                if pendingRoutine(id), let mine = local[id] {
                    merged.append(mine)
                } else {
                    merged.append(try Routine(json: r))
                }
            }
            for r in routines where pendingRoutine(r.id) && !incomingIds.contains(r.id) {
                merged.append(r)
            }
            routines = merged
        } else {
            for r in incoming {
                let id = jsonString(r["id"]) ?? ""
                if pendingRoutine(id) { continue } // Local change goes up first.
                if r["deletedAt"] != nil && !(r["deletedAt"] is NSNull) {
                    routines.removeAll { $0.id == id }
                } else {
                    replaceRoutine(try Routine(json: r))
                }
            }
        }
        routinesCursor = try require(jsonString(body["serverTime"]), "serverTime")
        saveRoutines()
    }

    private func pullSessions(_ check: () throws -> Void) async throws {
        var since = sessionsCursor ?? "1970-01-01T00:00:00Z"
        var changed = false
        while true {
            let response = try await api.get("/sessions/sync", query: ["since": since])
            try check()
            let body = try require(response.body as? JSON, "sessions")
            let incoming = try (body["sessions"] as? [Any] ?? []).map {
                try WorkoutSession(json: try require($0 as? JSON, "session"))
            }
            if !incoming.isEmpty {
                let ids = Set(incoming.map(\.id))
                var all = incoming + sessions.filter { !ids.contains($0.id) }
                all.sort { $0.startedAt > $1.startedAt }
                sessions = all
                changed = true
            }
            since = try require(jsonString(body["serverTime"]), "serverTime")
            if jsonBool(body["hasMore"]) != true { break }
        }
        sessionsCursor = since
        if changed { saveSessions() }
    }

    private func pullFavorites(_ check: () throws -> Void) async throws {
        let response = try await api.get("/favorites")
        try check()
        var server = Set((response.body as? [Any] ?? []).compactMap { $0 as? String })
        // Changes still in the queue win over the server list.
        for op in outbox where op.type == "favorite" {
            if op.on == true { server.insert(op.id) } else { server.remove(op.id) }
        }
        if server != favoriteIds {
            favoriteIds = server
            saveFavorites()
        }
    }
}

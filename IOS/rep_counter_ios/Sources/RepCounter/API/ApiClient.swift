// HTTP access to the Rep Counter API.
//
// Every request carries the access token. When it expires the client trades
// the refresh token for a new pair once and repeats the request, so screens
// never deal with tokens. If the refresh token is no longer valid the session
// is over and `onSessionExpired` fires.

import Foundation
import Security

/// An error the API answered with. `message` is in Spanish and can be shown
/// to the user as is.
struct ApiError: Error {
    let status: Int
    let code: String
    let message: String
    var details: JSON = [:]

    /// Retrying the same request later will not help (validation, conflict…).
    var isPermanent: Bool {
        status >= 400 && status < 500 && status != 401 && status != 408 && status != 429
    }
}

/// No answer from the server: no internet, timeout, DNS, TLS. Worth retrying.
struct NetworkError: Error {
    var cause: Error?
    var message: String { "Sin conexión con el servidor. Revisa tu internet." }
}

struct Tokens {
    let access: String
    let refresh: String
    let accessExpiresAt: Date

    static func fromAuthResponse(_ json: JSON, now: Date) throws -> Tokens {
        Tokens(
            access: try require(jsonString(json["accessToken"]), "accessToken"),
            refresh: try require(jsonString(json["refreshToken"]), "refreshToken"),
            accessExpiresAt: now.addingTimeInterval(
                Double(try require(jsonInt(json["expiresIn"]), "expiresIn")))
        )
    }

    func toJSON() -> JSON {
        ["access": access, "refresh": refresh, "accessExpiresAt": ISODate.string(accessExpiresAt)]
    }

    init(access: String, refresh: String, accessExpiresAt: Date) {
        self.access = access
        self.refresh = refresh
        self.accessExpiresAt = accessExpiresAt
    }

    init(json j: JSON) throws {
        access = try require(jsonString(j["access"]), "access")
        refresh = try require(jsonString(j["refresh"]), "refresh")
        accessExpiresAt = try require(ISODate.parse(j["accessExpiresAt"]), "accessExpiresAt")
    }
}

/// iOS Keychain. Tokens never go to UserDefaults.
final class KeychainTokenStore {
    private let service = "com.mauromm.repcounter"
    private let account = "auth.tokens"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() -> Tokens? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        do {
            let json = try require(try JSONSerialization.jsonObject(with: data) as? JSON, "tokens")
            return try Tokens(json: json)
        } catch {
            // Corrupted or unreadable after a restore: start signed out.
            clear()
            return nil
        }
    }

    func write(_ tokens: Tokens) {
        guard let data = try? JSONSerialization.data(withJSONObject: tokens.toJSON()) else { return }
        clear()
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

struct ApiResponse {
    let status: Int
    let body: Any?
    let headers: [String: String]
}

@MainActor
final class ApiClient {
    let tokens: KeychainTokenStore
    let timeout: TimeInterval = 20

    /// Called when the refresh token was rejected: the user must sign in again.
    var onSessionExpired: (() -> Void)?

    private let base: URL
    private let session: URLSession
    private var refreshing: Task<Bool, Never>?

    init(baseUrl: String, tokens: KeychainTokenStore) {
        base = URL(string: baseUrl.hasSuffix("/") ? baseUrl : baseUrl + "/")!
        self.tokens = tokens
        let config = URLSessionConfiguration.ephemeral
        // The catalog uses its own ETag; no HTTP cache in between.
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = timeout
        session = URLSession(configuration: config)
    }

    func uri(_ path: String, _ query: [String: String]? = nil) -> URL {
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var components = URLComponents(
            url: URL(string: relative, relativeTo: base)!.absoluteURL, resolvingAgainstBaseURL: false)!
        if let query, !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    func get(_ path: String, query: [String: String]? = nil, headers: [String: String]? = nil,
             auth: Bool = true) async throws -> ApiResponse {
        try await send("GET", path, query: query, headers: headers, auth: auth)
    }

    func post(_ path: String, body: Any? = nil, auth: Bool = true) async throws -> ApiResponse {
        try await send("POST", path, body: body, auth: auth)
    }

    func put(_ path: String, body: Any? = nil) async throws -> ApiResponse {
        try await send("PUT", path, body: body)
    }

    func delete(_ path: String, body: Any? = nil) async throws -> ApiResponse {
        try await send("DELETE", path, body: body)
    }

    /// Saves the tokens of a login or registration response.
    func storeAuthResponse(_ json: JSON) throws {
        tokens.write(try Tokens.fromAuthResponse(json, now: Date()))
    }

    func send(_ method: String, _ path: String, body: Any? = nil, query: [String: String]? = nil,
              headers: [String: String]? = nil, auth: Bool = true) async throws -> ApiResponse {
        if auth, let current = tokens.read(),
           Date() > current.accessExpiresAt.addingTimeInterval(-30) {
            // Renew a little before expiry instead of waiting for the 401.
            _ = await refresh()
        }
        var (data, response) = try await raw(method, path, body, query, headers, auth)
        if response.statusCode == 401, auth, await refresh() {
            (data, response) = try await raw(method, path, body, query, headers, auth)
        }
        return try decode(data, response)
    }

    private func raw(_ method: String, _ path: String, _ body: Any?, _ query: [String: String]?,
                     _ extraHeaders: [String: String]?, _ auth: Bool) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: uri(path, query), timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        if auth, let current = tokens.read() {
            request.setValue("Bearer \(current.access)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in extraHeaders ?? [:] {
            request.setValue(value, forHTTPHeaderField: key)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw NetworkError() }
            return (data, http)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError(cause: error)
        }
    }

    private func decode(_ data: Data, _ response: HTTPURLResponse) throws -> ApiResponse {
        var body: Any?
        if !data.isEmpty {
            body = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        }
        let status = response.statusCode
        if status >= 400 {
            let error = (body as? JSON)?["error"] as? JSON ?? [:]
            throw ApiError(
                status: status,
                code: jsonString(error["code"]) ?? "http_\(status)",
                message: jsonString(error["message"]) ?? (status >= 500
                    ? "El servidor tuvo un problema. Intenta de nuevo en un momento."
                    : "No se pudo completar la acción."),
                details: error
            )
        }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key.lowercased()] = value }
        }
        return ApiResponse(status: status, body: body, headers: headers)
    }

    /// Trades the refresh token for a new pair. Concurrent callers share one
    /// attempt, since each refresh token works only once.
    private func refresh() async -> Bool {
        if let refreshing { return await refreshing.value }
        let task = Task { await doRefresh() }
        refreshing = task
        let result = await task.value
        refreshing = nil
        return result
    }

    private func doRefresh() async -> Bool {
        guard let current = tokens.read() else { return false }
        do {
            let (data, response) = try await raw(
                "POST", "/auth/refresh", ["refreshToken": current.refresh], nil, nil, false)
            let body = try require(try decode(data, response).body as? JSON, "refresh")
            tokens.write(try Tokens.fromAuthResponse(body, now: Date()))
            return true
        } catch let error as ApiError {
            if error.status == 401 {
                tokens.clear()
                onSessionExpired?()
            }
            return false
        } catch {
            return false
        }
    }
}

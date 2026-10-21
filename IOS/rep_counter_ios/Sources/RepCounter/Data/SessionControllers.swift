// Account and preferences.
//
// `AuthController` signs in against the API. Tokens live in the Keychain
// (see ApiClient.swift); the profile is also cached in UserDefaults so the
// app opens signed in without network.

import Foundation
import Observation

struct AuthError: Error {
    let message: String
}

@MainActor
@Observable
final class AuthController {
    private static let kUser = "auth.user"

    @ObservationIgnored let api: ApiClient
    @ObservationIgnored private let prefs = UserDefaults.standard

    /// The repository follows the signed-in user.
    @ObservationIgnored var onUserChanged: ((String?) -> Void)?

    private(set) var user: UserProfile?

    /// True when the server ended the session (refresh token rejected), so
    /// the login screen can say why.
    var sessionExpired = false

    var signedIn: Bool { user != nil }

    init(api: ApiClient) {
        self.api = api
        api.onSessionExpired = { [weak self] in self?.expired() }
    }

    func load() {
        let tokens = api.tokens.read()
        if tokens != nil, let raw = prefs.string(forKey: Self.kUser),
           let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? JSON {
            // A profile from an older version without id stays signed out.
            user = try? UserProfile(json: json)
        }
        if user == nil { forget() }
    }

    /// Picks up a name change made on another phone. Silent when offline.
    func refreshProfile() async {
        guard signedIn else { return }
        do {
            let response = try await api.get("/me")
            if let json = response.body as? JSON, let profile = try? UserProfile(json: json) {
                setUser(profile)
            }
        } catch {
            // Offline: keep the cached profile. A rejected session already
            // went through expired().
        }
    }

    private func validate(_ email: String, _ password: String, newPassword: Bool = false) throws {
        let pattern = #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#
        if email.trimmed.range(of: pattern, options: .regularExpression) == nil {
            throw AuthError(message: "Escribe un correo válido.")
        }
        if password.isEmpty {
            throw AuthError(message: "Escribe tu contraseña.")
        }
        if newPassword && password.count < 8 {
            throw AuthError(message: "La contraseña debe tener al menos 8 caracteres.")
        }
    }

    func signIn(_ email: String, _ password: String) async throws {
        try validate(email, password)
        try await authenticate("/auth/login", ["email": email.trimmed, "password": password])
    }

    func signUp(_ name: String, _ email: String, _ password: String) async throws {
        if name.trimmed.isEmpty {
            throw AuthError(message: "Escribe tu nombre.")
        }
        try validate(email, password, newPassword: true)
        try await authenticate("/auth/register", [
            "name": name.trimmed,
            "email": email.trimmed,
            "password": password,
        ])
    }

    func signInWithGoogle() async throws {
        // Needs Google Sign-In on the phone and GOOGLE_CLIENT_IDS on the
        // server; the API already accepts the ID token at /auth/google.
        throw AuthError(message: "El acceso con Google todavía no está disponible.")
    }

    private func authenticate(_ path: String, _ body: JSON) async throws {
        do {
            let response = try await api.post(path, body: body, auth: false)
            let json = try require(response.body as? JSON, "body")
            try api.storeAuthResponse(json)
            sessionExpired = false
            setUser(try UserProfile(json: try require(json["user"] as? JSON, "user")))
        } catch let error as ApiError {
            throw AuthError(message: error.message)
        } catch let error as NetworkError {
            throw AuthError(message: error.message)
        } catch is DecodeError {
            throw AuthError(message: "No se pudo completar la acción.")
        }
    }

    /// Ends the session here and on the server. Works offline too: the server
    /// token then simply expires on its own.
    func signOut() async {
        if let tokens = api.tokens.read() {
            _ = try? await api.post("/auth/logout", body: ["refreshToken": tokens.refresh], auth: false)
        }
        forget()
    }

    private func expired() {
        guard user != nil else { return }
        sessionExpired = true
        forget()
    }

    private func forget() {
        let had = user != nil
        user = nil
        api.tokens.clear()
        prefs.removeObject(forKey: Self.kUser)
        if had { onUserChanged?(nil) }
    }

    private func setUser(_ profile: UserProfile) {
        let changed = profile.id != user?.id
        user = profile
        if let data = try? JSONSerialization.data(withJSONObject: profile.toJSON()) {
            prefs.set(String(data: data, encoding: .utf8), forKey: Self.kUser)
        }
        if changed { onUserChanged?(profile.id) }
    }
}

@MainActor
@Observable
final class SettingsController {
    private static let kDark = "settings.dark"

    private(set) var darkMode = false

    func load() {
        darkMode = UserDefaults.standard.bool(forKey: Self.kDark)
    }

    func setDarkMode(_ value: Bool) {
        darkMode = value
        UserDefaults.standard.set(value, forKey: Self.kDark)
    }

    // How far the weight stack rises when the user takes the handle, per
    // exercise: it depends on the machine, and stays on this phone.
    private static let kGripLift = "settings.gripLift."

    private var gripLift: [String: Int] = [:]

    func gripLiftCm(_ exerciseId: String) -> Int {
        gripLift[exerciseId] ?? UserDefaults.standard.integer(forKey: Self.kGripLift + exerciseId)
    }

    func setGripLiftCm(_ exerciseId: String, _ cm: Int) {
        gripLift[exerciseId] = cm
        UserDefaults.standard.set(cm, forKey: Self.kGripLift + exerciseId)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// Rep counter: connects to the XIAO nRF52840 Sense over BLE, organizes the
// workout in routines, and keeps the history on the Rep Counter API.
// SwiftUI port of the Flutter app in rep_counter_app/.

import SwiftUI

enum AppConfig {
    /// Base URL of the Rep Counter API (Info.plist APIBaseURL).
    static var apiBaseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? "").trimmed
    }

    /// Use the fake sensor instead of Bluetooth (testing without the board).
    static var simulateSensor: Bool {
        Bundle.main.object(forInfoDictionaryKey: "SensorSimulated") as? Bool ?? false
    }

    /// Why the build cannot run, or nil if the configuration is usable.
    static func problem(_ baseUrl: String, release: Bool) -> String? {
        if baseUrl.isEmpty {
            return "Falta APIBaseURL. Agrégala en Info.plist."
        }
        guard let url = URL(string: baseUrl), let scheme = url.scheme, let host = url.host, !host.isEmpty else {
            return "APIBaseURL no es una URL válida: \(baseUrl)"
        }
        if release && scheme != "https" {
            return "En producción APIBaseURL debe usar https: \(baseUrl)"
        }
        return nil
    }
}

/// The app's long-lived services.
@MainActor
final class AppServices {
    let api: ApiClient
    let repository: GymRepository
    let auth: AuthController
    let settings: SettingsController
    let sensor: SensorService

    init(baseUrl: String) {
        api = ApiClient(baseUrl: baseUrl, tokens: KeychainTokenStore())
        repository = GymRepository(api: api, store: FileLocalStore())
        auth = AuthController(api: api)
        settings = SettingsController()
        sensor = SensorService(simulated: AppConfig.simulateSensor)
    }

    func load() {
        repository.load()
        auth.load()
        settings.load()
        // The repository follows the signed-in user: their data loads on sign
        // in, and on sign out or an expired session nothing of theirs stays on
        // screen.
        repository.switchUser(auth.user?.id)
        auth.onUserChanged = { [weak self] id in self?.repository.switchUser(id) }
    }
}

@main
struct RepCounterApp: App {
    init() {
        FontRegistry.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            AppEntry()
        }
    }
}

private struct AppEntry: View {
    @State private var services: AppServices?
    @State private var problem: String?

    var body: some View {
        Group {
            if let problem {
                // A build without a server address must say so instead of
                // failing on every screen with network errors.
                Text(problem)
                    .font(.text(16))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColors.light.ink)
                    .padding(kGutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.light.bg.ignoresSafeArea())
            } else if let services {
                RootView(services: services)
            } else {
                Color.clear
            }
        }
        .task {
            guard services == nil, problem == nil else { return }
            #if DEBUG
            let release = false
            #else
            let release = true
            #endif
            let base = AppConfig.apiBaseURL
            if let issue = AppConfig.problem(base, release: release) {
                problem = issue
                return
            }
            let loaded = AppServices(baseUrl: base)
            loaded.load()
            Router.shared.root = loaded.auth.signedIn ? .connection : .login
            services = loaded
            if loaded.auth.signedIn { await loaded.auth.refreshProfile() }
        }
    }
}

struct RootView: View {
    let services: AppServices
    @Bindable private var router = Router.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let colors = services.settings.darkMode ? AppColors.dark : AppColors.light
        ZStack {
            colors.bg.ignoresSafeArea()
            NavigationStack(path: $router.path) {
                rootScreen
                    .screen()
                    .navigationDestination(for: Route.self) { route in
                        RouteScreen(route: route).screen()
                    }
            }
            .id(router.root)
            OverlayHost()
        }
        .environment(\.colors, colors)
        .environment(services.repository)
        .environment(services.auth)
        .environment(services.settings)
        .environment(services.sensor)
        .preferredColorScheme(colors.isDark ? .dark : .light)
        .tint(colors.ink)
        .onChange(of: services.auth.signedIn) { wasSignedIn, signedIn in
            // Back to the login screen whenever the session ends: signing out,
            // or the server rejecting the session (password changed elsewhere,
            // token stolen).
            if wasSignedIn && !signedIn { router.reset(to: .login) }
        }
        .onChange(of: scenePhase) { old, phase in
            // Coming back to the app is the natural moment to catch up: changes
            // from another phone, or uploads that waited for signal.
            if phase == .active && old == .background && services.auth.signedIn {
                Task {
                    await services.repository.sync()
                    await services.auth.refreshProfile()
                }
            }
        }
    }

    @ViewBuilder
    private var rootScreen: some View {
        switch router.root {
        case .loading: Color.clear
        case .login: LoginScreen()
        case .connection: ConnectionScreen(popOnConnect: false, then: nil)
        case .home: HomeShell()
        }
    }
}

struct RouteScreen: View {
    let route: Route

    var body: some View {
        switch route {
        case .register: RegisterScreen()
        case .connection(let then): ConnectionScreen(popOnConnect: true, then: then)
        case .settings: SettingsScreen()
        case .routineDetail(let id): RoutineDetailScreen(routineId: id)
        case .routineEditor(let routine): RoutineEditorScreen(routine: routine, route: route)
        case .exerciseDetail(let exercise): ExerciseDetailScreen(exercise: exercise)
        case .picker(let request): ExercisePickerScreen(request: request)
        case .workout(let spec): WorkoutFlowScreen(spec: spec, route: route)
        case .summary(let session, let justFinished):
            SummaryScreen(session: session, justFinished: justFinished, route: route)
        case .allSessions: AllSessionsScreen()
        case .progress(let exercise): ProgressScreen(exercise: exercise)
        }
    }
}

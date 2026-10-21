// Navigation. One stack per root screen (login, sensor connection, home),
// mirroring the Flutter navigator: pushes, replacements and "back to the
// first screen".

import SwiftUI
import UIKit

/// What a workout screen starts with. The controller is created when the
/// screen opens.
struct WorkoutSpec: Hashable {
    enum Kind: Hashable {
        case routine(Routine)
        case free(Exercise, weightKg: Double?)
    }

    let id = UUID()
    let kind: Kind
}

struct PickerRequest: Hashable {
    let id = UUID()
    let title: String
    var single = false
}

enum Route: Hashable {
    case register
    /// Sensor connection opened from a badge or before a workout: it closes
    /// on connect (and opens `then`, when given).
    case connection(then: WorkoutSpec?)
    case settings
    case routineDetail(String)
    case routineEditor(Routine?)
    case exerciseDetail(Exercise)
    case picker(PickerRequest)
    case workout(WorkoutSpec)
    case summary(WorkoutSession, justFinished: Bool)
    case allSessions
    case progress(Exercise)
}

enum RootScreen { case loading, login, connection, home }

@MainActor
@Observable
final class Router {
    static let shared = Router()

    var root: RootScreen = .loading
    var path: [Route] = []
    /// Selected tab of the home screen: Rutinas · Ejercicios · Historial.
    var homeTab = 0

    /// Routes that cannot be left with the back swipe right now (a workout in
    /// progress, unsaved edits).
    @ObservationIgnored var blocked: Set<Route> = []
    @ObservationIgnored private var pickerHandlers: [UUID: ([Exercise]) -> Void] = [:]

    var top: Route? { path.last }

    func push(_ route: Route) { path.append(route) }

    func pop() {
        if !path.isEmpty { path.removeLast() }
    }

    func replaceTop(with route: Route) {
        if path.isEmpty {
            path = [route]
        } else {
            path[path.count - 1] = route
        }
    }

    /// Back to the first screen of the current root.
    func popToFirst() { path = [] }

    func reset(to root: RootScreen) {
        path = []
        homeTab = 0
        self.root = root
    }

    /// Opens the exercise picker; `handler` receives the chosen exercises.
    func pickExercises(title: String, single: Bool = false, _ handler: @escaping ([Exercise]) -> Void) {
        let request = PickerRequest(title: title, single: single)
        pickerHandlers[request.id] = handler
        push(.picker(request))
    }

    func finishPicker(_ request: PickerRequest, _ result: [Exercise]) {
        pop()
        pickerHandlers.removeValue(forKey: request.id)?(result)
    }

    var swipeBackAllowed: Bool {
        guard let top else { return false }
        return !blocked.contains(top)
    }
}

/// The navigation bar is hidden everywhere (every screen draws its own
/// header), which also disables the back swipe. This brings it back, except
/// on routes that block it.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1 && MainActor.assumeIsolated { Router.shared.swipeBackAllowed }
    }
}

extension View {
    /// Keeps the back swipe from leaving `route` while `blocked` is true
    /// (Flutter's PopScope with canPop false).
    func blocksBack(_ route: Route?, _ blocked: Bool) -> some View {
        modifier(BlocksBack(route: route, isBlocked: blocked))
    }
}

private struct BlocksBack: ViewModifier {
    let route: Route?
    let isBlocked: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { update(isBlocked) }
            .onChange(of: isBlocked) { _, value in update(value) }
    }

    private func update(_ value: Bool) {
        guard let route else { return }
        if value {
            Router.shared.blocked.insert(route)
        } else {
            Router.shared.blocked.remove(route)
        }
    }
}

// Dialogs, bottom sheets and the snackbar, drawn like the Flutter app's
// Material ones: theme background, radius 6, no shadows.

import SwiftUI

@MainActor
@Observable
final class OverlayCenter {
    static let shared = OverlayCenter()

    struct Presented: Identifiable {
        let id = UUID()
        let content: AnyView
        let dismiss: () -> Void
    }

    struct Snack: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    var dialog: Presented?
    var sheet: Presented?
    var snack: Snack?

    /// Shows a dialog built by `build`, which receives the function that
    /// closes it with a result. Tapping outside closes it with nil.
    func dialog<T>(_ build: (@escaping (T?) -> Void) -> AnyView) async -> T? {
        await withCheckedContinuation { continuation in
            var done = false
            let finish: (T?) -> Void = { [weak self] value in
                guard !done else { return }
                done = true
                withAnimation(.easeOut(duration: 0.15)) { self?.dialog = nil }
                continuation.resume(returning: value)
            }
            withAnimation(.easeOut(duration: 0.15)) {
                dialog = Presented(content: build(finish), dismiss: { finish(nil) })
            }
        }
    }

    /// Same as `dialog`, as a sheet from the bottom.
    func sheet<T>(_ build: (@escaping (T?) -> Void) -> AnyView) async -> T? {
        await withCheckedContinuation { continuation in
            var done = false
            let finish: (T?) -> Void = { [weak self] value in
                guard !done else { return }
                done = true
                withAnimation(.easeOut(duration: 0.25)) { self?.sheet = nil }
                continuation.resume(returning: value)
            }
            withAnimation(.easeOut(duration: 0.25)) {
                sheet = Presented(content: build(finish), dismiss: { finish(nil) })
            }
        }
    }

    func showMessage(_ text: String) {
        let snack = Snack(text: text)
        withAnimation(.easeOut(duration: 0.2)) { self.snack = snack }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard self?.snack?.id == snack.id else { return }
            withAnimation(.easeIn(duration: 0.2)) { self?.snack = nil }
        }
    }
}

/// Asks before leaving a screen with unsaved or in-progress work.
@MainActor
func confirm(title: String, message: String, confirmLabel: String, cancelLabel: String = "Cancelar") async -> Bool {
    let result: Bool? = await OverlayCenter.shared.dialog { finish in
        AnyView(AppDialog(title: title) {
            Text(message)
                .font(.text(16))
                .modifier(InkColor(\.ink2))
        } actions: {
            TextAction(label: cancelLabel) { finish(false) }
            TextAction(label: confirmLabel, colorKey: \.ink, weight: .semibold) { finish(true) }
        })
    }
    return result ?? false
}

@MainActor
func showMessage(_ text: String) { OverlayCenter.shared.showMessage(text) }

/// Light haptic tick, used when a rep lands or a timer ends.
@MainActor
func tick() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }

/// Applies a color from the theme. Handy where the environment is not
/// otherwise at hand.
struct InkColor: ViewModifier {
    let key: KeyPath<AppColors, Color>
    @Environment(\.colors) private var c

    init(_ key: KeyPath<AppColors, Color>) { self.key = key }

    func body(content: Content) -> some View { content.foregroundStyle(c[keyPath: key]) }
}

/// Material-style alert: title, content, actions aligned to the right.
struct AppDialog<Content: View, Actions: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions
    @Environment(\.colors) private var c

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.text(22, .semibold))
                .foregroundStyle(c.ink)
                .padding(.bottom, 16)
            content
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                actions
            }
            .padding(.top, 20)
            .padding(.trailing, -8)
        }
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 16, trailing: 24))
        .frame(maxWidth: 560, alignment: .leading)
        .background(c.bg, in: RoundedRectangle(cornerRadius: kRadius))
        .padding(.horizontal, 40)
    }
}

/// Draws the current dialog, sheet and snackbar over the app.
struct OverlayHost: View {
    @Environment(\.colors) private var c
    private let center = OverlayCenter.shared

    var body: some View {
        ZStack {
            if let sheet = center.sheet {
                Color.black.opacity(0.54)
                    .ignoresSafeArea()
                    .onTapGesture { sheet.dismiss() }
                    .transition(.opacity)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    sheet.content
                        .padding(EdgeInsets(top: 24, leading: kGutter, bottom: 24, trailing: kGutter))
                        .frame(maxWidth: .infinity)
                        .background(
                            UnevenRoundedRectangle(topLeadingRadius: kRadius * 2, topTrailingRadius: kRadius * 2)
                                .fill(c.bg)
                                .ignoresSafeArea(edges: .bottom)
                        )
                }
                .id(sheet.id)
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }
            if let dialog = center.dialog {
                Color.black.opacity(0.54)
                    .ignoresSafeArea()
                    .onTapGesture { dialog.dismiss() }
                    .transition(.opacity)
                dialog.content
                    .id(dialog.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(2)
            }
            if let snack = center.snack {
                VStack {
                    Spacer()
                    Text(snack.text)
                        .font(.text(16))
                        .foregroundStyle(c.bg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(c.ink, in: RoundedRectangle(cornerRadius: 4))
                        .padding(.horizontal, 15)
                        .padding(.bottom, 10)
                        .onTapGesture { center.snack = nil }
                }
                .id(snack.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
            }
        }
    }
}

// MARK: - Typed numbers

/// What the weight dialog returns. Nil from `askWeight` means cancelled, so
/// body weight needs its own case.
enum WeightEntry {
    case kg(Double)
    case bodyweight

    var kg: Double? {
        if case .kg(let v) = self { return v }
        return nil
    }
}

/// "22,75" or "22.75" → 22.75. Nil when it is not a number.
func parseDecimal(_ text: String) -> Double? {
    let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
    return v
}

/// Types an exact weight, in kg or lb (a switch next to the field, which
/// converts what is typed). Empty or 0 is body weight. Nil if cancelled.
@MainActor
func askWeight(initial: Double?, maxKg: Double) async -> WeightEntry? {
    await OverlayCenter.shared.dialog { finish in
        AnyView(WeightDialog(initialKg: initial, maxKg: maxKg, finish: finish))
    }
}

private struct WeightDialog: View {
    let initialKg: Double?
    let maxKg: Double
    let finish: (WeightEntry?) -> Void
    @Environment(\.colors) private var c
    @AppStorage(WeightUnit.storageKey) private var unit: WeightUnit = .kg
    @State private var text: String?
    @State private var error: String?
    @FocusState private var focused: Bool

    private var current: String { text ?? initialKg.map { unit.format(kg: $0) } ?? "" }

    /// What is typed, in kg. Nil when empty, zero or not a number.
    private var typedKg: Double? {
        guard let v = parseDecimal(current), v > 0 else { return nil }
        return unit.toKg(v)
    }

    private func save() {
        if current.trimmingCharacters(in: .whitespaces).isEmpty { return finish(.bodyweight) }
        guard let v = parseDecimal(current), v >= 0 else {
            error = "Escribe un número, por ejemplo 22,5."
            return
        }
        if v == 0 { return finish(.bodyweight) }
        let kg = unit.toKg(v)
        if kg > maxKg {
            error = "El máximo es \(formatWeightBoth(maxKg, first: unit))."
            return
        }
        finish(.kg(kg))
    }

    /// Swaps the unit and rewrites the typed number in it: 5 kg → 11 lb.
    private func switchUnit(to new: WeightUnit) {
        guard new != unit else { return }
        tick()
        if let kg = typedKg { text = new.format(kg: kg) }
        error = nil
        unit = new
    }

    var body: some View {
        let binding = Binding(get: { current }, set: { text = $0; error = nil })
        AppDialog(title: "Peso") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("", text: binding, prompt: Text("Corporal").foregroundStyle(c.ink3))
                        .font(.number(32))
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .onSubmit(save)
                    unitChip(.kg)
                    unitChip(.lb)
                }
                .modifier(FieldBox(focused: focused))
                if let error {
                    Text(error).font(.text(14)).foregroundStyle(c.ink)
                } else if let kg = typedKg {
                    // The same weight in the other unit, as it is typed.
                    Text("= \(unit.other.format(kg: kg)) \(unit.other.rawValue)")
                        .font(.text(14, .semibold)).foregroundStyle(c.ink2)
                } else {
                    Text("Déjalo vacío para peso corporal.").font(.text(14)).foregroundStyle(c.ink2)
                }
            }
        } actions: {
            TextAction(label: "Cancelar") { finish(nil) }
            TextAction(label: "Guardar", colorKey: \.ink, weight: .semibold, action: save)
        }
        .onAppear {
            // Straight to the keyboard, with the old value ready to replace.
            focused = true
            DispatchQueue.main.async {
                UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
            }
        }
    }

    private func unitChip(_ u: WeightUnit) -> some View {
        let selected = u == unit
        return Pressable(action: { switchUnit(to: u) }, label: u == .kg ? "En kilos" : "En libras") {
            Text(u.rawValue)
                .font(.text(15, .semibold))
                .foregroundStyle(selected ? c.bg : c.ink2)
                .frame(width: 40, height: 32)
                .background(selected ? c.ink : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Types a whole number, such as the reps of a set. Nil if cancelled.
@MainActor
func askCount(title: String, initial: Int, min: Int, max: Int) async -> Int? {
    await OverlayCenter.shared.dialog { finish in
        AnyView(NumberDialog(
            title: title,
            unit: nil,
            initial: "\(initial)",
            hint: "0",
            note: nil,
            keyboard: .numberPad,
            validate: { text in
                guard let v = Int(text.trimmingCharacters(in: .whitespaces)) else {
                    return .failure("Escribe un número entero.")
                }
                if v < min || v > max { return .failure("Tiene que estar entre \(min) y \(max).") }
                return .success(v)
            },
            finish: finish
        ))
    }
}

/// Result of checking what was typed: the value, or why it is wrong.
enum NumberCheck<T> {
    case success(T)
    case failure(String)
}

private struct NumberDialog<T>: View {
    let title: String
    let unit: String?
    let initial: String
    let hint: String
    let note: String?
    let keyboard: UIKeyboardType
    let validate: (String) -> NumberCheck<T>
    let finish: (T?) -> Void
    @Environment(\.colors) private var c
    @State private var text: String?
    @State private var error: String?
    @FocusState private var focused: Bool

    private func save() {
        switch validate(text ?? initial) {
        case .success(let v): finish(v)
        case .failure(let message): error = message
        }
    }

    var body: some View {
        let binding = Binding(get: { text ?? initial }, set: { text = $0; error = nil })
        AppDialog(title: title) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    TextField("", text: binding, prompt: Text(hint).foregroundStyle(c.ink3))
                        .font(.number(32))
                        .keyboardType(keyboard)
                        .focused($focused)
                        .onSubmit(save)
                    if let unit { Text(unit).font(.text(17)).foregroundStyle(c.ink2) }
                }
                .modifier(FieldBox(focused: focused))
                if let error {
                    Text(error).font(.text(14)).foregroundStyle(c.ink)
                } else if let note {
                    Text(note).font(.text(14)).foregroundStyle(c.ink2)
                }
            }
        } actions: {
            TextAction(label: "Cancelar") { finish(nil) }
            TextAction(label: "Guardar", colorKey: \.ink, weight: .semibold, action: save)
        }
        .onAppear {
            // Straight to the keyboard, with the old value ready to replace.
            focused = true
            DispatchQueue.main.async {
                UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
            }
        }
    }
}

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

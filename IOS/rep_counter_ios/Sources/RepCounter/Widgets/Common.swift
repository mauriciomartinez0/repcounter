// Building blocks shared by the screens. Sizes come from the style guide:
// 24 side margin, 72 primary button, 56 text field, radius 6, 1 px lines.

import SwiftUI

/// Uppercase 12 px label ("PESO USADO").
struct AppLabel: View {
    let text: String
    var color: Color?
    var size: CGFloat = 12
    var alignment: TextAlignment = .leading
    @Environment(\.colors) private var c

    init(_ text: String, color: Color? = nil, size: CGFloat = 12, alignment: TextAlignment = .leading) {
        self.text = text
        self.color = color
        self.size = size
        self.alignment = alignment
    }

    var body: some View {
        Text(text.uppercased())
            .font(.text(size, .semibold))
            .tracking(size * 0.1)
            .foregroundStyle(color ?? c.ink3)
            .multilineTextAlignment(alignment)
    }
}

/// Tap target without ripple. The design has no shadows or ink effects; a
/// slight opacity change acknowledges the press.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.linear(duration: 0.08), value: configuration.isPressed)
    }
}

struct Pressable<Content: View>: View {
    let action: (() -> Void)?
    var label: String?
    @ViewBuilder let content: Content

    init(action: (() -> Void)?, label: String? = nil, @ViewBuilder content: () -> Content) {
        self.action = action
        self.label = label
        self.content = content()
    }

    var body: some View {
        let button = Button { action?() } label: { content }
            .buttonStyle(PressableStyle())
            .disabled(action == nil)
        if let label {
            button.accessibilityLabel(label)
        } else {
            button
        }
    }
}

struct PrimaryButton: View {
    let label: String
    var height: CGFloat = 72
    var fontSize: CGFloat = 22
    var busy = false
    let action: (() -> Void)?
    @Environment(\.colors) private var c

    init(_ label: String, height: CGFloat = 72, fontSize: CGFloat = 22, busy: Bool = false,
         action: (() -> Void)?) {
        self.label = label
        self.height = height
        self.fontSize = fontSize
        self.busy = busy
        self.action = action
    }

    var body: some View {
        Pressable(action: action != nil && !busy ? action : nil) {
            ZStack {
                if busy {
                    ProgressView().tint(c.btnInk)
                } else {
                    Text(label)
                        .font(.text(fontSize, .semibold))
                        .foregroundStyle(c.btnInk)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(c.btnBg, in: RoundedRectangle(cornerRadius: kRadius))
            .opacity(action == nil ? 0.4 : 1)
        }
    }
}

struct SecondaryButton: View {
    let label: String
    var height: CGFloat = 64
    var fontSize: CGFloat = 18
    var icon: AppIconKind?
    let action: (() -> Void)?
    @Environment(\.colors) private var c

    init(_ label: String, height: CGFloat = 64, fontSize: CGFloat = 18, icon: AppIconKind? = nil,
         action: (() -> Void)?) {
        self.label = label
        self.height = height
        self.fontSize = fontSize
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Pressable(action: action) {
            HStack(spacing: 12) {
                if let icon { AppIcon(icon, color: c.ink) }
                Text(label)
                    .font(.text(fontSize, .semibold))
                    .foregroundStyle(c.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(RoundedRectangle(cornerRadius: kRadius).strokeBorder(c.control, lineWidth: 1))
        }
    }
}

/// 48 px outlined button for secondary actions in a row ("Editar").
struct SmallButton: View {
    let label: String
    let action: (() -> Void)?
    @Environment(\.colors) private var c

    init(_ label: String, action: (() -> Void)?) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Pressable(action: action) {
            Text(label)
                .font(.text(16, .semibold))
                .foregroundStyle(c.ink)
                .padding(.horizontal, 20)
                .frame(height: 48)
                .overlay(RoundedRectangle(cornerRadius: kRadius).strokeBorder(c.control, lineWidth: 1))
        }
    }
}

/// A plain text action ("¿La olvidaste?", "Cancelar").
struct TextAction: View {
    let label: String
    var color: Color?
    var colorKey: KeyPath<AppColors, Color>?
    var weight: TextWeight = .regular
    var size: CGFloat = 16
    var underline = false
    let action: (() -> Void)?
    @Environment(\.colors) private var c

    init(label: String, color: Color? = nil, colorKey: KeyPath<AppColors, Color>? = nil,
         weight: TextWeight = .regular, size: CGFloat = 16, underline: Bool = false,
         action: (() -> Void)?) {
        self.label = label
        self.color = color
        self.colorKey = colorKey
        self.weight = weight
        self.size = size
        self.underline = underline
        self.action = action
    }

    var body: some View {
        let ink = color ?? colorKey.map { c[keyPath: $0] } ?? c.ink2
        Pressable(action: action) {
            Text(label)
                .font(.text(size, weight))
                .underline(underline, color: ink)
                .foregroundStyle(ink)
                .frame(minWidth: 44, minHeight: 44)
        }
    }
}

/// Field look shared by AppTextField and SearchField.
private struct FieldBox: ViewModifier {
    let focused: Bool
    @Environment(\.colors) private var c

    func body(content: Content) -> some View {
        content
            .font(.text(17))
            .foregroundStyle(c.ink)
            .tint(c.ink)
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(c.surface, in: RoundedRectangle(cornerRadius: kRadius))
            .overlay(
                RoundedRectangle(cornerRadius: kRadius)
                    .strokeBorder(focused ? c.ink : c.control, lineWidth: focused ? 1.5 : 1)
            )
    }
}

struct AppTextField<Trailing: View>: View {
    let label: String
    let hint: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var secure = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var capitalization: TextInputAutocapitalization = .sentences
    var submitLabel: SubmitLabel = .return
    var onSubmit: () -> Void = {}
    @ViewBuilder var trailing: Trailing
    @Environment(\.colors) private var c

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                AppLabel(label)
                Spacer(minLength: 0)
                trailing
            }
            .frame(minHeight: 16)
            Group {
                if secure {
                    SecureField("", text: $text, prompt: Text(hint).foregroundStyle(c.ink2))
                } else {
                    TextField("", text: $text, prompt: Text(hint).foregroundStyle(c.ink2))
                }
            }
            .focused(focus)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(secure || keyboard == .emailAddress)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            .modifier(FieldBox(focused: focus.wrappedValue))
        }
    }
}

extension AppTextField where Trailing == EmptyView {
    init(label: String, hint: String, text: Binding<String>, focus: FocusState<Bool>.Binding,
         secure: Bool = false, keyboard: UIKeyboardType = .default, contentType: UITextContentType? = nil,
         capitalization: TextInputAutocapitalization = .sentences, submitLabel: SubmitLabel = .return,
         onSubmit: @escaping () -> Void = {}) {
        self.init(label: label, hint: hint, text: text, focus: focus, secure: secure, keyboard: keyboard,
                  contentType: contentType, capitalization: capitalization, submitLabel: submitLabel,
                  onSubmit: onSubmit, trailing: { EmptyView() })
    }
}

/// Search field with the surface fill used in the catalog.
struct SearchField: View {
    @Binding var text: String
    var hint = "Buscar ejercicio"
    @FocusState private var focused: Bool
    @Environment(\.colors) private var c

    var body: some View {
        TextField("", text: $text, prompt: Text(hint).foregroundStyle(c.ink2))
            .focused($focused)
            .submitLabel(.search)
            .modifier(FieldBox(focused: focused))
    }
}

/// Dot plus "SENSOR". Filled when connected, hollow when not. Tapping it
/// while disconnected opens the connection screen.
struct SensorBadge: View {
    var interactive = true
    @Environment(SensorService.self) private var sensor
    @Environment(\.colors) private var c

    var body: some View {
        let connected = sensor.connected
        let battery = connected ? sensor.batteryLevel : nil
        let badge = HStack(spacing: 8) {
            Circle()
                .fill(connected ? c.dot : .clear)
                .overlay(
                    Circle().strokeBorder(connected ? (c.dotRing ?? c.dot) : c.ink2, lineWidth: 1.5)
                )
                .frame(width: 10, height: 10)
            AppLabel("Sensor", color: c.ink2)
            if let battery {
                BatteryIndicator(level: battery)
            }
        }
        if interactive && !connected {
            Pressable(action: { Router.shared.push(.connection(then: nil)) }) {
                badge.frame(height: 44)
            }
            .accessibilityLabel("Sensor sin conectar")
        } else {
            badge
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(connected
                    ? "Sensor conectado" + (battery.map { ", batería \($0) por ciento" } ?? "")
                    : "Sensor sin conectar")
        }
    }
}

/// Battery outline filled to the level, plus "82 %". At 15 % or less it
/// switches to ink and semibold so it stands out without a new color.
struct BatteryIndicator: View {
    let level: Int
    @Environment(\.colors) private var c

    var body: some View {
        let low = level <= 15
        let ink = low ? c.ink : c.ink2
        HStack(spacing: 4) {
            HStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(ink, lineWidth: 1.25)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(ink)
                                .frame(width: max(1.5, (geo.size.width - 4) * CGFloat(level) / 100))
                                .padding(2)
                        }
                    }
                    .frame(width: 20, height: 10)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(ink)
                    .frame(width: 1.5, height: 4)
            }
            Text("\(level) %")
                .font(.text(12, low ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(ink)
        }
    }
}

struct IconTapTarget: View {
    let icon: AppIconKind
    let label: String
    var color: Color?
    let action: (() -> Void)?

    var body: some View {
        Pressable(action: action, label: label) {
            AppIcon(icon, color: color)
                .frame(width: 48, height: 48)
        }
    }
}

/// Back chevron on the left, sensor badge (and optional extras) on the right.
struct BackHeader<Actions: View>: View {
    var onBack: (() -> Void)?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 0) {
            IconTapTarget(icon: .back, label: "Volver") {
                if let onBack { onBack() } else { Router.shared.pop() }
            }
            Spacer(minLength: 0)
            actions
            SensorBadge()
        }
        .padding(.leading, 12)
        .padding(.trailing, kGutter)
        .frame(height: 56)
    }
}

extension BackHeader where Actions == EmptyView {
    init(onBack: (() -> Void)? = nil) {
        self.onBack = onBack
        actions = EmptyView()
    }
}

/// "Cancelar · Título · Guardar".
struct ModalHeader: View {
    let title: String
    var onCancel: (() -> Void)?
    var actionLabel: String?
    var onAction: (() -> Void)?
    @Environment(\.colors) private var c

    var body: some View {
        HStack(spacing: 0) {
            TextAction(label: "Cancelar") {
                if let onCancel { onCancel() } else { Router.shared.pop() }
            }
            // Without an action the title sits after "Cancelar"; with one it
            // is centered between both.
            if actionLabel == nil { Spacer().frame(width: 56) }
            Text(title)
                .font(.text(17, .semibold))
                .foregroundStyle(c.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: actionLabel == nil ? .leading : .center)
            if let actionLabel {
                TextAction(label: actionLabel, color: onAction == nil ? c.ink3 : c.mark, weight: .semibold,
                           action: onAction)
            }
        }
        .padding(.horizontal, kGutter)
        .frame(height: 56)
    }
}

/// Outlined chip with an icon ("Press de banca" in Recientes).
struct OutlineChip: View {
    let label: String
    var icon: AppIconKind?
    let action: (() -> Void)?
    @Environment(\.colors) private var c

    var body: some View {
        Pressable(action: action) {
            HStack(spacing: 8) {
                if let icon { AppIcon(icon, size: 22, color: c.ink) }
                Text(label).font(.text(15)).foregroundStyle(c.ink).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .overlay(RoundedRectangle(cornerRadius: kRadius).strokeBorder(c.control, lineWidth: 1))
        }
    }
}

/// Filled chip used for filters and segment choices. Selected chips invert.
struct FillChip: View {
    let label: String
    let selected: Bool
    var icon: AppIconKind?
    var fontSize: CGFloat = 15
    let action: (() -> Void)?
    @Environment(\.colors) private var c

    var body: some View {
        let fg = selected ? c.bg : c.ink
        Pressable(action: action) {
            HStack(spacing: 8) {
                if let icon { AppIcon(icon, size: 18, color: fg) }
                Text(label).font(.text(fontSize)).foregroundStyle(fg).lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(selected ? c.ink : c.surface, in: RoundedRectangle(cornerRadius: kRadius))
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Horizontal row of chips that scrolls past the right edge, as in the
/// designs, while starting aligned with the side margin.
struct ChipRow<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) { content }
                .padding(.horizontal, kGutter)
        }
    }
}

struct AppCheckbox: View {
    let checked: Bool
    @Environment(\.colors) private var c

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(checked ? c.btnBg : .clear)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(checked ? c.btnBg : c.control, lineWidth: 1.5))
            .overlay {
                if checked { AppIcon(.check, size: 20, color: c.btnInk, strokeWidth: 2) }
            }
            .frame(width: 28, height: 28)
    }
}

/// Theme switch as drawn in Ajustes: 68 × 40 track, 28 px knob.
struct AppSwitch: View {
    let value: Bool
    var label: String?
    let onChanged: (Bool) -> Void
    @Environment(\.colors) private var c

    var body: some View {
        Pressable(action: { onChanged(!value) }) {
            ZStack(alignment: value ? .trailing : .leading) {
                Capsule()
                    .fill(value ? c.btnBg : c.surface)
                    .overlay(Capsule().strokeBorder(value ? c.btnBg : c.control, lineWidth: 1.5))
                Circle()
                    .fill(value ? c.btnInk : c.control)
                    .frame(width: 28, height: 28)
                    .padding(4.5 + 1.5)
            }
            .frame(width: 68, height: 40)
            .animation(.easeOut(duration: 0.16), value: value)
        }
        .accessibilityLabel(label ?? "")
        .accessibilityValue(value ? "Activado" : "Desactivado")
    }
}

/// Big number with a small unit next to it ("60 kg").
struct NumberWithUnit: View {
    let value: String
    var unit: String?
    var size: CGFloat = 40
    var unitSize: CGFloat = 15
    var color: Color?
    @Environment(\.colors) private var c

    var body: some View {
        var text = Text(value).font(.number(size)).foregroundColor(color ?? c.ink)
        if let unit {
            text = text + Text(" \(unit)").font(.text(unitSize)).foregroundColor(c.ink2)
        }
        return text.lineLimit(1)
    }
}

/// − value + control for weights.
struct WeightStepper: View {
    /// Nil means body weight; the buttons then add load.
    let valueKg: Double?
    var large = true
    var step = 2.5
    let onChanged: (Double?) -> Void
    @Environment(\.colors) private var c

    var body: some View {
        let box: CGFloat = large ? 72 : 56
        HStack(spacing: 0) {
            stepButton(.minus, "Bajar peso", box: box, action: valueKg.map { v in
                { onChanged(v - step <= 0 ? nil : v - step) }
            })
            if large { Spacer(minLength: 0) }
            Group {
                if let value = valueKg {
                    NumberWithUnit(value: formatKg(value), unit: "kg", size: large ? 80 : 40,
                                   unitSize: large ? 20 : 15)
                } else {
                    Text("Corporal").font(.number(large ? 48 : 30)).foregroundStyle(c.ink)
                }
            }
            .frame(width: large ? nil : 108)
            .minimumScaleFactor(0.5)
            if large { Spacer(minLength: 0) }
            stepButton(.plus, "Subir peso", box: box) { onChanged((valueKg ?? 0) + step) }
        }
    }

    private func stepButton(_ icon: AppIconKind, _ label: String, box: CGFloat,
                            action: (() -> Void)?) -> some View {
        Pressable(action: action, label: label) {
            AppIcon(icon, size: large ? 28 : 24, color: c.ink)
                .frame(width: box, height: box)
                .background(c.surface, in: RoundedRectangle(cornerRadius: kRadius))
                .opacity(action == nil ? 0.4 : 1)
        }
    }
}

/// − value + for whole numbers, such as correcting the reps of a set.
struct CountStepper: View {
    let value: Int
    var min = 0
    var max = 999
    /// For screen readers: "Quitar una de repeticiones".
    var label = "repeticiones"
    let onChanged: (Int) -> Void
    @Environment(\.colors) private var c

    var body: some View {
        HStack(spacing: 0) {
            button(.minus, "Quitar una de \(label)", value > min ? { onChanged(value - 1) } : nil)
            Text("\(value)")
                .font(.number(40))
                .foregroundStyle(c.ink)
                .frame(width: 72)
            button(.plus, "Sumar una de \(label)", value < max ? { onChanged(value + 1) } : nil)
        }
    }

    private func button(_ icon: AppIconKind, _ semantic: String, _ action: (() -> Void)?) -> some View {
        Pressable(action: action, label: semantic) {
            AppIcon(icon, color: c.ink)
                .frame(width: 56, height: 56)
                .background(c.surface, in: RoundedRectangle(cornerRadius: kRadius))
                .opacity(action == nil ? 0.4 : 1)
        }
    }
}

/// A labelled stat used in the rest screen, summary and progress.
struct StatCell<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value
    var footnote: String?
    var footnoteColor: Color?
    @Environment(\.colors) private var c

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AppLabel(label)
            value
            if let footnote {
                Text(footnote)
                    .font(.text(14, footnoteColor != nil ? .semibold : .regular))
                    .foregroundStyle(footnoteColor ?? c.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Two stats side by side with a vertical rule between, framed by lines.
struct StatPair<Left: View, Right: View>: View {
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right
    @Environment(\.colors) private var c

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            left
                .padding(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 16))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(c.line).frame(width: 1)
            right
                .padding(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .top) { Rectangle().fill(c.line).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: 1) }
    }
}

/// Thin progress track (calibration, rest timer).
struct ProgressTrack: View {
    let value: Double
    var height: CGFloat = 4
    var fill: Color?
    @Environment(\.colors) private var c

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(c.track)
                Rectangle()
                    .fill(fill ?? c.ink)
                    .frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: height)
    }
}

/// A horizontal 1 px rule.
struct Rule: View {
    @Environment(\.colors) private var c

    var body: some View {
        Rectangle().fill(c.line).frame(height: 1)
    }
}

/// Bottom border helper used by list rows.
extension View {
    func bottomRule(_ color: Color, visible: Bool = true) -> some View {
        overlay(alignment: .bottom) {
            if visible { Rectangle().fill(color).frame(height: 1) }
        }
    }

    func topRule(_ color: Color, visible: Bool = true) -> some View {
        overlay(alignment: .top) {
            if visible { Rectangle().fill(color).frame(height: 1) }
        }
    }

    /// Every screen: theme background edge to edge, no navigation bar.
    func screen() -> some View {
        modifier(ScreenModifier())
    }
}

private struct ScreenModifier: ViewModifier {
    @Environment(\.colors) private var c

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(c.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// Wraps chips onto several lines (Flutter's Wrap).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var runSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + runSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + runSpacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

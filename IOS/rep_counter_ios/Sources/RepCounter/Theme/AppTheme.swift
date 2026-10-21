// Design tokens from the style guide: two themes, one accent, no shadows or
// gradients. Every screen reads its colors from `AppColors` (environment
// `\.colors`) so the dark-mode switch in Ajustes changes the whole app at once.

import CoreText
import SwiftUI

/// Side margin used by every screen.
let kGutter: CGFloat = 24
let kRadius: CGFloat = 6

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct AppColors: Equatable {
    let bg: Color
    let surface: Color
    let line: Color
    let track: Color
    let control: Color
    let ink: Color
    let ink2: Color
    let ink3: Color

    /// The accent on top of the background: active tab, threshold, chart line
    /// past the threshold, "Guardar".
    let mark: Color
    let btnBg: Color
    let btnInk: Color

    /// The sensor dot. Lime in both themes; it only ever means "the sensor".
    let dot: Color
    /// Nil when the dot has no ring (dark theme).
    let dotRing: Color?

    /// Counter background and number once the target is reached.
    let hitBg: Color
    let hitInk: Color

    let isDark: Bool

    static let light = AppColors(
        bg: Color(hex: 0xF5F6EF),
        surface: Color(hex: 0xE8EADF),
        line: Color(hex: 0xD5D8C8),
        track: Color(hex: 0xC4C8B4),
        control: Color(hex: 0x767A66),
        ink: Color(hex: 0x0B0D04),
        ink2: Color(hex: 0x454938),
        ink3: Color(hex: 0x5F6350),
        mark: Color(hex: 0x3F6B00),
        btnBg: Color(hex: 0x0B0D04),
        btnInk: Color(hex: 0xC8FF2E),
        dot: Color(hex: 0xC8FF2E),
        dotRing: Color(hex: 0x0B0D04),
        hitBg: Color(hex: 0xC8FF2E),
        hitInk: Color(hex: 0x0B0D04),
        isDark: false
    )

    static let dark = AppColors(
        bg: Color(hex: 0x060705),
        surface: Color(hex: 0x14160F),
        line: Color(hex: 0x23261C),
        track: Color(hex: 0x3A3E30),
        control: Color(hex: 0x5F6352),
        ink: Color(hex: 0xF4F6EC),
        ink2: Color(hex: 0xA6AA98),
        ink3: Color(hex: 0x80846F),
        mark: Color(hex: 0xC8FF2E),
        btnBg: Color(hex: 0xC8FF2E),
        btnInk: Color(hex: 0x0B0D04),
        dot: Color(hex: 0xC8FF2E),
        dotRing: nil,
        hitBg: Color(hex: 0x060705),
        hitInk: Color(hex: 0xC8FF2E),
        isDark: true
    )
}

private struct AppColorsKey: EnvironmentKey {
    static let defaultValue = AppColors.light
}

extension EnvironmentValues {
    var colors: AppColors {
        get { self[AppColorsKey.self] }
        set { self[AppColorsKey.self] = newValue }
    }
}

// MARK: - Type

enum TextWeight {
    case regular, medium, semibold

    var fontName: String {
        switch self {
        case .regular: "Barlow-Regular"
        case .medium: "Barlow-Medium"
        case .semibold: "Barlow-SemiBold"
        }
    }
}

extension Font {
    /// Barlow, the text face.
    static func text(_ size: CGFloat, _ weight: TextWeight = .regular) -> Font {
        .custom(weight.fontName, fixedSize: size)
    }

    /// Numbers: Barlow Condensed Light with tabular figures so digits do not
    /// jump around while the count changes.
    static func number(_ size: CGFloat) -> Font {
        .custom("BarlowCondensed-Light", fixedSize: size).monospacedDigit()
    }
}

/// Registers the bundled fonts once at launch. They ship as a SwiftPM
/// resource, so Info.plist's UIAppFonts cannot point at them.
enum FontRegistry {
    static func registerAll() {
        let root = Bundle.module.bundleURL
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return
        }
        for case let url as URL in files where url.pathExtension.lowercased() == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

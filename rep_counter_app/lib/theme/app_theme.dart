// Design tokens from the style guide: two themes, one accent, no shadows or
// gradients. Every screen reads its colors from [AppColors] so the dark-mode
// switch in Ajustes changes the whole app at once.

import 'package:flutter/material.dart';

const String kTextFont = 'Barlow';
const String kNumberFont = 'Barlow Condensed';

/// Side margin used by every screen.
const double kGutter = 24;
const double kRadius = 6;

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.line,
    required this.track,
    required this.control,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.mark,
    required this.btnBg,
    required this.btnInk,
    required this.dot,
    required this.dotRing,
    required this.hitBg,
    required this.hitInk,
  });

  final Color bg;
  final Color surface;
  final Color line;
  final Color track;
  final Color control;
  final Color ink;
  final Color ink2;
  final Color ink3;

  /// The accent on top of the background: active tab, threshold, chart line
  /// past the threshold, "Guardar".
  final Color mark;
  final Color btnBg;
  final Color btnInk;

  /// The sensor dot. Lime in both themes; it only ever means "the sensor".
  final Color dot;
  final Color dotRing;

  /// Counter background and number once the target is reached.
  final Color hitBg;
  final Color hitInk;

  static const AppColors light = AppColors(
    bg: Color(0xFFF5F6EF),
    surface: Color(0xFFE8EADF),
    line: Color(0xFFD5D8C8),
    track: Color(0xFFC4C8B4),
    control: Color(0xFF767A66),
    ink: Color(0xFF0B0D04),
    ink2: Color(0xFF454938),
    ink3: Color(0xFF5F6350),
    mark: Color(0xFF3F6B00),
    btnBg: Color(0xFF0B0D04),
    btnInk: Color(0xFFC8FF2E),
    dot: Color(0xFFC8FF2E),
    dotRing: Color(0xFF0B0D04),
    hitBg: Color(0xFFC8FF2E),
    hitInk: Color(0xFF0B0D04),
  );

  static const AppColors dark = AppColors(
    bg: Color(0xFF060705),
    surface: Color(0xFF14160F),
    line: Color(0xFF23261C),
    track: Color(0xFF3A3E30),
    control: Color(0xFF5F6352),
    ink: Color(0xFFF4F6EC),
    ink2: Color(0xFFA6AA98),
    ink3: Color(0xFF80846F),
    mark: Color(0xFFC8FF2E),
    btnBg: Color(0xFFC8FF2E),
    btnInk: Color(0xFF0B0D04),
    dot: Color(0xFFC8FF2E),
    dotRing: Color(0x00000000),
    hitBg: Color(0xFF060705),
    hitInk: Color(0xFFC8FF2E),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      line: l(line, other.line),
      track: l(track, other.track),
      control: l(control, other.control),
      ink: l(ink, other.ink),
      ink2: l(ink2, other.ink2),
      ink3: l(ink3, other.ink3),
      mark: l(mark, other.mark),
      btnBg: l(btnBg, other.btnBg),
      btnInk: l(btnInk, other.btnInk),
      dot: l(dot, other.dot),
      dotRing: l(dotRing, other.dotRing),
      hitBg: l(hitBg, other.hitBg),
      hitInk: l(hitInk, other.hitInk),
    );
  }
}

extension AppThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

/// Text styles named after the style guide's type scale.
class AppText {
  AppText._();

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static TextStyle text(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = 1.3,
  }) =>
      TextStyle(
        fontFamily: kTextFont,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
      );

  /// Numbers: Barlow Condensed Light with tabular figures so digits do not
  /// jump around while the count changes.
  static TextStyle number(double size, {Color? color, double height = 1}) =>
      TextStyle(
        fontFamily: kNumberFont,
        fontSize: size,
        fontWeight: FontWeight.w300,
        color: color,
        height: height,
        fontFeatures: _tabular,
      );

  /// 12 px SemiBold uppercase label ("PESO USADO").
  static TextStyle label(Color color, {double size = 12}) => TextStyle(
        fontFamily: kTextFont,
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: size * 0.1,
        height: 16 / 12,
        color: color,
      );
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: kTextFont,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: c.ink.withValues(alpha: 0.05),
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: c.btnBg,
      onPrimary: c.btnInk,
      secondary: c.mark,
      onSecondary: c.bg,
      error: c.ink,
      onError: c.bg,
      surface: c.bg,
      onSurface: c.ink,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.ink,
      selectionColor: c.dot.withValues(alpha: 0.5),
      selectionHandleColor: c.ink,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: AppText.text(16, color: c.bg),
      behavior: SnackBarBehavior.floating,
    ),
    extensions: [c],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: kTextFont,
      bodyColor: c.ink,
      displayColor: c.ink,
    ),
  );
}

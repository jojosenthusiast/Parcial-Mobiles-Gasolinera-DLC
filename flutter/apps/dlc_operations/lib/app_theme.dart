import 'package:flutter/material.dart';

/// Semantic status shared by tanks, alerts and badges.
/// Always rendered with an icon and a text label, never colour alone.
enum DlcStatus {
  optimal,
  medium,
  critical,
  warning,
  info;

  String get label => switch (this) {
    DlcStatus.optimal => 'Óptimo',
    DlcStatus.medium => 'Medio',
    DlcStatus.critical => 'Crítico',
    DlcStatus.warning => 'Atención',
    DlcStatus.info => 'Información',
  };

  IconData get icon => switch (this) {
    DlcStatus.optimal => Icons.check_circle_outline,
    DlcStatus.medium => Icons.error_outline,
    DlcStatus.critical => Icons.report_gmailerrorred_outlined,
    DlcStatus.warning => Icons.warning_amber_rounded,
    DlcStatus.info => Icons.info_outline,
  };
}

/// Brand and semantic colours that Material's [ColorScheme] does not model.
/// Light and dark variants are tuned for WCAG AA (4.5:1) against [surface].
@immutable
class DlcColors extends ThemeExtension<DlcColors> {
  const DlcColors({
    required this.brand,
    required this.brandContainer,
    required this.ink,
    required this.muted,
    required this.border,
    required this.surface,
    required this.optimal,
    required this.medium,
    required this.critical,
    required this.warning,
    required this.info,
    required this.optimalContainer,
    required this.mediumContainer,
    required this.criticalContainer,
    required this.warningContainer,
    required this.infoContainer,
  });

  final Color brand;
  final Color brandContainer;
  final Color ink;
  final Color muted;
  final Color border;
  final Color surface;
  final Color optimal;
  final Color medium;
  final Color critical;
  final Color warning;
  final Color info;
  final Color optimalContainer;
  final Color mediumContainer;
  final Color criticalContainer;
  final Color warningContainer;
  final Color infoContainer;

  static const light = DlcColors(
    brand: Color(0xffc4411a),
    brandContainer: Color(0xffffe7dd),
    ink: Color(0xff213b32),
    muted: Color(0xff6d706a),
    border: Color(0xffe4ddcf),
    surface: Color(0xfffffdf8),
    optimal: Color(0xff287553),
    medium: Color(0xff8a5a00),
    critical: Color(0xffb93a31),
    warning: Color(0xff9a4a00),
    info: Color(0xff1f5f99),
    optimalContainer: Color(0xffe5f1e7),
    mediumContainer: Color(0xfffff2db),
    criticalContainer: Color(0xffffeae5),
    warningContainer: Color(0xffffeed9),
    infoContainer: Color(0xffe3effa),
  );

  static const dark = DlcColors(
    brand: Color(0xffff8a5c),
    brandContainer: Color(0xff4a2316),
    ink: Color(0xffe8efe9),
    muted: Color(0xffa9afa7),
    border: Color(0xff3a3731),
    surface: Color(0xff1f1d1a),
    optimal: Color(0xff63c797),
    medium: Color(0xfff0be55),
    critical: Color(0xffff8f86),
    warning: Color(0xffffb35c),
    info: Color(0xff80bdf2),
    optimalContainer: Color(0xff16342a),
    mediumContainer: Color(0xff3b2e0e),
    criticalContainer: Color(0xff4a2420),
    warningContainer: Color(0xff402a0e),
    infoContainer: Color(0xff1b3248),
  );

  static DlcColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  Color foreground(DlcStatus status) => switch (status) {
    DlcStatus.optimal => optimal,
    DlcStatus.medium => medium,
    DlcStatus.critical => critical,
    DlcStatus.warning => warning,
    DlcStatus.info => info,
  };

  Color container(DlcStatus status) => switch (status) {
    DlcStatus.optimal => optimalContainer,
    DlcStatus.medium => mediumContainer,
    DlcStatus.critical => criticalContainer,
    DlcStatus.warning => warningContainer,
    DlcStatus.info => infoContainer,
  };

  @override
  DlcColors copyWith({
    Color? brand,
    Color? brandContainer,
    Color? ink,
    Color? muted,
    Color? border,
    Color? surface,
    Color? optimal,
    Color? medium,
    Color? critical,
    Color? warning,
    Color? info,
    Color? optimalContainer,
    Color? mediumContainer,
    Color? criticalContainer,
    Color? warningContainer,
    Color? infoContainer,
  }) => DlcColors(
    brand: brand ?? this.brand,
    brandContainer: brandContainer ?? this.brandContainer,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    border: border ?? this.border,
    surface: surface ?? this.surface,
    optimal: optimal ?? this.optimal,
    medium: medium ?? this.medium,
    critical: critical ?? this.critical,
    warning: warning ?? this.warning,
    info: info ?? this.info,
    optimalContainer: optimalContainer ?? this.optimalContainer,
    mediumContainer: mediumContainer ?? this.mediumContainer,
    criticalContainer: criticalContainer ?? this.criticalContainer,
    warningContainer: warningContainer ?? this.warningContainer,
    infoContainer: infoContainer ?? this.infoContainer,
  );

  @override
  DlcColors lerp(ThemeExtension<DlcColors>? other, double t) {
    if (other is! DlcColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return DlcColors(
      brand: mix(brand, other.brand),
      brandContainer: mix(brandContainer, other.brandContainer),
      ink: mix(ink, other.ink),
      muted: mix(muted, other.muted),
      border: mix(border, other.border),
      surface: mix(surface, other.surface),
      optimal: mix(optimal, other.optimal),
      medium: mix(medium, other.medium),
      critical: mix(critical, other.critical),
      warning: mix(warning, other.warning),
      info: mix(info, other.info),
      optimalContainer: mix(optimalContainer, other.optimalContainer),
      mediumContainer: mix(mediumContainer, other.mediumContainer),
      criticalContainer: mix(criticalContainer, other.criticalContainer),
      warningContainer: mix(warningContainer, other.warningContainer),
      infoContainer: mix(infoContainer, other.infoContainer),
    );
  }
}

extension DlcThemeContext on BuildContext {
  /// Brand and status colours for the active theme. Falls back to the matching
  /// palette when the surrounding [MaterialApp] has no [DlcColors] extension.
  DlcColors get dlc {
    final theme = Theme.of(this);
    return theme.extension<DlcColors>() ?? DlcColors.of(theme.brightness);
  }
}

/// WCAG 2.x contrast ratio between two opaque colours (1.0 to 21.0).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

ThemeData buildDlcTheme(Brightness brightness) {
  final c = DlcColors.of(brightness);
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: DlcColors.light.brand,
    brightness: brightness,
    primary: c.brand,
    onPrimary: dark ? const Color(0xff2a1308) : Colors.white,
    secondary: dark ? c.optimal : c.ink,
    surface: c.surface,
    onSurface: dark ? c.ink : null,
    error: c.critical,
  );
  OutlineInputBorder outline(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: color, width: width),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: dark
        ? const Color(0xff141210)
        : const Color(0xfff5f0e5),
    colorScheme: scheme,
    extensions: [c],
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: outline(c.border),
      enabledBorder: outline(c.border),
      focusedBorder: outline(c.brand, 1.6),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.border),
      ),
    ),
  );
}

final ThemeData lightTheme = buildDlcTheme(Brightness.light);
final ThemeData darkTheme = buildDlcTheme(Brightness.dark);

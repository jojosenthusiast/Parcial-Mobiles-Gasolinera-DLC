import 'package:flutter/cupertino.dart' show CupertinoIcons;
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
    DlcStatus.optimal => CupertinoIcons.checkmark_circle,
    DlcStatus.medium => CupertinoIcons.exclamationmark_circle,
    DlcStatus.critical => CupertinoIcons.exclamationmark_octagon,
    DlcStatus.warning => CupertinoIcons.exclamationmark_triangle,
    DlcStatus.info => CupertinoIcons.info_circle,
  };
}

/// Brand colours sampled from the logo (DESIGN.md section 1). They are
/// decorative (gradients, dots, bars): text never uses them directly.
abstract final class DlcBrand {
  static const yellow = Color(0xfffbbd29);
  static const amber = Color(0xfffb9f41);
  static const orange = Color(0xfffb7911);
  static const red = Color(0xffa21a1a);
  static const inkWarm = Color(0xff1c1917);

  /// Brand gradient for hero elements only (never behind small text).
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [yellow, orange, red],
  );
}

/// Brand and semantic colours that Material's [ColorScheme] does not model.
/// Light and dark variants are tuned for WCAG AA (4.5:1) against [surface].
///
/// [brand] doubles as the action colour (filled buttons with [onBrand] text,
/// links): burnt orange, >= 4.5:1 against white in light mode.
@immutable
class DlcColors extends ThemeExtension<DlcColors> {
  const DlcColors({
    required this.brand,
    required this.brandContainer,
    required this.onBrand,
    required this.ink,
    required this.muted,
    required this.border,
    required this.borderStrong,
    required this.surface,
    required this.surfaceAlt,
    required this.canvas,
    required this.heroStart,
    required this.heroEnd,
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
    required this.fuelSuper,
    required this.fuelRegular,
    required this.fuelDiesel,
  });

  final Color brand;
  final Color brandContainer;

  /// Text/icon colour on top of a [brand] fill.
  final Color onBrand;
  final Color ink;
  final Color muted;
  final Color border;

  /// Border of interactive controls (>= 3:1 against the surface).
  final Color borderStrong;
  final Color surface;

  /// Slightly tinted surface for inset areas and tracks.
  final Color surfaceAlt;

  /// Page background.
  final Color canvas;
  final Color heroStart;
  final Color heroEnd;
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

  /// Fuel colours safe to use as TEXT on [surface] (AA). The pure marketing
  /// colours live in [fuelFill].
  final Color fuelSuper;
  final Color fuelRegular;
  final Color fuelDiesel;

  /// Action colour alias (DESIGN.md "action").
  Color get action => brand;

  static const light = DlcColors(
    brand: Color(0xffc2410c),
    brandContainer: Color(0xffffebdc),
    onBrand: Color(0xffffffff),
    ink: Color(0xff1c1917),
    muted: Color(0xff675e56),
    border: Color(0xffe4ddd3),
    borderStrong: Color(0xff8c8176),
    surface: Color(0xfffffefc),
    surfaceAlt: Color(0xfff2ece3),
    canvas: Color(0xfff7f3ed),
    heroStart: Color(0xff9a1717),
    heroEnd: Color(0xffc2410c),
    optimal: Color(0xff23704a),
    medium: Color(0xff8a5a00),
    critical: Color(0xffb3261e),
    warning: Color(0xff9a4a00),
    info: Color(0xff2f5d8a),
    optimalContainer: Color(0xffe2f1e6),
    mediumContainer: Color(0xfffff2db),
    criticalContainer: Color(0xffffeae5),
    warningContainer: Color(0xffffeed9),
    infoContainer: Color(0xffe3edf7),
    fuelSuper: Color(0xffc62828),
    fuelRegular: Color(0xff2e7d32),
    fuelDiesel: Color(0xff8a5a00),
  );

  static const dark = DlcColors(
    brand: Color(0xffff9a55),
    brandContainer: Color(0xff4a2316),
    onBrand: Color(0xff1c1917),
    ink: Color(0xfff3eee8),
    muted: Color(0xffb5aca2),
    border: Color(0xff3a352f),
    borderStrong: Color(0xff8a8076),
    surface: Color(0xff1f1c19),
    surfaceAlt: Color(0xff2a2622),
    canvas: Color(0xff151311),
    heroStart: Color(0xff6f1212),
    heroEnd: Color(0xffa23209),
    optimal: Color(0xff63c797),
    medium: Color(0xfff0be55),
    critical: Color(0xffff8f86),
    warning: Color(0xffffb35c),
    info: Color(0xff8cbcf0),
    optimalContainer: Color(0xff16342a),
    mediumContainer: Color(0xff3b2e0e),
    criticalContainer: Color(0xff4a2420),
    warningContainer: Color(0xff402a0e),
    infoContainer: Color(0xff1b3248),
    fuelSuper: Color(0xffff8a80),
    fuelRegular: Color(0xff81c784),
    fuelDiesel: Color(0xfffbc02d),
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

  /// Text-safe colour of a fuel family (`super`, `regular`, `diesel`).
  Color fuelText(String? family) => switch (family) {
    'super' => fuelSuper,
    'regular' => fuelRegular,
    'diesel' => fuelDiesel,
    _ => brand,
  };

  /// Pure fuel colour (DESIGN.md) for fills, dots and bars. Diesel amber
  /// needs dark text on top.
  static Color fuelFill(String? family) => switch (family) {
    'super' => const Color(0xffc62828),
    'regular' => const Color(0xff2e7d32),
    'diesel' => const Color(0xfff9a825),
    _ => DlcBrand.orange,
  };

  /// Maps the free-text fuel name to a family when the server omits it.
  static String fuelFamilyOf(String? family, [String? name]) {
    final raw = (family ?? '').trim().toLowerCase();
    if (raw == 'super' || raw == 'regular' || raw == 'diesel') return raw;
    final n = (name ?? '')
        .toLowerCase()
        .replaceAll('ú', 'u')
        .replaceAll('é', 'e');
    if (n.contains('super')) return 'super';
    if (n.contains('regular')) return 'regular';
    if (n.contains('diesel')) return 'diesel';
    return 'other';
  }

  LinearGradient get heroGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [heroStart, heroEnd],
  );

  @override
  DlcColors copyWith({
    Color? brand,
    Color? brandContainer,
    Color? onBrand,
    Color? ink,
    Color? muted,
    Color? border,
    Color? borderStrong,
    Color? surface,
    Color? surfaceAlt,
    Color? canvas,
    Color? heroStart,
    Color? heroEnd,
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
    Color? fuelSuper,
    Color? fuelRegular,
    Color? fuelDiesel,
  }) => DlcColors(
    brand: brand ?? this.brand,
    brandContainer: brandContainer ?? this.brandContainer,
    onBrand: onBrand ?? this.onBrand,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    border: border ?? this.border,
    borderStrong: borderStrong ?? this.borderStrong,
    surface: surface ?? this.surface,
    surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    canvas: canvas ?? this.canvas,
    heroStart: heroStart ?? this.heroStart,
    heroEnd: heroEnd ?? this.heroEnd,
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
    fuelSuper: fuelSuper ?? this.fuelSuper,
    fuelRegular: fuelRegular ?? this.fuelRegular,
    fuelDiesel: fuelDiesel ?? this.fuelDiesel,
  );

  @override
  DlcColors lerp(ThemeExtension<DlcColors>? other, double t) {
    if (other is! DlcColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return DlcColors(
      brand: mix(brand, other.brand),
      brandContainer: mix(brandContainer, other.brandContainer),
      onBrand: mix(onBrand, other.onBrand),
      ink: mix(ink, other.ink),
      muted: mix(muted, other.muted),
      border: mix(border, other.border),
      borderStrong: mix(borderStrong, other.borderStrong),
      surface: mix(surface, other.surface),
      surfaceAlt: mix(surfaceAlt, other.surfaceAlt),
      canvas: mix(canvas, other.canvas),
      heroStart: mix(heroStart, other.heroStart),
      heroEnd: mix(heroEnd, other.heroEnd),
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
      fuelSuper: mix(fuelSuper, other.fuelSuper),
      fuelRegular: mix(fuelRegular, other.fuelRegular),
      fuelDiesel: mix(fuelDiesel, other.fuelDiesel),
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

/// Type scale (DESIGN.md section 2): 12, 14, 16, 20, 24, 32. Titles 600-700.
TextTheme _textTheme(DlcColors c, TextTheme base) {
  TextStyle s(double size, FontWeight w, {double? height}) => TextStyle(
    fontSize: size,
    fontWeight: w,
    color: c.ink,
    height: height,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  return base.copyWith(
    displaySmall: s(32, FontWeight.w700, height: 1.15),
    headlineMedium: s(32, FontWeight.w700, height: 1.15),
    headlineSmall: s(24, FontWeight.w700, height: 1.2),
    titleLarge: s(20, FontWeight.w700, height: 1.25),
    titleMedium: s(16, FontWeight.w600, height: 1.3),
    titleSmall: s(14, FontWeight.w600, height: 1.3),
    bodyLarge: s(16, FontWeight.w400, height: 1.4),
    bodyMedium: s(14, FontWeight.w400, height: 1.4),
    bodySmall: s(12, FontWeight.w400, height: 1.35),
    labelLarge: s(14, FontWeight.w600),
    labelMedium: s(12, FontWeight.w600),
    labelSmall: s(12, FontWeight.w500),
  );
}

ThemeData buildDlcTheme(Brightness brightness) {
  final c = DlcColors.of(brightness);
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: DlcColors.light.brand,
        brightness: brightness,
      ).copyWith(
        primary: c.brand,
        onPrimary: c.onBrand,
        primaryContainer: c.brandContainer,
        onPrimaryContainer: dark ? c.ink : DlcColors.light.brand,
        secondary: c.ink,
        onSecondary: c.surface,
        surface: c.surface,
        onSurface: c.ink,
        onSurfaceVariant: c.muted,
        surfaceContainerLowest: c.surface,
        surfaceContainerLow: c.surface,
        surfaceContainer: c.surfaceAlt,
        surfaceContainerHigh: c.surfaceAlt,
        surfaceContainerHighest: c.surfaceAlt,
        outline: c.borderStrong,
        outlineVariant: c.border,
        error: c.critical,
        onError: dark ? DlcBrand.inkWarm : Colors.white,
        errorContainer: c.criticalContainer,
        onErrorContainer: c.critical,
      );
  OutlineInputBorder outline(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
  );
  const minTouch = Size(44, 48);
  return base.copyWith(
    scaffoldBackgroundColor: c.canvas,
    textTheme: _textTheme(c, base.textTheme),
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: c.ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    dividerTheme: DividerThemeData(color: c.border, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: outline(c.borderStrong),
      enabledBorder: outline(c.borderStrong),
      focusedBorder: outline(c.brand, 2),
      errorBorder: outline(c.critical),
      focusedErrorBorder: outline(c.critical, 2),
      labelStyle: TextStyle(color: c.muted),
      helperStyle: TextStyle(color: c.muted),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.brand,
        foregroundColor: c.onBrand,
        minimumSize: minTouch,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: BorderSide(color: c.borderStrong),
        minimumSize: minTouch,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.brand,
        minimumSize: minTouch,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.brand,
      foregroundColor: c.onBrand,
      elevation: 2,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(0, 44),
        side: BorderSide(color: c.borderStrong),
        foregroundColor: c.ink,
        selectedBackgroundColor: c.brandContainer,
        selectedForegroundColor: dark ? c.ink : DlcColors.light.brand,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.brandContainer,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? c.ink : c.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? (dark ? c.ink : DlcColors.light.brand)
              : c.muted,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surfaceAlt,
      side: BorderSide(color: c.border),
      labelStyle: TextStyle(
        color: c.ink,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? c.surfaceAlt : c.ink,
      contentTextStyle: TextStyle(color: dark ? c.ink : c.surface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.muted,
      textColor: c.ink,
      minVerticalPadding: 8,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.brand),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

final ThemeData lightTheme = buildDlcTheme(Brightness.light);
final ThemeData darkTheme = buildDlcTheme(Brightness.dark);

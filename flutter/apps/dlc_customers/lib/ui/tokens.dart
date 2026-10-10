import 'package:flutter/material.dart';

/// Brand colours sampled from the DLC logo (DESIGN.md section 1).
abstract final class DlcBrand {
  static const yellow = Color(0xFFFBBD29);
  static const amber = Color(0xFFFB9F41);
  static const orange = Color(0xFFFB7911);
  static const red = Color(0xFFA21A1A);
  static const ink = Color(0xFF1C1917);

  /// Burnt orange for filled buttons with white text (>= 4.5:1 on white).
  static const action = Color(0xFFC2410C);

  /// Hero gradient. Text on it is always [ink] (>= 6.5:1 on every stop).
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [yellow, amber, orange],
  );
}

/// Foreground + container pair used for semantic and decorative tones.
@immutable
class DlcTone {
  const DlcTone(this.fg, this.bg, [this.bar]);
  final Color fg;
  final Color bg;

  /// Fill colour for progress bars on top of [bg] (>= 3:1 against [bg]).
  final Color? bar;
}

/// Semantic and decorative tokens that Material's ColorScheme lacks.
/// Defined once per brightness (DESIGN.md: tokens once, both modes derived).
@immutable
class DlcColors extends ThemeExtension<DlcColors> {
  const DlcColors({
    required this.ok,
    required this.warn,
    required this.crit,
    required this.info,
    required this.accents,
    required this.paper,
    required this.card,
  });

  final DlcTone ok, warn, crit, info;

  /// Four colourful tones (orange, amber, red, yellow) for reward cards.
  final List<DlcTone> accents;
  final Color paper, card;

  static const light = DlcColors(
    ok: DlcTone(Color(0xFF166534), Color(0xFFDCFCE7)),
    warn: DlcTone(Color(0xFF92400E), Color(0xFFFEF3C7)),
    crit: DlcTone(Color(0xFFB91C1C), Color(0xFFFEE2E2)),
    info: DlcTone(Color(0xFF334E68), Color(0xFFE3EAF2)),
    accents: [
      DlcTone(Color(0xFF7C2D12), Color(0xFFFFEDD5), Color(0xFFC2410C)),
      DlcTone(Color(0xFF78350F), Color(0xFFFEF3C7), Color(0xFFB45309)),
      DlcTone(Color(0xFF7F1D1D), Color(0xFFFEE2E2), Color(0xFFB91C1C)),
      DlcTone(Color(0xFF713F12), Color(0xFFFEF9C3), Color(0xFFA16207)),
    ],
    paper: Color(0xFFFAF7F2),
    card: Color(0xFFFFFFFF),
  );

  static const dark = DlcColors(
    ok: DlcTone(Color(0xFF86EFAC), Color(0xFF12351F)),
    warn: DlcTone(Color(0xFFFCD34D), Color(0xFF3A2506)),
    crit: DlcTone(Color(0xFFFCA5A5), Color(0xFF4A1818)),
    info: DlcTone(Color(0xFFB6C8DB), Color(0xFF232F3C)),
    accents: [
      DlcTone(Color(0xFFFFEDD5), Color(0xFF3B1A0C), Color(0xFFFB9F41)),
      DlcTone(Color(0xFFFEF3C7), Color(0xFF3A2608), Color(0xFFFBBD29)),
      DlcTone(Color(0xFFFEE2E2), Color(0xFF3F1414), Color(0xFFF87171)),
      DlcTone(Color(0xFFFEF9C3), Color(0xFF33300A), Color(0xFFFACC15)),
    ],
    paper: Color(0xFF12100E),
    card: Color(0xFF1C1917),
  );

  @override
  DlcColors copyWith({
    DlcTone? ok,
    DlcTone? warn,
    DlcTone? crit,
    DlcTone? info,
    List<DlcTone>? accents,
    Color? paper,
    Color? card,
  }) => DlcColors(
    ok: ok ?? this.ok,
    warn: warn ?? this.warn,
    crit: crit ?? this.crit,
    info: info ?? this.info,
    accents: accents ?? this.accents,
    paper: paper ?? this.paper,
    card: card ?? this.card,
  );

  @override
  DlcColors lerp(ThemeExtension<DlcColors>? other, double t) =>
      other is DlcColors && t >= 0.5 ? other : this;
}

extension DlcThemeContext on BuildContext {
  DlcColors get dlc {
    final theme = Theme.of(this);
    return theme.extension<DlcColors>() ??
        (theme.brightness == Brightness.dark
            ? DlcColors.dark
            : DlcColors.light);
  }
}

/// Custom ease-out (DESIGN.md section 8): never ease-in.
const Curve dlcEaseOut = Cubic(0.2, 0, 0, 1);

/// Motion budget: nothing longer than 300 ms.
const Duration dlcMotion = Duration(milliseconds: 280);
const Duration dlcPress = Duration(milliseconds: 150);

/// Brand theme for one brightness. Light and dark share component theming;
/// only the palette differs.
ThemeData buildDlcTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final tokens = dark ? DlcColors.dark : DlcColors.light;
  final base = ColorScheme.fromSeed(
    seedColor: DlcBrand.orange,
    brightness: brightness,
  );
  final scheme = base.copyWith(
    primary: dark ? DlcBrand.amber : DlcBrand.action,
    onPrimary: dark ? DlcBrand.ink : Colors.white,
    primaryContainer: dark ? const Color(0xFF4A1D0A) : const Color(0xFFFFEDD5),
    onPrimaryContainer: dark
        ? const Color(0xFFFFEDD5)
        : const Color(0xFF7C2D12),
    secondary: dark ? DlcBrand.yellow : const Color(0xFFB45309),
    onSecondary: dark ? DlcBrand.ink : Colors.white,
    secondaryContainer: dark
        ? const Color(0xFF422006)
        : const Color(0xFFFEF3C7),
    onSecondaryContainer: dark
        ? const Color(0xFFFEF3C7)
        : const Color(0xFF78350F),
    tertiary: dark ? const Color(0xFFF87171) : DlcBrand.red,
    onTertiary: dark ? const Color(0xFF450A0A) : Colors.white,
    tertiaryContainer: dark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2),
    onTertiaryContainer: dark
        ? const Color(0xFFFEE2E2)
        : const Color(0xFF7F1D1D),
    error: dark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
    onError: dark ? const Color(0xFF450A0A) : Colors.white,
    errorContainer: dark ? const Color(0xFF4A1818) : const Color(0xFFFEE2E2),
    onErrorContainer: dark ? const Color(0xFFFEE2E2) : const Color(0xFF7F1D1D),
    surface: tokens.card,
    onSurface: dark ? const Color(0xFFF5F0EB) : DlcBrand.ink,
    onSurfaceVariant: dark ? const Color(0xFFBDB4AB) : const Color(0xFF57534E),
    outline: dark ? const Color(0xFF948B82) : const Color(0xFF78716C),
    outlineVariant: dark ? const Color(0xFF3A332E) : const Color(0xFFE7E0D8),
    surfaceContainerLowest: dark ? tokens.paper : Colors.white,
    surfaceContainerLow: dark
        ? const Color(0xFF181513)
        : const Color(0xFFFBF8F4),
    surfaceContainer: dark ? const Color(0xFF211D1A) : const Color(0xFFF5F0EA),
    surfaceContainerHigh: dark
        ? const Color(0xFF2A2521)
        : const Color(0xFFEFE8E0),
    surfaceContainerHighest: dark
        ? const Color(0xFF332D29)
        : const Color(0xFFE7DFD6),
    surfaceTint: Colors.transparent,
  );
  final radius14 = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.paper,
    extensions: [tokens],
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.paper,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: tokens.card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: radius14,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: radius14,
        side: BorderSide(color: scheme.outline),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: radius14,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: radius14,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(0, 44),
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
      ),
    ),
  );
}

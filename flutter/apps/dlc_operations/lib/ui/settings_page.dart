import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../format.dart';
import '../haptics.dart';
import '../preferences.dart';
import '../theme_mode_controller.dart';
import 'kit.dart';
import 'motion.dart';

/// Profile and preferences: theme, volume unit and decimals (per user,
/// persisted through the session's secure preferences).
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.theme,
    required this.prefs,
    required this.identity,
    required this.onLogout,
    super.key,
  });
  final ThemeModeController theme;
  final DisplayPrefsController prefs;
  final EmployeeIdentity? identity;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Configuración')),
    body: SettingsBody(
      theme: theme,
      prefs: prefs,
      identity: identity,
      onLogout: onLogout,
    ),
  );
}

class SettingsBody extends StatelessWidget {
  const SettingsBody({
    required this.theme,
    required this.prefs,
    required this.identity,
    required this.onLogout,
    super.key,
  });
  final ThemeModeController theme;
  final DisplayPrefsController prefs;
  final EmployeeIdentity? identity;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final user = identity;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (user != null)
          Entrance(
            child: DlcCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: c.brandContainer,
                    child: Text(
                      _initials(user.displayName),
                      style: TextStyle(
                        color: c.brand,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.muted, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.roles.map((r) => r.name).toSet().join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SectionHeader(title: 'Apariencia', icon: CupertinoIcons.sun_max),
        Entrance(
          index: 1,
          child: DlcCard(
            child: ListenableBuilder(
              listenable: theme,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tema',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SegmentedFilter<ThemeMode>(
                    semanticLabel: 'Tema',
                    selected: theme.mode,
                    options: {
                      for (final m in ThemeMode.values) m: themeModeLabel(m),
                    },
                    onChanged: (m) {
                      Haptics.selection();
                      theme.select(m);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        const SectionHeader(
          title: 'Números y unidades',
          icon: CupertinoIcons.slider_horizontal_3,
        ),
        Entrance(
          index: 2,
          child: ListenableBuilder(
            listenable: prefs,
            builder: (context, _) => DlcCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Unidad de volumen',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SegmentedFilter<VolumeUnit>(
                    semanticLabel: 'Unidad de volumen',
                    selected: prefs.prefs.unit,
                    options: {for (final u in VolumeUnit.values) u: u.label},
                    onChanged: (u) {
                      Haptics.selection();
                      prefs.setUnit(u);
                    },
                  ),
                  const SizedBox(height: 18),
                  _DecimalsStepper(
                    value: prefs.prefs.decimals,
                    onChanged: (v) {
                      Haptics.selection();
                      prefs.setDecimals(v);
                    },
                  ),
                  const SizedBox(height: 14),
                  _Preview(prefs: prefs.prefs),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'La moneda de cada importe sale de la sucursal: no se suman monedas distintas.',
          style: TextStyle(color: c.muted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: onLogout,
          icon: const Icon(CupertinoIcons.square_arrow_left, size: 18),
          label: const Text('Cerrar sesión'),
          style: OutlinedButton.styleFrom(
            foregroundColor: c.critical,
            side: BorderSide(color: c.critical),
          ),
        ),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _DecimalsStepper extends StatelessWidget {
  const _DecimalsStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Decimales',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                'Para dinero y precios (0 a $kMaxDecimals).',
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _RoundButton(
          icon: CupertinoIcons.minus,
          label: 'Menos decimales',
          onPressed: value > kMinDecimals ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$value',
            key: const Key('decimals-value'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        _RoundButton(
          icon: CupertinoIcons.plus,
          label: 'Más decimales',
          onPressed: value < kMaxDecimals ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton.outlined(
    onPressed: onPressed,
    tooltip: label,
    icon: Icon(icon, size: 18),
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
  );
}

class _Preview extends StatelessWidget {
  const _Preview({required this.prefs});
  final DisplayPrefs prefs;
  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return DlcCard(
      weight: CardWeight.quiet,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vista previa', style: TextStyle(color: c.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            '${prefs.price(0.9124, currency: 'USD')}  ·  ${prefs.money(1234.5)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            '${prefs.volumeCard(15000)} en tanque · ${prefs.volumeDetail(1234.567)} despachados',
            style: TextStyle(color: c.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

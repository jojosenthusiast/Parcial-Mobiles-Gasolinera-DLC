import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../haptics.dart';
import 'format.dart';
import 'settings.dart';
import 'tokens.dart';
import 'widgets.dart';

/// Mi codigo: the QR always sits on white with a quiet zone, in both themes,
/// so scanners can read it in dark mode too.
class QrPage extends StatelessWidget {
  const QrPage({super.key, required this.qr});
  final Map<String, dynamic>? qr;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final code = qr?['code'];
    final message = asStr(qr?['message']);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Semantics(
          header: true,
          child: const Text(
            'Mi código',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        Reveal(
          group: 'qr',
          child: DlcCard(
            weight: CardWeight.standard,
            child: Column(
              children: [
                const BrandDrop(size: 32),
                const SizedBox(height: 6),
                Text(
                  'Muéstralo en caja',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 14),
                if (code is String && code.isNotEmpty)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final side = math.min(220.0, constraints.maxWidth - 40);
                      return Semantics(
                        label: 'Código QR de tu cuenta DLC',
                        image: true,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          // Quiet zone: white margin around the modules.
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: QrImageView(
                              data: code,
                              size: math.max(120, side),
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
                  )
                else if (qr == null)
                  const SkeletonPulse(
                    child: SkeletonBox(width: 220, height: 220, radius: 16),
                  )
                else
                  const EmptyState(
                    icon: CupertinoIcons.qrcode,
                    message:
                        'Tu código aún no está disponible. Desliza hacia abajo para actualizar.',
                  ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
                if (code is String && code.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SelectableText(
                    code,
                    textAlign: TextAlign.center,
                    style: numeric(
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Perfil: identity, preferences (tema, unidad, decimales) and logout.
class AccountPage extends StatelessWidget {
  const AccountPage({
    super.key,
    required this.profile,
    required this.email,
    required this.busy,
    required this.onSignOut,
  });
  final Map<String, dynamic>? profile;
  final String? email;
  final bool busy;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = SettingsScope.of(context);
    final name = asStr(profile?['fullName']).trim();
    final phone = asStr(profile?['phone']).trim();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Semantics(
          header: true,
          child: const Text(
            'Perfil',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        DlcCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      gradient: DlcBrand.heroGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      initialsOf(name),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: DlcBrand.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'Cliente DLC' : name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if ((email ?? '').isNotEmpty)
                          Text(
                            email!,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              _InfoRow(
                icon: CupertinoIcons.phone,
                label: 'Teléfono',
                value: phone.isEmpty ? 'No registrado' : phone,
              ),
              _InfoRow(
                icon: CupertinoIcons.calendar,
                label: 'Cuenta desde',
                value: formatDate(profile?['createdAt']),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DlcCard(
          weight: CardWeight.compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: CupertinoIcons.slider_horizontal_3,
                title: 'Configuración',
              ),
              const _FieldLabel('Tema'),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(CupertinoIcons.sun_max, size: 18),
                      label: Text('Claro'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(CupertinoIcons.moon, size: 18),
                      label: Text('Oscuro'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(CupertinoIcons.circle_lefthalf_fill, size: 18),
                      label: Text('Sistema'),
                    ),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (selection) {
                    Haptics.selection();
                    settings.themeMode = selection.first;
                  },
                ),
              ),
              const SizedBox(height: 16),
              const _FieldLabel('Unidad de volumen'),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<VolumeUnit>(
                  showSelectedIcon: false,
                  segments: [
                    for (final unit in VolumeUnit.values)
                      ButtonSegment(
                        value: unit,
                        icon: const Icon(CupertinoIcons.drop, size: 18),
                        label: Text(unit.label),
                      ),
                  ],
                  selected: {settings.volumeUnit},
                  onSelectionChanged: (selection) {
                    Haptics.selection();
                    settings.volumeUnit = selection.first;
                  },
                ),
              ),
              const SizedBox(height: 16),
              const _FieldLabel('Decimales en importes'),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (var d = 0; d <= 4; d++)
                      ButtonSegment(value: d, label: Text('$d')),
                  ],
                  selected: {settings.decimals},
                  onSelectionChanged: (selection) {
                    Haptics.selection();
                    settings.decimals = selection.first;
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ejemplo: ${settings.money(1234.5)}',
                style: numeric(
                  TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        DlcButton(
          label: 'Cerrar sesión',
          icon: CupertinoIcons.arrow_right_square,
          kind: DlcButtonKind.danger,
          onPressed: busy ? null : onSignOut,
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(value, style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

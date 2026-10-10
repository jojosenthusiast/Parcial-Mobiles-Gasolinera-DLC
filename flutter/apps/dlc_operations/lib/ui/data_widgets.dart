import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../format.dart';
import '../labels.dart';
import '../tank_levels.dart';
import 'gauges.dart';
import 'kit.dart';
import 'motion.dart';

// ---------------------------------------------------------------------------
// Alerts
// ---------------------------------------------------------------------------

@immutable
class AlertItem {
  const AlertItem({
    required this.title,
    required this.detail,
    required this.severity,
    this.branchName,
  });
  final String title;
  final String detail;

  /// `critical`, `high`, `warning`, `medium`, `low`...
  final String severity;
  final String? branchName;

  bool get isCritical => severity == 'critical' || severity == 'high';
}

/// Alerts sorted by severity (most severe first, stable).
List<AlertItem> sortAlerts(Iterable<AlertItem> items) {
  final list = items.toList();
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final bySeverity = severityRank(a.$2.severity).compareTo(
      severityRank(b.$2.severity),
    );
    return bySeverity != 0 ? bySeverity : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Strip at the very top of the summary: critical things first. Collapsed to
/// one line, expands to the list.
class AlertStrip extends StatefulWidget {
  const AlertStrip({required this.items, this.collapsedLimit = 3, super.key});
  final List<AlertItem> items;
  final int collapsedLimit;
  @override
  State<AlertStrip> createState() => _AlertStripState();
}

class _AlertStripState extends State<AlertStrip> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final items = sortAlerts(widget.items);
    if (items.isEmpty) {
      return DlcCard(
        weight: CardWeight.quiet,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(CupertinoIcons.checkmark_circle, color: c.optimal, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sin alertas activas',
                style: TextStyle(color: c.optimal, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    final critical = items.where((i) => i.isCritical).length;
    final tone = critical > 0 ? DlcStatus.critical : DlcStatus.warning;
    final fg = c.foreground(tone);
    final shown = _open ? items : items.take(1).toList();
    return DlcCard(
      color: c.container(tone),
      padding: EdgeInsets.zero,
      semanticLabel:
          '${items.length} alertas, $critical críticas. ${items.first.title}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: items.length > 1
                ? () => setState(() => _open = !_open)
                : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    Icon(tone.icon, color: fg, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        critical > 0
                            ? '$critical ${critical == 1 ? 'alerta crítica' : 'alertas críticas'}'
                                  '${items.length > critical ? ' · ${items.length - critical} más' : ''}'
                            : '${items.length} ${items.length == 1 ? 'alerta' : 'alertas'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (items.length > 1)
                      Icon(
                        _open
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down,
                        size: 16,
                        color: fg,
                      ),
                  ],
                ),
              ),
            ),
          ),
          for (final a in shown.take(_open ? 12 : 1))
            Padding(
              padding: const EdgeInsets.fromLTRB(46, 0, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.branchName == null ? a.title : '${a.branchName}: ${a.title}',
                    style: TextStyle(
                      color: c.ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (a.detail.isNotEmpty)
                    Text(
                      a.detail,
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KPI tiles
// ---------------------------------------------------------------------------

/// The one dominant figure of a screen: gradient card, large number counted
/// up once, optional second line (other currencies) and context chips.
class HeroKpi extends StatelessWidget {
  const HeroKpi({
    required this.label,
    required this.value,
    required this.format,
    this.caption,
    this.extra,
    this.icon = CupertinoIcons.chart_bar,
    super.key,
  });
  final String label;
  final double value;
  final String Function(double) format;
  final String? caption;
  final String? extra;
  final IconData icon;

  @override
  Widget build(BuildContext context) => DlcCard(
    weight: CardWeight.hero,
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    semanticLabel: '$label: ${format(value)}',
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: CountUp(
                  value: value,
                  format: format,
                  style: const TextStyle(
                    fontSize: 38,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (extra != null) ...[
                const SizedBox(height: 4),
                Text(
                  extra!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
              if (caption != null) ...[
                const SizedBox(height: 6),
                Text(
                  caption!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Color(0xffffe9d6)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        const BrandDrop(size: 52),
      ],
    ),
  );
}

/// Secondary figure: flat tile, small number, two-line label.
class MiniKpi extends StatelessWidget {
  const MiniKpi({
    required this.icon,
    required this.value,
    required this.label,
    this.tone,
    super.key,
  });
  final IconData icon;
  final String value;
  final String label;
  final DlcStatus? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final fg = tone == null ? c.muted : c.foreground(tone!);
    return DlcCard(
      weight: CardWeight.quiet,
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      semanticLabel: '$label: $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.muted, fontSize: 12, height: 1.25),
          ),
        ],
      ),
    );
  }
}

/// Three secondary KPIs in one row (equal width, never wraps).
class MiniKpiRow extends StatelessWidget {
  const MiniKpiRow({required this.tiles, super.key});
  final List<MiniKpi> tiles;
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: tiles[i]),
        ],
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Tank card
// ---------------------------------------------------------------------------

/// One tank: vertical gauge + percent + status in words + litres.
class TankCard extends StatelessWidget {
  const TankCard({
    required this.tank,
    required this.prefs,
    this.branchName,
    super.key,
  });
  final Map<String, dynamic> tank;
  final DisplayPrefs prefs;
  final String? branchName;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final pct = tankPercent(tank);
    final status = pct == null ? null : tankStatusForPercent(pct);
    final fg = status == null ? c.muted : c.foreground(status);
    final family = DlcColors.fuelFamilyOf(
      tank['family']?.toString(),
      tank['fuelName']?.toString(),
    );
    final fuel = (tank['fuelName'] ?? fuelFamilyLabel(family)).toString();
    final code = (tank['code'] ?? '').toString();
    final onHand = parseAmount(tank['onHandLiters']);
    final capacity = parseAmount(tank['capacityLiters']);
    final statusText = status == null ? 'Sin medición' : tankStatusText(status);
    return DlcCard(
      padding: const EdgeInsets.all(12),
      semanticLabel:
          '${branchName == null ? '' : '$branchName, '}$fuel $code: ${pct == null ? 'sin medición' : '${pct.toStringAsFixed(0)} %, ${statusText.toLowerCase()}'}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            TankGauge(percent: pct),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: DlcColors.fuelFill(family),
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 10, height: 10),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          code.isEmpty ? fuel : '$fuel · $code',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pct == null ? '-- %' : '${pct.toStringAsFixed(0)} %',
                    style: TextStyle(
                      color: fg,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(status?.icon ?? CupertinoIcons.question_circle, size: 14, color: fg),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: fg,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    onHand == null
                        ? 'Sin saldo'
                        : '${prefs.volumeCard(onHand)}${capacity == null ? '' : ' de ${prefs.volumeCard(capacity)}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two columns when there is room, one when narrow or at large text.
class ResponsiveWrap extends StatelessWidget {
  const ResponsiveWrap({
    required this.children,
    this.minItemWidth = 280,
    this.spacing = 10,
    super.key,
  });
  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = (box.maxWidth / minItemWidth).floor().clamp(1, 3);
      final width = (box.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final (i, w) in children.indexed)
            SizedBox(
              width: width,
              child: Entrance(index: i, child: w),
            ),
        ],
      );
    },
  );
}

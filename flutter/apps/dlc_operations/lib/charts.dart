import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'tank_levels.dart';

/// Plain `CustomPaint` charts: no packages, each with a text alternative.

/// Formats a number with thousands separators and fixed decimals (es style
/// is not needed for the UI; a comma grouping keeps it compact).
String groupedNumber(double value, {int decimals = 0}) {
  final fixed = value.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final sign = parts.first.startsWith('-') ? '-' : '';
  final digits = parts.first.replaceFirst('-', '');
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '$sign$buffer${parts.length > 1 ? '.${parts[1]}' : ''}';
}

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

// ---------------------------------------------------------------------------
// Tank level bars
// ---------------------------------------------------------------------------

class TankBarPainter extends CustomPainter {
  const TankBarPainter({
    required this.fraction,
    required this.fill,
    required this.track,
    required this.tick,
  });

  /// 0..1
  final double fraction;
  final Color fill;
  final Color track;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final trackRect = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(trackRect, Paint()..color = track);
    final width = size.width * fraction.clamp(0, 1);
    if (width > 0) {
      canvas.save();
      canvas.clipRRect(trackRect);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width < size.height ? size.height : width, size.height),
        Paint()..color = fill,
      );
      canvas.restore();
    }
    // Threshold ticks at the critical and medium limits.
    final tickPaint = Paint()
      ..color = tick
      ..strokeWidth = 1.5;
    for (final limit in [kTankCriticalMaxPercent, kTankMediumMaxPercent]) {
      final x = size.width * limit / 100;
      canvas.drawLine(Offset(x, 2), Offset(x, size.height - 2), tickPaint);
    }
  }

  @override
  bool shouldRepaint(TankBarPainter old) =>
      old.fraction != fraction ||
      old.fill != fill ||
      old.track != track ||
      old.tick != tick;
}

/// Per-fuel level bars (Súper / Regular / Diésel) coloured by status. Every
/// bar shows an icon, the label, the percentage and the status in words.
class TankLevelBars extends StatelessWidget {
  const TankLevelBars({required this.levels, super.key});
  final List<FuelLevel> levels;

  @override
  Widget build(BuildContext context) {
    if (levels.isEmpty) {
      return Text(
        'Sin tanques configurados.',
        style: TextStyle(color: context.dlc.muted),
      );
    }
    final colors = context.dlc;
    return Semantics(
      container: true,
      label:
          'Nivel de combustible por tipo. ${levels.map((l) => l.description).join('. ')}.',
      child: ExcludeSemantics(
        child: Column(
          children: [
            for (var i = 0; i < levels.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _TankLevelRow(level: levels[i], colors: colors),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Marcas en 30 % (crítico) y 60 % (medio).',
                style: TextStyle(color: colors.muted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TankLevelRow extends StatelessWidget {
  const _TankLevelRow({required this.level, required this.colors});
  final FuelLevel level;
  final DlcColors colors;

  @override
  Widget build(BuildContext context) {
    final status = level.status;
    final fg = status == null ? colors.muted : colors.foreground(status);
    final icon = status?.icon ?? Icons.help_outline;
    final percent = level.percent;
    final statusText = status == null
        ? 'Sin medición'
        : tankStatusText(status) + (level.isPartial ? ' (parcial)' : '');
    final duration = _reduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                level.label,
                style: TextStyle(
                  color: colors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              percent == null ? '— %' : '${percent.toStringAsFixed(0)} %',
              style: TextStyle(color: fg, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(
          tween: Tween(end: (percent ?? 0) / 100),
          duration: duration,
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => SizedBox(
            height: 14,
            width: double.infinity,
            child: CustomPaint(
              painter: TankBarPainter(
                fraction: value,
                fill: fg,
                track: colors.border,
                tick: colors.surface,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          percent == null
              ? statusText
              : '$statusText · ${groupedNumber(level.liters)} L de ${groupedNumber(level.capacityLiters)} L'
                    '${level.tankCount > 1 ? ' · ${level.tankCount} tanques' : ''}',
          style: TextStyle(color: colors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Trend bar chart
// ---------------------------------------------------------------------------

class TrendPoint {
  const TrendPoint(this.label, this.value);
  final String label;
  final double value;
}

class TrendSummary {
  const TrendSummary({
    required this.total,
    required this.average,
    required this.best,
    required this.worst,
  });
  final double total;
  final double average;
  final TrendPoint? best;
  final TrendPoint? worst;
}

/// Pure statistics behind the chart caption and its text alternative.
TrendSummary summarizeTrend(List<TrendPoint> points) {
  if (points.isEmpty) {
    return const TrendSummary(total: 0, average: 0, best: null, worst: null);
  }
  final total = points.fold<double>(0, (s, p) => s + p.value);
  var best = points.first, worst = points.first;
  for (final p in points) {
    if (p.value > best.value) best = p;
    if (p.value < worst.value) worst = p;
  }
  return TrendSummary(
    total: total,
    average: total / points.length,
    best: best,
    worst: worst,
  );
}

class TrendBarsPainter extends CustomPainter {
  const TrendBarsPainter({
    required this.values,
    required this.highlightIndex,
    required this.bar,
    required this.highlight,
    required this.grid,
    required this.progress,
  });
  final List<double> values;
  final int highlightIndex;
  final Color bar;
  final Color highlight;
  final Color grid;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = size.height - (size.height - 2) * f - 1;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.isEmpty) return;
    final peak = values.fold<double>(0, (m, v) => v > m ? v : m);
    final slot = size.width / values.length;
    final barWidth = (slot * 0.62).clamp(3.0, 36.0);
    for (var i = 0; i < values.length; i++) {
      final ratio = peak <= 0 ? 0.0 : (values[i] / peak).clamp(0.0, 1.0);
      final h = (size.height - 4) * ratio * progress;
      final left = slot * i + (slot - barWidth) / 2;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, size.height - 1 - (h < 2 ? 2 : h), barWidth, h < 2 ? 2 : h),
        topLeft: const Radius.circular(5),
        topRight: const Radius.circular(5),
      );
      canvas.drawRRect(rect, Paint()..color = i == highlightIndex ? highlight : bar);
    }
  }

  @override
  bool shouldRepaint(TrendBarsPainter old) =>
      old.values != values ||
      old.highlightIndex != highlightIndex ||
      old.bar != bar ||
      old.highlight != highlight ||
      old.grid != grid ||
      old.progress != progress;
}

/// Bar chart for a short series (sales or litres per day). Provides a spoken
/// summary, a visible caption and an expandable table as text alternatives.
class TrendBarChart extends StatelessWidget {
  const TrendBarChart({
    required this.title,
    required this.points,
    required this.format,
    this.color,
    super.key,
  });
  final String title;
  final List<TrendPoint> points;
  final String Function(double value) format;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.dlc;
    if (points.isEmpty) {
      return Text(
        'Sin datos para $title en el período.',
        style: TextStyle(color: colors.muted),
      );
    }
    final summary = summarizeTrend(points);
    final best = summary.best!;
    final caption =
        'Total ${format(summary.total)} · promedio ${format(summary.average)} por día · mejor día ${best.label} (${format(best.value)})';
    final highlightIndex = points.indexOf(best);
    final base = color ?? colors.brand;
    final duration = _reduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 500);
    return Semantics(
      container: true,
      label: '$title. $caption.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bar_chart_rounded, size: 20, color: base),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: colors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      'Máx. ${format(best.value)}',
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  builder: (context, progress, _) => SizedBox(
                    height: 110,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: TrendBarsPainter(
                        values: [for (final p in points) p.value],
                        highlightIndex: highlightIndex,
                        bar: base.withValues(alpha: .55),
                        highlight: base,
                        grid: colors.border,
                        progress: progress,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    for (final p in points)
                      Expanded(
                        child: Text(
                          points.length > 10 ? '' : p.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(color: colors.muted, fontSize: 10),
                        ),
                      ),
                  ],
                ),
                if (points.length > 10)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        points.first.label,
                        style: TextStyle(color: colors.muted, fontSize: 10),
                      ),
                      Text(
                        points.last.label,
                        style: TextStyle(color: colors.muted, fontSize: 10),
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                Text(
                  caption,
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Ver datos como texto'),
              children: [
                for (final p in points)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.label),
                    trailing: Text(
                      format(p.value),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

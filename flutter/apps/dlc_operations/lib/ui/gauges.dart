import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../tank_levels.dart';
import 'motion.dart';

/// Vertical tank gauge painted with CustomPaint: fill coloured by status,
/// ticks at the 30 % and 60 % thresholds.
class TankGaugePainter extends CustomPainter {
  const TankGaugePainter({
    required this.fraction,
    required this.fill,
    required this.track,
    required this.tick,
    required this.outline,
  });
  final double fraction;
  final Color fill, track, tick, outline;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    canvas.drawRRect(body, Paint()..color = track);
    final h = size.height * fraction.clamp(0, 1);
    if (h > 0) {
      canvas.save();
      canvas.clipRRect(body);
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - h, size.width, h),
        Paint()..color = fill,
      );
      canvas.restore();
    }
    final tickPaint = Paint()
      ..color = tick
      ..strokeWidth = 1.5;
    for (final limit in [kTankCriticalMaxPercent, kTankMediumMaxPercent]) {
      final y = size.height * (1 - limit / 100);
      canvas.drawLine(
        Offset(size.width * .55, y),
        Offset(size.width, y),
        tickPaint,
      );
    }
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = outline,
    );
  }

  @override
  bool shouldRepaint(TankGaugePainter old) =>
      old.fraction != fraction ||
      old.fill != fill ||
      old.track != track ||
      old.tick != tick ||
      old.outline != outline;
}

class TankGauge extends StatelessWidget {
  const TankGauge({
    required this.percent,
    this.width = 34,
    this.height = 92,
    super.key,
  });

  /// 0-100, null when there is no measurement.
  final double? percent;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final status = percent == null ? null : tankStatusForPercent(percent!);
    final fg = status == null ? c.muted : c.foreground(status);
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: (percent ?? 0) / 100),
        duration: reduceMotion(context) ? Duration.zero : kEntranceDuration,
        curve: kEaseOut,
        builder: (context, value, _) => SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: TankGaugePainter(
              fraction: value,
              fill: fg,
              track: c.surfaceAlt,
              tick: c.surface,
              outline: c.borderStrong,
            ),
          ),
        ),
      ),
    );
  }
}

@immutable
class BarItem {
  const BarItem({
    required this.label,
    required this.value,
    required this.display,
    this.detail,
    this.color,
  });
  final String label;
  final double value;

  /// Formatted value shown at the end of the bar.
  final String display;
  final String? detail;
  final Color? color;
}

class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.ratio,
    required this.color,
    required this.track,
  });
  final double ratio;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track);
    final w = (size.width * ratio.clamp(0, 1)).clamp(0.0, size.width);
    if (w > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w < size.height ? size.height : w, size.height),
          r,
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.ratio != ratio || old.color != color || old.track != track;
}

/// Horizontal comparison bars (one row per branch): label, value and a bar
/// whose length is relative to the largest value. Text alternative included.
class HBarChart extends StatelessWidget {
  const HBarChart({required this.title, required this.items, super.key});
  final String title;
  final List<BarItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    if (items.isEmpty) return const SizedBox.shrink();
    final peak = items.fold<double>(0, (m, i) => i.value > m ? i.value : m);
    final summary = items.map((i) => '${i.label} ${i.display}').join(', ');
    final duration = reduceMotion(context) ? Duration.zero : kEntranceDuration;
    return Semantics(
      container: true,
      label: '$title. $summary.',
      child: ExcludeSemantics(
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      items[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    items[i].display,
                    maxLines: 1,
                    style: TextStyle(
                      color: c.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0,
                  end: peak <= 0 ? 0 : items[i].value / peak,
                ),
                duration: duration,
                curve: kEaseOut,
                builder: (context, v, _) => SizedBox(
                  height: 10,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _BarPainter(
                      ratio: v,
                      color: items[i].color ?? c.brand,
                      track: c.surfaceAlt,
                    ),
                  ),
                ),
              ),
              if (items[i].detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      items[i].detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.muted, fontSize: 11),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Strong ease-out used by every entrance (DESIGN.md section 8): starts fast,
/// settles softly. Never an ease-in.
const Curve kEaseOut = Cubic(0.23, 1, 0.32, 1);

/// Entrance and counter duration cap (<= 300 ms).
const Duration kEntranceDuration = Duration(milliseconds: 260);
const Duration kStaggerStep = Duration(milliseconds: 45);

bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Fade + 10 px rise on first build. [index] staggers siblings (capped), the
/// animation runs once and never replays on refreshes. With
/// `disableAnimations` the child is shown immediately.
class Entrance extends StatefulWidget {
  const Entrance({required this.child, this.index = 0, super.key});
  final Widget child;
  final int index;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late final Animation<double> _curve;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) return;
    final delay = kStaggerStep * widget.index.clamp(0, 6);
    final total = kEntranceDuration + delay;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _curve = CurvedAnimation(
      parent: controller,
      curve: Interval(
        delay.inMilliseconds / total.inMilliseconds,
        1,
        curve: kEaseOut,
      ),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return widget.child;
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - _curve.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Number that counts up once from zero to [value] (not on every rebuild).
class CountUp extends StatelessWidget {
  const CountUp({
    required this.value,
    required this.format,
    this.style,
    this.maxLines = 1,
    super.key,
  });
  final double value;
  final String Function(double value) format;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) {
      return Text(format(value), style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: kEntranceDuration,
      curve: kEaseOut,
      builder: (context, v, _) => Text(
        format(v),
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

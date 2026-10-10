import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'format.dart';
import 'tokens.dart';

bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

const _tabular = [FontFeature.tabularFigures()];

TextStyle numeric(TextStyle? base) =>
    (base ?? const TextStyle()).copyWith(fontFeatures: _tabular);

// ---------------------------------------------------------------------------
// Brand
// ---------------------------------------------------------------------------

/// The DLC logo with its name. The letters are near-black, so in dark mode the
/// mark sits on a light chip to stay legible.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.height = 32});
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final image = Image.asset(
      'assets/branding/dlc_wordmark.png',
      height: height,
      fit: BoxFit.contain,
      semanticLabel: 'DLC',
      errorBuilder: (_, _, _) => Text(
        'DLC',
        style: TextStyle(
          fontSize: height * 0.6,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
    if (!dark) return image;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EE),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: height * 0.18),
        child: image,
      ),
    );
  }
}

class BrandDrop extends StatelessWidget {
  const BrandDrop({super.key, this.size = 48});
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/dlc_drop.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
    errorBuilder: (_, _, _) => Icon(
      CupertinoIcons.drop_fill,
      size: size,
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}

// ---------------------------------------------------------------------------
// Cards with different visual weight
// ---------------------------------------------------------------------------

enum CardWeight { hero, standard, compact }

class DlcCard extends StatelessWidget {
  const DlcCard({
    super.key,
    required this.child,
    this.weight = CardWeight.standard,
    this.padding,
    this.color,
    this.onTap,
    this.semanticLabel,
  });
  final Widget child;
  final CardWeight weight;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.dlc;
    final radius = switch (weight) {
      CardWeight.hero => 28.0,
      CardWeight.standard => 20.0,
      CardWeight.compact => 16.0,
    };
    final shape = BorderRadius.circular(radius);
    final inner = Padding(
      padding:
          padding ??
          EdgeInsets.all(switch (weight) {
            CardWeight.hero => 22.0,
            CardWeight.standard => 18.0,
            CardWeight.compact => 14.0,
          }),
      child: child,
    );
    final decoration = switch (weight) {
      CardWeight.hero => BoxDecoration(
        gradient: DlcBrand.heroGradient,
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: DlcBrand.orange.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      CardWeight.standard => BoxDecoration(
        color: color ?? colors.card,
        borderRadius: shape,
        border: Border.all(color: scheme.outlineVariant),
      ),
      CardWeight.compact => BoxDecoration(
        color: color ?? scheme.surfaceContainer,
        borderRadius: shape,
      ),
    };
    Widget card = DecoratedBox(
      decoration: decoration,
      child: onTap == null
          ? inner
          : Material(
              type: MaterialType.transparency,
              child: InkWell(borderRadius: shape, onTap: onTap, child: inner),
            ),
    );
    if (onTap != null) card = PressScale(child: card);
    return semanticLabel == null
        ? card
        : Semantics(container: true, label: semanticLabel, child: card);
  }
}

/// Scales to 0.96 while a pointer is down (150 ms ease-out). Pointer events
/// are observed passively so taps still reach the child.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});
  final Widget child;
  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  void _set(bool value) {
    if (_down != value && mounted) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down && !reduceMotion(context) ? 0.96 : 1,
      duration: reduceMotion(context) ? Duration.zero : dlcPress,
      curve: dlcEaseOut,
      child: widget.child,
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Round icon with a tone background; never relies on colour alone because
/// callers always add a text label next to it.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.tone,
    this.size = 40,
  });
  final IconData icon;
  final DlcTone tone;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: tone.bg, shape: BoxShape.circle),
    child: Icon(icon, size: size * 0.5, color: tone.fg),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.look});
  final StatusLook look;
  @override
  Widget build(BuildContext context) {
    final tone = toneFor(context.dlc, look.kind, Theme.of(context).colorScheme);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(look.icon, size: 14, color: tone.fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                look.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: tone.fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

enum DlcButtonKind { primary, approve, danger, neutral }

/// Semantic button: colour and icon always travel together (DESIGN.md s.4).
/// While [busy] the icon becomes a spinner and taps are ignored, but the label
/// stays so the button never changes width.
class DlcButton extends StatelessWidget {
  const DlcButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.kind = DlcButtonKind.primary,
    this.busy = false,
    this.expand = true,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final DlcButtonKind kind;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.dlc;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final handler = busy || onPressed == null
        ? (onPressed == null ? null : () {})
        : onPressed;
    final fg = switch (kind) {
      DlcButtonKind.primary => scheme.onPrimary,
      DlcButtonKind.approve => dark ? DlcBrand.ink : Colors.white,
      DlcButtonKind.danger => colors.crit.fg,
      DlcButtonKind.neutral => scheme.onSurface,
    };
    final leading = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : Icon(icon, size: 20);
    final text = Flexible(
      child: Text(label, textAlign: TextAlign.center, softWrap: true),
    );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [leading, const SizedBox(width: 8), text],
    );
    final Widget button = switch (kind) {
      DlcButtonKind.primary => FilledButton(onPressed: handler, child: child),
      DlcButtonKind.approve => FilledButton(
        onPressed: handler,
        style: FilledButton.styleFrom(
          backgroundColor: dark
              ? const Color(0xFF86EFAC)
              : const Color(0xFF166534),
          foregroundColor: fg,
        ),
        child: child,
      ),
      DlcButtonKind.danger => OutlinedButton(
        onPressed: handler,
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(color: fg),
        ),
        child: child,
      ),
      DlcButtonKind.neutral => OutlinedButton(onPressed: handler, child: child),
    };
    return Semantics(
      button: true,
      label: busy ? '$label, en curso' : null,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

// ---------------------------------------------------------------------------
// Motion
// ---------------------------------------------------------------------------

/// Staggered entrance (opacity + 12 px rise, 280 ms ease-out). Plays once per
/// [group] per app session so tab switches stay instant.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.group = 'default',
  });
  final Widget child;
  final int index;
  final String group;
  static final Set<String> _seen = {};

  /// Test hook: forget which groups already played.
  static void reset() => _seen.clear();

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    if (Reveal._seen.contains(widget.group)) return;
    final delay = 60 * widget.index.clamp(0, 5);
    final total = dlcMotion.inMilliseconds + delay;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    );
    _curve = CurvedAnimation(
      parent: _controller!,
      curve: Interval(delay / total, 1, curve: dlcEaseOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Reveal._seen.add(widget.group);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = _controller;
    if (c == null || c.isCompleted || c.isAnimating) return;
    if (reduceMotion(context)) {
      c.value = 1;
    } else {
      c.forward();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return widget.child;
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - _curve.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Number that counts up to [value] in 300 ms (once, when [animate]).
class CountUp extends StatefulWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.style,
    this.animate = true,
    this.onDone,
    this.format,
  });
  final num value;
  final TextStyle style;
  final bool animate;
  final VoidCallback? onDone;
  final String Function(num value)? format;

  @override
  State<CountUp> createState() => _CountUpState();
}

class _CountUpState extends State<CountUp> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late num _from = widget.animate ? 0 : widget.value;
  bool _started = false;

  String _text(num v) =>
      (widget.format ?? (n) => formatNumber(n, decimals: 0))(v);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.animate && !reduceMotion(context) && widget.value != 0) {
      _controller.forward().whenComplete(() => widget.onDone?.call());
    } else {
      _from = widget.value;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onDone?.call(),
      );
    }
  }

  @override
  void didUpdateWidget(CountUp old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _from = widget.value;
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: _text(widget.value),
    excludeSemantics: true,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = dlcEaseOut.transform(_controller.value);
        final shown = _from + (widget.value - _from) * t;
        return Text(
          _text(shown.round()),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: numeric(widget.style),
        );
      },
    ),
  );
}

/// Horizontal progress bar that fills once on first paint (300 ms ease-out).
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.fraction,
    required this.color,
    required this.track,
    this.height = 10,
    this.semanticLabel,
  });
  final double fraction;
  final Color color, track;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(f * 100).round()}%',
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: f),
          duration: reduceMotion(context) ? Duration.zero : dlcMotion,
          curve: dlcEaseOut,
          builder: (context, value, _) => ClipRRect(
            borderRadius: BorderRadius.circular(height),
            child: Stack(
              children: [
                Container(height: height, color: track),
                FractionallySizedBox(
                  widthFactor: value,
                  child: Container(height: height, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading, empty and error states
// ---------------------------------------------------------------------------

/// Gentle opacity pulse for a whole skeleton layout (static when the system
/// asks for reduced motion).
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});
  final Widget child;
  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _controller.stop();
      _started = false;
    } else if (!_started) {
      _started = true;
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Cargando',
    liveRegion: true,
    child: ExcludeSemantics(
      child: FadeTransition(
        opacity: Tween(
          begin: 0.5,
          end: 1.0,
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut)),
        child: widget.child,
      ),
    ),
  );
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 16, this.radius = 8});
  final double? width;
  final double height, radius;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// Skeleton for the signed-in shell: hero + secondary cards.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});
  @override
  Widget build(BuildContext context) => SkeletonPulse(
    child: ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        const SkeletonBox(width: 180, height: 26),
        const SizedBox(height: 16),
        const SkeletonBox(height: 168, radius: 28),
        const SizedBox(height: 16),
        const SkeletonBox(height: 110, radius: 20),
        const SizedBox(height: 12),
        const SkeletonBox(height: 96, radius: 16),
        const SizedBox(height: 12),
        const SkeletonBox(height: 96, radius: 16),
      ],
    ),
  );
}

class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 4});
  final int rows;
  @override
  Widget build(BuildContext context) => SkeletonPulse(
    child: Column(
      children: [
        for (var i = 0; i < rows; i++)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: SkeletonBox(height: 64, radius: 16),
          ),
      ],
    ),
  );
}

/// Icon + useful sentence (+ optional action).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.title,
    this.action,
  });
  final IconData icon;
  final String message;
  final String? title;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 36, color: scheme.onSurfaceVariant),
          const SizedBox(height: 10),
          if (title != null) ...[
            Text(
              title!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

/// What happened, plus an optional technical reference kept folded.
@immutable
class UiError {
  const UiError(this.message, {this.reference});
  final String message;
  final String? reference;
}

/// Full-area error with a retry button.
class ErrorState extends StatefulWidget {
  const ErrorState({
    super.key,
    required this.error,
    required this.onRetry,
    this.extra,
  });
  final UiError error;
  final VoidCallback onRetry;

  /// Optional secondary action shown below Reintentar (e.g. sign out).
  final Widget? extra;
  @override
  State<ErrorState> createState() => _ErrorStateState();
}

class _ErrorStateState extends State<ErrorState> {
  bool _showRef = false;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ref = widget.error.reference;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(
              icon: CupertinoIcons.wifi_exclamationmark,
              tone: context.dlc.crit,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'No pudimos cargar tus datos',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              widget.error.message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            DlcButton(
              label: 'Reintentar',
              icon: CupertinoIcons.arrow_clockwise,
              onPressed: widget.onRetry,
              expand: false,
            ),
            ?widget.extra,
            if (ref != null) ...[
              TextButton(
                onPressed: () => setState(() => _showRef = !_showRef),
                child: Text(
                  _showRef ? 'Ocultar detalle' : 'Ver detalle técnico',
                ),
              ),
              if (_showRef) SelectableText('Referencia: $ref'),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline banner above content that is still on screen.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.error,
    this.onRetry,
    this.staleSince,
    this.onDismiss,
  });
  final UiError error;
  final VoidCallback? onRetry;
  final DateTime? staleSince;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final tone = context.dlc.crit;
    final stale = staleSince == null
        ? ''
        : ' Mostrando datos de las ${formatTime(staleSince!)}.';
    return Semantics(
      liveRegion: true,
      child: Material(
        color: tone.bg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Icon(CupertinoIcons.exclamationmark_triangle, color: tone.fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${error.message}$stale',
                  style: TextStyle(color: tone.fg, fontSize: 14),
                ),
              ),
              if (onRetry != null)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(CupertinoIcons.arrow_clockwise, size: 16),
                  label: const Text('Reintentar'),
                  style: TextButton.styleFrom(foregroundColor: tone.fg),
                )
              else if (onDismiss != null)
                IconButton(
                  tooltip: 'Cerrar aviso',
                  onPressed: onDismiss,
                  icon: Icon(CupertinoIcons.xmark, size: 18, color: tone.fg),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

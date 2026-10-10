import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'motion.dart';

/// Shared building blocks of the DLC design system (DESIGN.md). Every widget
/// reads colours from [DlcColors], uses CupertinoIcons only and stays inside
/// its constraints at 360 px wide with text scale 1.3.

// ---------------------------------------------------------------------------
// Brand
// ---------------------------------------------------------------------------

/// Logo with the name. On dark themes it sits on a light plate because the
/// letters are warm black.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({this.height = 32, super.key});
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final image = Image.asset(
      'assets/branding/dlc_wordmark.png',
      height: height,
      fit: BoxFit.contain,
      semanticLabel: 'DLC Gasolineras',
      errorBuilder: (_, _, _) => SizedBox(
        height: height,
        child: Center(
          child: Text(
            'DLC',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: height * .6,
              color: context.dlc.ink,
            ),
          ),
        ),
      ),
    );
    if (!dark) return image;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xfffffefc),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: image,
      ),
    );
  }
}

/// The drop on its own (small marks, hero decoration).
class BrandDrop extends StatelessWidget {
  const BrandDrop({this.size = 40, super.key});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      'assets/branding/dlc_drop.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
    ),
  );
}

// ---------------------------------------------------------------------------
// Cards with different visual weight
// ---------------------------------------------------------------------------

enum CardWeight { hero, standard, quiet }

/// Hero: brand gradient (white text). Standard: bordered surface. Quiet: flat
/// tinted tile for secondary information.
class DlcCard extends StatelessWidget {
  const DlcCard({
    required this.child,
    this.weight = CardWeight.standard,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.semanticLabel,
    super.key,
  });
  final Widget child;
  final CardWeight weight;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final radius = BorderRadius.circular(
      weight == CardWeight.hero ? 22 : weight == CardWeight.quiet ? 14 : 18,
    );
    final decoration = switch (weight) {
      CardWeight.hero => BoxDecoration(
        gradient: c.heroGradient,
        borderRadius: radius,
      ),
      CardWeight.standard => BoxDecoration(
        color: color ?? c.surface,
        borderRadius: radius,
        border: Border.all(color: c.border),
      ),
      CardWeight.quiet => BoxDecoration(
        color: color ?? c.surfaceAlt,
        borderRadius: radius,
      ),
    };
    Widget content = Padding(padding: padding, child: child);
    if (weight == CardWeight.hero) {
      content = DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: IconTheme.merge(
          data: const IconThemeData(color: Colors.white),
          child: content,
        ),
      );
    }
    final box = Ink(decoration: decoration, child: content);
    final tappable = onTap == null
        ? box
        : InkWell(onTap: onTap, borderRadius: radius, child: box);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: tappable,
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.trailing,
    this.icon,
    super.key,
  });
  final String title;
  final String? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: c.muted),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(
              trailing!,
              style: TextStyle(
                color: c.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Icon + label in the tone colours (never colour alone).
class ToneChip extends StatelessWidget {
  const ToneChip({
    required this.label,
    required this.tone,
    this.icon,
    super.key,
  });
  final String label;
  final DlcStatus tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final fg = c.foreground(tone);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.container(tone),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? tone.icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading and empty states
// ---------------------------------------------------------------------------

/// Gentle opacity pulse for skeletons; static with reduced motion.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({required this.child, super.key});
  final Widget child;
  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _controller?.dispose();
      _controller = null;
    } else if (_controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    return FadeTransition(
      opacity: Tween<double>(begin: .55, end: 1).animate(controller),
      child: widget.child,
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({this.width, this.height = 14, this.radius = 8, super.key});
  final double? width;
  final double height;
  final double radius;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.dlc.border,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: SizedBox(width: width, height: height),
  );
}

/// Placeholder that mimics the real layout (hero + secondary row + rows).
class PageSkeleton extends StatelessWidget {
  const PageSkeleton({this.rows = 3, super.key});
  final int rows;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Cargando',
    liveRegion: true,
    child: ExcludeSemantics(
      child: SkeletonPulse(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(height: 150, radius: 22),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Expanded(child: SkeletonBox(height: 78, radius: 14)),
                  SizedBox(width: 10),
                  Expanded(child: SkeletonBox(height: 78, radius: 14)),
                ],
              ),
              for (var i = 0; i < rows; i++) ...[
                const SizedBox(height: 14),
                const SkeletonBox(height: 70, radius: 16),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    super.key,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return DlcCard(
      weight: CardWeight.quiet,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.brandContainer,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Icon(icon, size: 26, color: c.brand),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, height: 1.4),
          ),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon ?? CupertinoIcons.plus, size: 18),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Error with what happened + retry; technical reference folded.
class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.message,
    this.details,
    this.onRetry,
    this.staleSince,
    super.key,
  });
  final String message;
  final String? details;
  final VoidCallback? onRetry;

  /// "14:32" of the data that is still on screen.
  final String? staleSince;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return DlcCard(
      color: c.criticalContainer,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(CupertinoIcons.exclamationmark_circle, color: c.critical),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  staleSince == null
                      ? message
                      : '$message Datos de las $staleSince.',
                  style: TextStyle(color: c.critical, height: 1.35),
                ),
              ),
            ],
          ),
          if (onRetry != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(CupertinoIcons.refresh, size: 16),
                label: const Text('Reintentar'),
                style: TextButton.styleFrom(foregroundColor: c.critical),
              ),
            ),
          if (details != null && details!.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const Key('technical-details'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Detalles técnicos',
                  style: TextStyle(color: c.critical, fontSize: 12),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      details!,
                      style: TextStyle(color: c.critical, fontSize: 12),
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

// ---------------------------------------------------------------------------
// Fixed-width segmented filter (never wraps)
// ---------------------------------------------------------------------------

class SegmentedFilter<T> extends StatelessWidget {
  const SegmentedFilter({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            children: [
              for (final entry in options.entries)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: entry.key == selected,
                    label: entry.value,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => onChanged(entry.key),
                      child: AnimatedContainer(
                        duration: reduceMotion(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        curve: kEaseOut,
                        constraints: const BoxConstraints(minHeight: 40),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: entry.key == selected
                              ? c.surface
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          border: entry.key == selected
                              ? Border.all(color: c.borderStrong)
                              : null,
                        ),
                        child: Text(
                          entry.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: entry.key == selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: entry.key == selected
                                ? (dark ? c.ink : c.brand)
                                : c.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Combobox: outlined field (label + value + chevron) and searchable sheet
// ---------------------------------------------------------------------------

@immutable
class SelectOption<T> {
  const SelectOption(this.value, this.label, {this.detail, this.icon});
  final T value;
  final String label;
  final String? detail;
  final IconData? icon;
}

/// Above this many options the sheet shows a search box.
const int kSearchableThreshold = 6;

String _fold(String text) => text
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ñ', 'n');

/// Accent-insensitive filter shared by every searchable list.
List<SelectOption<T>> filterOptions<T>(
  List<SelectOption<T>> options,
  String query,
) {
  final q = _fold(query.trim());
  if (q.isEmpty) return options;
  return [
    for (final o in options)
      if (_fold('${o.label} ${o.detail ?? ''}').contains(q)) o,
  ];
}

Future<R?> _showDlcSheet<R>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext, ScrollController) body,
  double initial = .62,
}) => showModalBottomSheet<R>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheetContext) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: initial,
    minChildSize: .4,
    maxChildSize: .95,
    builder: (context, scroll) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(CupertinoIcons.xmark),
              ),
            ],
          ),
        ),
        Expanded(child: body(context, scroll)),
      ],
    ),
  ),
);

Future<T?> showSelectSheet<T>(
  BuildContext context, {
  required String title,
  required List<SelectOption<T>> options,
  T? selected,
}) => _showDlcSheet<T>(
  context,
  title: title,
  body: (context, scroll) => _SelectBody<T>(
    options: options,
    selected: selected,
    scroll: scroll,
    onPick: (v) => Navigator.pop(context, v),
  ),
);

class _SelectBody<T> extends StatefulWidget {
  const _SelectBody({
    required this.options,
    required this.selected,
    required this.scroll,
    required this.onPick,
  });
  final List<SelectOption<T>> options;
  final T? selected;
  final ScrollController scroll;
  final ValueChanged<T> onPick;
  @override
  State<_SelectBody<T>> createState() => _SelectBodyState<T>();
}

class _SelectBodyState<T> extends State<_SelectBody<T>> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final shown = filterOptions(widget.options, _query);
    return Column(
      children: [
        if (widget.options.length > kSearchableThreshold)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(
                hintText: 'Buscar',
                prefixIcon: Icon(CupertinoIcons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    'Sin resultados para "$_query".',
                    style: TextStyle(color: c.muted),
                  ),
                )
              : ListView.builder(
                  controller: widget.scroll,
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final o = shown[i];
                    final isSel = o.value == widget.selected;
                    return ListTile(
                      minTileHeight: 52,
                      leading: o.icon == null ? null : Icon(o.icon),
                      title: Text(
                        o.label,
                        style: TextStyle(
                          fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      subtitle: o.detail == null ? null : Text(o.detail!),
                      trailing: isSel
                          ? Icon(CupertinoIcons.checkmark_alt, color: c.brand)
                          : null,
                      selected: isSel,
                      onTap: () => widget.onPick(o.value),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Future<Set<T>?> showMultiSelectSheet<T>(
  BuildContext context, {
  required String title,
  required List<SelectOption<T>> options,
  required Set<T> selected,
  String allLabel = 'Todas',
}) => _showDlcSheet<Set<T>>(
  context,
  title: title,
  initial: .75,
  body: (context, scroll) => _MultiBody<T>(
    options: options,
    initial: selected,
    scroll: scroll,
    allLabel: allLabel,
  ),
);

class _MultiBody<T> extends StatefulWidget {
  const _MultiBody({
    required this.options,
    required this.initial,
    required this.scroll,
    required this.allLabel,
  });
  final List<SelectOption<T>> options;
  final Set<T> initial;
  final ScrollController scroll;
  final String allLabel;
  @override
  State<_MultiBody<T>> createState() => _MultiBodyState<T>();
}

class _MultiBodyState<T> extends State<_MultiBody<T>> {
  late Set<T> _chosen = {...widget.initial};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final shown = filterOptions(widget.options, _query);
    return Column(
      children: [
        if (widget.options.length > kSearchableThreshold)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar',
                prefixIcon: Icon(CupertinoIcons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: widget.scroll,
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final o = shown[i];
              final on = _chosen.contains(o.value);
              return CheckboxListTile(
                value: on,
                controlAffinity: ListTileControlAffinity.trailing,
                title: Text(o.label),
                subtitle: o.detail == null ? null : Text(o.detail!),
                secondary: o.icon == null ? null : Icon(o.icon),
                onChanged: (v) => setState(() {
                  if (v ?? false) {
                    _chosen.add(o.value);
                  } else {
                    _chosen.remove(o.value);
                  }
                }),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, <T>{}),
                    child: Text(widget.allLabel, maxLines: 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _chosen),
                    icon: const Icon(CupertinoIcons.checkmark_alt, size: 18),
                    label: Text(
                      _chosen.isEmpty ? 'Ver todas' : 'Aplicar (${_chosen.length})',
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Visibly interactive combobox: outlined field with label, value and a
/// chevron. Opens a (searchable when long) sheet.
class SelectField<T> extends StatelessWidget {
  const SelectField({
    required this.label,
    required this.valueLabel,
    required this.onTap,
    this.icon,
    this.enabled = true,
    this.errorText,
    super.key,
  });
  final String label;
  final String valueLabel;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label: $valueLabel',
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: InputDecorator(
          isEmpty: false,
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            prefixIcon: icon == null ? null : Icon(icon, size: 20),
            suffixIcon: Icon(
              CupertinoIcons.chevron_down,
              size: 16,
              color: enabled ? c.ink : c.muted,
            ),
          ),
          child: Text(
            valueLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: enabled ? c.ink : c.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

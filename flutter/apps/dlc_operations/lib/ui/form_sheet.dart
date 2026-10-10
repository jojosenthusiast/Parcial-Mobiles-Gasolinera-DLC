import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../preferences.dart';

/// Persists the text of a form while it is being written so a closed sheet
/// can be restored ("Borrador restaurado"). Values are plain strings keyed by
/// field name; nothing sensitive (passwords) should be bound.
class DraftBinder {
  DraftBinder({
    required this.store,
    required this.key,
    required Map<String, TextEditingController> fields,
    this.extra,
    this.debounce = const Duration(milliseconds: 350),
  }) : _fields = fields {
    for (final c in _fields.values) {
      c.addListener(_schedule);
    }
  }

  final KeyValueStore store;
  final String key;
  final Duration debounce;
  final Map<String, TextEditingController> _fields;

  /// Extra non-text state (selected country...) saved together with the text.
  final Map<String, String> Function()? extra;
  Timer? _timer;
  bool _restoring = false;
  bool _disposed = false;

  void _schedule() {
    if (_restoring || _disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, save);
  }

  /// Call after changing non-text state (dropdowns, switches).
  void touch() => _schedule();

  Map<String, String> snapshot() => {
    for (final e in _fields.entries) e.key: e.value.text,
    ...?extra?.call(),
  };

  Future<void> save() async {
    if (_disposed) return;
    final values = snapshot();
    if (values.values.every((v) => v.trim().isEmpty)) return;
    final json = encodeJson(values);
    if (json == null) return;
    try {
      await store.write('draft.$key', json);
    } catch (_) {}
  }

  /// Fills the controllers from the saved draft; returns the saved map (so
  /// the caller can restore its extra state) or null when there is none.
  Future<Map<String, String>?> restore() async {
    try {
      final raw = decodeJson(await store.read('draft.$key'));
      if (raw is! Map || raw.isEmpty) return null;
      final values = {
        for (final e in raw.entries) e.key.toString(): e.value?.toString() ?? '',
      };
      if (values.values.every((v) => v.trim().isEmpty)) return null;
      _restoring = true;
      for (final e in _fields.entries) {
        final v = values[e.key];
        if (v != null) e.value.text = v;
      }
      _restoring = false;
      return values;
    } catch (_) {
      _restoring = false;
      return null;
    }
  }

  Future<void> clear() async {
    _timer?.cancel();
    try {
      await store.write('draft.$key', '');
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final c in _fields.values) {
      c.removeListener(_schedule);
    }
  }
}

/// Small banner shown after a draft was restored.
class DraftBanner extends StatelessWidget {
  const DraftBanner({required this.onDiscard, super.key});
  final VoidCallback onDiscard;
  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.infoContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Icon(CupertinoIcons.doc_text, size: 18, color: c.info),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Borrador restaurado',
                style: TextStyle(color: c.info, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: onDiscard,
              style: TextButton.styleFrom(
                foregroundColor: c.info,
                minimumSize: const Size(44, 44),
              ),
              child: const Text('Descartar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Layout of a form inside a bottom sheet: header, scrolling body and a
/// sticky primary action. The keyboard never hides the action.
class FormSheetLayout extends StatelessWidget {
  const FormSheetLayout({
    required this.title,
    required this.scrollController,
    required this.children,
    required this.submitLabel,
    required this.onSubmit,
    this.icon,
    this.subtitle,
    this.submitIcon = CupertinoIcons.checkmark_alt,
    this.busy = false,
    super.key,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final ScrollController scrollController;
  final List<Widget> children;
  final String submitLabel;
  final IconData submitIcon;

  /// Null disables the button (form invalid).
  final VoidCallback? onSubmit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
          child: Row(
            children: [
              if (icon != null) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.brandContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(icon, size: 20, color: c.brand),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(color: c.muted, fontSize: 13),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(CupertinoIcons.xmark),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: children,
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : onSubmit,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(submitIcon, size: 18),
                  label: Text(busy ? 'Guardando...' : submitLabel),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Opens a form as a modal bottom sheet (DraggableScrollableSheet). The
/// [builder] receives the sheet's scroll controller and must return a
/// [FormSheetLayout]. Resizes with the keyboard.
Future<R?> showFormSheet<R>(
  BuildContext context, {
  required Widget Function(BuildContext context, ScrollController scroll)
  builder,
  double initialSize = .9,
}) => showModalBottomSheet<R>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: initialSize,
      minChildSize: .5,
      maxChildSize: .97,
      builder: (context, scroll) => builder(context, scroll),
    ),
  ),
);

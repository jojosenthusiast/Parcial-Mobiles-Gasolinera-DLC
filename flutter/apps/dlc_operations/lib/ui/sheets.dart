import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../validators.dart';

/// Shared bottom-sheet replacements for the old AlertDialogs: a confirmation,
/// a confirmation that also asks for a reason, a free-form text prompt and a
/// copyable one-time secret. All are keyboard safe and never overflow at 1.3x
/// text scale.
Future<R?> _showSheet<R>(
  BuildContext context,
  Widget Function(BuildContext) builder,
) => showModalBottomSheet<R>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: builder(sheetContext),
    ),
  ),
);

/// Yes/no confirmation. Returns true only when the user confirms.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  String cancelLabel = 'Volver',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await _showSheet<bool>(
    context,
    (ctx) => _ConfirmBody(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      icon: icon,
    ),
  );
  return result == true;
}

class _ConfirmBody extends StatelessWidget {
  const _ConfirmBody({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
    this.icon,
  });
  final String title, message, confirmLabel, cancelLabel;
  final bool destructive;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: destructive ? c.critical : c.brand),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(message, style: TextStyle(color: c.muted, height: 1.4)),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: c.critical)
              : null,
          child: Text(confirmLabel),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancelLabel),
        ),
      ],
    );
  }
}

/// Confirmation that also asks for a typed reason (min [minLength]).
/// Returns the trimmed reason or null when cancelled.
Future<String?> showReasonSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String fieldLabel,
  String confirmLabel = 'Confirmar',
  int minLength = 8,
  int maxLength = 240,
  bool destructive = false,
  String? initial,
}) => _showSheet<String>(
  context,
  (ctx) => _ReasonBody(
    title: title,
    message: message,
    fieldLabel: fieldLabel,
    confirmLabel: confirmLabel,
    minLength: minLength,
    maxLength: maxLength,
    destructive: destructive,
    initial: initial,
  ),
);

class _ReasonBody extends StatefulWidget {
  const _ReasonBody({
    required this.title,
    required this.message,
    required this.fieldLabel,
    required this.confirmLabel,
    required this.minLength,
    required this.maxLength,
    required this.destructive,
    this.initial,
  });
  final String title, message, fieldLabel, confirmLabel;
  final int minLength, maxLength;
  final bool destructive;
  final String? initial;
  @override
  State<_ReasonBody> createState() => _ReasonBodyState();
}

class _ReasonBodyState extends State<_ReasonBody> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial ?? '',
  );
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? _validate(String? v) => minLengthText(
    v,
    widget.minLength,
    field: widget.fieldLabel,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final valid = _validate(_text.text) == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(widget.message, style: TextStyle(color: c.muted, height: 1.4)),
        const SizedBox(height: 14),
        TextFormField(
          controller: _text,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: _validate,
          maxLength: widget.maxLength,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: widget.fieldLabel),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, _text.text.trim())
              : null,
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: c.critical)
              : null,
          child: Text(widget.confirmLabel),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Volver'),
        ),
      ],
    );
  }
}

/// Shows a secret that exists only once (activation / reset token) in a
/// copyable sheet. The caller never stores it.
Future<void> showSecretSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String secret,
  String? footnote,
}) => _showSheet<void>(
  context,
  (ctx) => _SecretBody(
    title: title,
    message: message,
    secret: secret,
    footnote: footnote,
  ),
);

class _SecretBody extends StatefulWidget {
  const _SecretBody({
    required this.title,
    required this.message,
    required this.secret,
    this.footnote,
  });
  final String title, message, secret;
  final String? footnote;
  @override
  State<_SecretBody> createState() => _SecretBodyState();
}

class _SecretBodyState extends State<_SecretBody> {
  bool _copied = false;
  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(CupertinoIcons.lock_shield, color: c.brand),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(widget.message, style: TextStyle(color: c.muted, height: 1.4)),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.secret,
              key: const Key('secret-token'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: widget.secret));
            if (mounted) setState(() => _copied = true);
          },
          icon: Icon(
            _copied ? CupertinoIcons.checkmark_alt : CupertinoIcons.doc_on_doc,
            size: 18,
          ),
          label: Text(_copied ? 'Copiado' : 'Copiar'),
        ),
        if (widget.footnote != null) ...[
          const SizedBox(height: 10),
          Text(
            widget.footnote!,
            style: TextStyle(color: c.muted, fontSize: 12, height: 1.4),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Listo, ya lo entregué'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import 'haptics.dart';
import 'validators.dart';

/// Text field with inline validation after the first interaction. A medium
/// haptic fires when the user leaves the field while it is invalid.
class LiveTextField extends StatefulWidget {
  const LiveTextField({
    required this.controller,
    required this.label,
    required this.validator,
    this.onChanged,
    this.helper,
    this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
    this.minLines,
    this.maxLines = 1,
    this.autofocus = false,
    this.prefixIcon,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final FieldValidator validator;

  /// Called after each edit so the parent can recompute "is the form valid".
  final VoidCallback? onChanged;
  final String? helper;
  final String? hint;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? maxLength;
  final int? minLines;
  final int? maxLines;
  final bool autofocus;
  final IconData? prefixIcon;

  /// Keyboard for decimal numbers (optionally signed).
  static TextInputType decimal({bool signed = false}) =>
      TextInputType.numberWithOptions(decimal: true, signed: signed);

  @override
  State<LiveTextField> createState() => _LiveTextFieldState();
}

class _LiveTextFieldState extends State<LiveTextField> {
  bool _touched = false;

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (focused) {
      if (!focused && _touched && widget.validator(widget.controller.text) != null) {
        Haptics.error();
      }
    },
    child: TextFormField(
      controller: widget.controller,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: widget.validator,
      keyboardType: widget.keyboardType,
      textCapitalization: widget.textCapitalization,
      maxLength: widget.maxLength,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      autofocus: widget.autofocus,
      onChanged: (_) {
        _touched = true;
        widget.onChanged?.call();
      },
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        hintText: widget.hint,
        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon),
      ),
    ),
  );
}

/// Dialog whose primary action stays disabled until [isValid] returns true.
/// [contentBuilder] receives a callback to call from each field's `onChanged`.
class ValidatedFormDialog extends StatefulWidget {
  const ValidatedFormDialog({
    required this.title,
    required this.submitLabel,
    required this.isValid,
    required this.contentBuilder,
    required this.onSubmit,
    this.cancelLabel = 'Cancelar',
    this.onCancel,
    super.key,
  });
  final String title;
  final String submitLabel;
  final String cancelLabel;
  final bool Function() isValid;
  final Widget Function(BuildContext context, VoidCallback changed)
  contentBuilder;
  final VoidCallback onSubmit;
  final VoidCallback? onCancel;

  @override
  State<ValidatedFormDialog> createState() => _ValidatedFormDialogState();
}

class _ValidatedFormDialogState extends State<ValidatedFormDialog> {
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: widget.contentBuilder(context, () => setState(() {})),
    ),
    actions: [
      TextButton(
        onPressed: widget.onCancel ?? () => Navigator.pop(context),
        child: Text(widget.cancelLabel),
      ),
      FilledButton(
        onPressed: widget.isValid() ? widget.onSubmit : null,
        child: Text(widget.submitLabel),
      ),
    ],
  );
}

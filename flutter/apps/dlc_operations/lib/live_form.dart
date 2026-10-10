import 'package:flutter/material.dart';

import 'app_theme.dart';
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
  /// Rendered as a bottom sheet (DESIGN.md: forms never use AlertDialog). It
  /// works inside `showDialog` or inline: the blank area closes it.
  @override
  Widget build(BuildContext context) {
    final colors = context.dlc;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onCancel ?? () => Navigator.maybePop(context),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: MediaQuery.sizeOf(context).height * .92,
            ),
            child: Material(
              color: colors.surface,
              elevation: 8,
              clipBehavior: Clip.antiAlias,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: EdgeInsets.only(bottom: inset),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 10, bottom: 6),
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.borderStrong,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: Semantics(
                          header: true,
                          child: Text(
                            widget.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                          child: widget.contentBuilder(
                            context,
                            () => setState(() {}),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed:
                                    widget.onCancel ??
                                    () => Navigator.pop(context),
                                child: Text(widget.cancelLabel),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: FilledButton(
                                onPressed: widget.isValid()
                                    ? widget.onSubmit
                                    : null,
                                child: Text(widget.submitLabel),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
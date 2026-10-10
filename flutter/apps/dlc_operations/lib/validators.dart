/// Pure, UI-free validators. Each returns a Spanish message or null when the
/// value is valid, so they plug into `TextFormField.validator` unchanged and
/// map one-to-one to Swift `(String) -> String?` functions.
typedef FieldValidator = String? Function(String? value);

/// Parses a user-typed decimal; accepts "12,5" and "12.5" (no thousands).
double? parseDecimal(String? raw) {
  final text = raw?.trim().replaceAll(',', '.') ?? '';
  if (text.isEmpty) return null;
  if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(text)) return null;
  return double.tryParse(text);
}

int decimalPlaces(String? raw) {
  final text = raw?.trim().replaceAll(',', '.') ?? '';
  final dot = text.indexOf('.');
  return dot < 0 ? 0 : text.length - dot - 1;
}

/// True when every result is null (no error).
bool allValid(Iterable<String?> results) => results.every((r) => r == null);

/// Runs validators in order and returns the first message.
FieldValidator composeValidators(List<FieldValidator> validators) =>
    (value) {
      for (final v in validators) {
        final message = v(value);
        if (message != null) return message;
      }
      return null;
    };

String? requiredText(String? value, {String field = 'Este campo'}) =>
    (value == null || value.trim().isEmpty) ? '$field es un dato obligatorio.' : null;

String? minLengthText(String? value, int min, {String field = 'Este campo'}) {
  final length = value?.trim().length ?? 0;
  if (length == 0) return '$field es un dato obligatorio.';
  return length < min ? '$field debe tener al menos $min caracteres.' : null;
}

String? maxLengthText(String? value, int max, {String field = 'Este campo'}) =>
    (value != null && value.trim().length > max)
    ? '$field no puede superar $max caracteres.'
    : null;

/// Number > 0 (or >= 0 with [allowZero]) with at most [maxDecimals] decimals.
String? positiveNumber(
  String? value, {
  String field = 'El valor',
  bool allowZero = false,
  int maxDecimals = 3,
  double? max,
}) {
  if (value == null || value.trim().isEmpty) return '$field es un dato obligatorio.';
  final n = parseDecimal(value);
  if (n == null) return '$field debe ser un número válido.';
  if (allowZero ? n < 0 : n <= 0) {
    return allowZero
        ? '$field no puede ser negativo.'
        : '$field debe ser mayor que cero.';
  }
  if (decimalPlaces(value) > maxDecimals) {
    return '$field admite hasta $maxDecimals decimales.';
  }
  if (max != null && n > max) return '$field no puede superar $max.';
  return null;
}

/// Optional number: empty is valid, otherwise it must parse and be >= 0
/// (or any sign with [signed], e.g. temperature).
String? optionalNumber(
  String? value, {
  String field = 'El valor',
  bool signed = false,
  int maxDecimals = 3,
}) {
  if (value == null || value.trim().isEmpty) return null;
  final n = parseDecimal(value);
  if (n == null) return '$field debe ser un número válido.';
  if (!signed && n < 0) return '$field no puede ser negativo.';
  if (decimalPlaces(value) > maxDecimals) {
    return '$field admite hasta $maxDecimals decimales.';
  }
  return null;
}

/// Meter totals only grow: final reading must be >= the initial one.
String? finalNotBelowInitial(
  String? finalValue,
  double? initial, {
  String field = 'La lectura final',
}) {
  final base = positiveNumber(finalValue, field: field, allowZero: true);
  if (base != null) return base;
  if (initial == null) return null;
  final n = parseDecimal(finalValue)!;
  return n < initial
      ? '$field no puede ser menor que la inicial (${_trim(initial)}).'
      : null;
}

/// Quantity that must not exceed what is available or ordered.
String? notAbove(
  String? value,
  double? limit, {
  String field = 'La cantidad',
  String limitName = 'el máximo permitido',
  int maxDecimals = 3,
  bool allowZero = false,
}) {
  final base = positiveNumber(
    value,
    field: field,
    maxDecimals: maxDecimals,
    allowZero: allowZero,
  );
  if (base != null) return base;
  if (limit == null) return null;
  return parseDecimal(value)! > limit
      ? '$field no puede superar $limitName (${_trim(limit)}).'
      : null;
}

/// Observed litres in a tank: zero is allowed (empty), never above capacity.
String? tankMeasureLiters(String? value, double? capacityLiters) => notAbove(
  value,
  capacityLiters,
  field: 'El combustible observado',
  limitName: 'la capacidad del tanque',
  allowZero: true,
);

/// Loss / shrinkage: any amount above zero needs a written explanation.
String? lossExplanation(
  String? explanation, {
  required double? lossAmount,
  int minLength = 10,
}) {
  if (lossAmount == null || lossAmount <= 0) return null;
  return minLengthText(explanation, minLength, field: 'La explicación');
}

String? emailAddress(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'El correo es obligatorio.';
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(text)
      ? null
      : 'Escribe un correo válido.';
}

String? branchCode(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'El código es obligatorio.';
  if (text.length > 24) return 'El código no puede superar 24 caracteres.';
  return RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$').hasMatch(text)
      ? null
      : 'Usa letras, números, guion o guion bajo.';
}

String? ianaTimezone(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'La zona horaria es obligatoria.';
  return RegExp(r'^[A-Za-z]+(?:[/_+-][A-Za-z0-9_+-]+)+$').hasMatch(text) ||
          text == 'UTC'
      ? null
      : 'Usa el formato IANA, por ejemplo America/El_Salvador.';
}

String? personName(String? value, {String field = 'El nombre'}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return '$field es un dato obligatorio.';
  if (text.length < 3) return '$field debe tener al menos 3 caracteres.';
  return text.length > 120 ? '$field no puede superar 120 caracteres.' : null;
}

String? integerInRange(
  String? value, {
  required int min,
  required int max,
  String field = 'El valor',
}) {
  final n = int.tryParse(value?.trim() ?? '');
  if (n == null) return '$field debe ser un número entero.';
  return (n < min || n > max)
      ? '$field debe estar entre $min y $max.'
      : null;
}

String _trim(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

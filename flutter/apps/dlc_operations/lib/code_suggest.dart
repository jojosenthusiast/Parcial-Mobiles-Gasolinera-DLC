/// Pure helpers to suggest the next code from the last saved one and to
/// validate uniqueness live. No Flutter imports: maps 1:1 to Swift.

final RegExp _trailingNumber = RegExp(r'^(.*?)(\d+)$');

class _ParsedCode {
  const _ParsedCode(this.prefix, this.number, this.width);
  final String prefix;
  final int number;
  final int width;
}

_ParsedCode? _parse(String code) {
  final m = _trailingNumber.firstMatch(code.trim());
  if (m == null) return null;
  final digits = m.group(2)!;
  final number = int.tryParse(digits);
  if (number == null) return null;
  return _ParsedCode(m.group(1)!, number, digits.length);
}

/// Suggests the next correlative code.
///
/// [existing] lists the saved codes, MOST RECENT FIRST when the order is
/// known. The prefix of the first code that ends in digits wins; the number
/// is then the highest one found with that same prefix plus one, keeping the
/// zero padding: `['QA-GT-01']` -> `QA-GT-02`, `['SV-9','SV-10']` -> `SV-11`.
///
/// With no usable code, returns `<fallbackPrefix>01` (or null without prefix).
String? suggestNextCode(
  Iterable<String> existing, {
  String? fallbackPrefix,
}) {
  final parsed = [
    for (final code in existing)
      if (_parse(code) != null) _parse(code)!,
  ];
  if (parsed.isEmpty) {
    final prefix = fallbackPrefix?.trim();
    return prefix == null || prefix.isEmpty ? null : '${_ensureSeparator(prefix)}01';
  }
  final lead = parsed.first;
  var highest = lead.number;
  var width = lead.width;
  for (final p in parsed) {
    if (p.prefix.toLowerCase() != lead.prefix.toLowerCase()) continue;
    if (p.number > highest) highest = p.number;
    if (p.width > width) width = p.width;
  }
  final next = (highest + 1).toString().padLeft(width, '0');
  return '${lead.prefix}$next';
}

String _ensureSeparator(String prefix) {
  final last = prefix[prefix.length - 1];
  return RegExp(r'[A-Za-z0-9]').hasMatch(last) ? '$prefix-' : prefix;
}

/// Case-insensitive duplicate check on trimmed codes.
bool codeExists(Iterable<String> existing, String candidate) {
  final wanted = candidate.trim().toLowerCase();
  if (wanted.isEmpty) return false;
  return existing.any((c) => c.trim().toLowerCase() == wanted);
}

/// Validator factory: Spanish message when [candidate] is already in use.
String? Function(String?) uniqueCodeValidator(
  Iterable<String> Function() existing, {
  String? ignore,
}) => (value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  if (ignore != null && text.toLowerCase() == ignore.trim().toLowerCase()) {
    return null;
  }
  return codeExists(existing(), text)
      ? 'Ese código ya existe. Prueba con ${suggestNextCode(existing()) ?? 'otro'}.'
      : null;
};

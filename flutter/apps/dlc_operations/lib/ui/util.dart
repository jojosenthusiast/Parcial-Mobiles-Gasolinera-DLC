import 'package:dlc_api/dlc_api.dart';

import '../format.dart';

Map<String, dynamic> asMap(Object? x) =>
    x is Map ? Map<String, dynamic>.from(x) : <String, dynamic>{};

List<dynamic> asList(Object? x) => x is List ? x : const [];

List<Map<String, dynamic>> asMaps(Object? x) => [
  for (final e in asList(x))
    if (e is Map) Map<String, dynamic>.from(e),
];

String asText(Object? x, [String fallback = '']) {
  final s = x?.toString().trim() ?? '';
  return s.isEmpty ? fallback : s;
}

/// ISO currency of a branch from its country (never a fixed USD).
String branchCurrency(BranchSummary? branch) =>
    currencyForCountry(branch?.countryCode);

/// "14:32" from a server timestamp, or null.
String? clockOf(Object? raw) {
  final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  return d == null ? null : formatClock(d);
}

/// Next-friendly name for a pump when the server sends only a code.
String pumpTitle(Map<String, dynamic> pump) =>
    asText(pump['name'], asText(pump['code'], 'Surtidor'));

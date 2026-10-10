import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;

/// Spanish display names for the countries DLC operates in or expects to.
/// Unknown codes fall back to the ISO code itself.
const Map<String, String> kCountryNamesEs = {
  'SV': 'El Salvador',
  'GT': 'Guatemala',
  'HN': 'Honduras',
  'NI': 'Nicaragua',
  'CR': 'Costa Rica',
  'PA': 'Panamá',
  'MX': 'México',
  'US': 'Estados Unidos',
  'CO': 'Colombia',
};

const String kAllCountriesLabel = 'Todos los países';
const String kAllBranchesLabel = 'Todas las sucursales';

String countryName(String? code) {
  final normalized = normalizeCountryCode(code);
  return kCountryNamesEs[normalized] ?? normalized;
}

/// Codes offered when creating or editing a branch: the known list plus any
/// extra code already in use (so a branch in another country stays editable).
List<String> selectableCountryCodes([Iterable<String> extra = const []]) {
  final codes = <String>{...kCountryNamesEs.keys};
  for (final code in extra) {
    codes.add(normalizeCountryCode(code));
  }
  return codes.toList(growable: false);
}

/// Branches whose country matches [countryCode]; null/empty means all.
List<BranchSummary> filterBranchesByCountry(
  List<BranchSummary> branches,
  String? countryCode,
) {
  if (countryCode == null || countryCode.isEmpty) return branches;
  final wanted = normalizeCountryCode(countryCode);
  return branches
      .where((b) => b.countryCode == wanted)
      .toList(growable: false);
}

/// Applies the country and branch filters together (both optional).
List<BranchSummary> filterBranches(
  List<BranchSummary> branches, {
  String? countryCode,
  String? branchId,
}) => filterBranchesByCountry(
  branches,
  countryCode,
).where((b) => branchId == null || b.id == branchId).toList(growable: false);

/// Keeps [branchId] only when it still belongs to [countryCode]; changing the
/// country therefore resets an incompatible branch selection to null.
String? reconcileBranchForCountry(
  String? branchId,
  String? countryCode,
  List<BranchSummary> branches,
) {
  if (branchId == null) return null;
  final stillVisible = filterBranchesByCountry(
    branches,
    countryCode,
  ).any((b) => b.id == branchId);
  return stillVisible ? branchId : null;
}

/// Country options with branch counts. Prefers the server's `countries` list
/// and falls back to counting [branches]. Sorted by Spanish name.
List<NetworkCountry> countryOptions(
  List<BranchSummary> branches, {
  List<NetworkCountry> fromServer = const [],
}) {
  final counts = <String, int>{};
  if (fromServer.isNotEmpty) {
    for (final c in fromServer) {
      counts[c.countryCode] = (counts[c.countryCode] ?? 0) + c.branchCount;
    }
  } else {
    for (final b in branches) {
      counts[b.countryCode] = (counts[b.countryCode] ?? 0) + 1;
    }
  }
  final list = [
    for (final e in counts.entries)
      NetworkCountry(countryCode: e.key, branchCount: e.value),
  ]..sort((a, b) => countryName(a.countryCode).compareTo(countryName(b.countryCode)));
  return list;
}

/// Dropdown for choosing a country.
///
/// With [includeAll] the first entry is "Todos los países" and [value] may be
/// null; otherwise [value] is required (defaults to SV in forms).
class CountryDropdown extends StatelessWidget {
  const CountryDropdown({
    required this.value,
    required this.onChanged,
    this.codes,
    this.counts = const {},
    this.includeAll = false,
    this.label = 'País',
    this.enabled = true,
    super.key,
  });

  final String? value;
  final ValueChanged<String?> onChanged;

  /// Codes to list; defaults to [selectableCountryCodes].
  final List<String>? codes;

  /// Optional branch counts shown next to each name.
  final Map<String, int> counts;
  final bool includeAll;
  final String label;
  final bool enabled;

  static const _all = '*';

  @override
  Widget build(BuildContext context) {
    final options = codes ?? selectableCountryCodes([?value]);
    final current = value == null ? (includeAll ? _all : null) : value;
    final safe = current == _all || options.contains(current) ? current : null;
    return DropdownButtonFormField<String>(
      key: ValueKey('country-$safe-${options.length}'),
      initialValue: safe,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(CupertinoIcons.globe),
      ),
      items: [
        if (includeAll)
          const DropdownMenuItem(value: _all, child: Text(kAllCountriesLabel)),
        for (final code in options)
          DropdownMenuItem(
            value: code,
            child: Text(
              counts.containsKey(code)
                  ? '${countryName(code)} (${counts[code]})'
                  : countryName(code),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: enabled
          ? (v) => onChanged(v == _all ? null : v)
          : null,
    );
  }
}

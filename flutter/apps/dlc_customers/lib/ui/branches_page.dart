import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'format.dart';
import 'tokens.dart';
import 'widgets.dart';

/// One branch: name, zone and country. The API does not publish opening
/// hours, so no open/closed status is shown.
class BranchTile extends StatelessWidget {
  const BranchTile({super.key, required this.branch});
  final Map<String, dynamic> branch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final zone = asStr(branch['zone']).trim();
    final country = countryName(branch['countryCode']);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              IconBadge(
                icon: CupertinoIcons.placemark,
                tone: context.dlc.accents[0],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asStr(branch['name']),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      zone.isEmpty ? country : '$zone · $country',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Branch directory grouped by country, with search.
class BranchesPage extends StatelessWidget {
  const BranchesPage({
    super.key,
    required this.branches,
    required this.search,
    required this.onSearchChanged,
  });
  final List<Map<String, dynamic>> branches;
  final TextEditingController search;
  final VoidCallback onSearchChanged;

  List<Map<String, dynamic>> get matching {
    final query = search.text.trim().toLowerCase();
    if (query.isEmpty) return branches;
    return branches
        .where(
          (b) =>
              '${asStr(b['name'])} ${asStr(b['zone'])} ${countryName(b['countryCode'])}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final list = matching;
    final byCountry = <String, List<Map<String, dynamic>>>{};
    for (final b in list) {
      byCountry.putIfAbsent(countryName(b['countryCode']), () => []).add(b);
    }
    final countries = byCountry.keys.toList()..sort();
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Semantics(
          header: true,
          child: const Text(
            'Sucursales',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: search,
          onChanged: (_) => onSearchChanged(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Buscar sucursal',
            prefixIcon: const Icon(CupertinoIcons.search),
            suffixIcon: search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Borrar búsqueda',
                    icon: const Icon(CupertinoIcons.xmark_circle_fill),
                    onPressed: () {
                      search.clear();
                      onSearchChanged();
                    },
                  ),
          ),
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          EmptyState(
            icon: CupertinoIcons.search,
            message: search.text.trim().isEmpty
                ? 'No hay sucursales activas por el momento.'
                : 'Ninguna sucursal coincide con tu búsqueda. Prueba con otro nombre o zona.',
          ),
        for (final country in countries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.flag,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      '$country · ${byCountry[country]!.length}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          DlcCard(
            weight: CardWeight.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < byCountry[country]!.length; i++) ...[
                  if (i > 0) const Divider(),
                  BranchTile(branch: byCountry[country]![i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

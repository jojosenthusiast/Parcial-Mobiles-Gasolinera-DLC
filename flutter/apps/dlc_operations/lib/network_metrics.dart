import 'package:dlc_api/dlc_api.dart';

import 'tank_levels.dart';

double _d(Object? v) => v == null ? 0 : (double.tryParse(v.toString()) ?? 0);
int _i(Object? v) => v == null ? 0 : (int.tryParse(v.toString()) ?? 0);
Map<String, dynamic> _m(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _l(Object? v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

/// One branch row of `GET /metrics/network/dashboard`.
class NetworkBranchRow {
  const NetworkBranchRow({
    required this.id,
    required this.name,
    required this.code,
    required this.countryCode,
    required this.inventoryRisk,
    required this.closedCuts,
    required this.expectedCuts,
    required this.tanks,
    required this.soldLiters,
    required this.salesUsd,
  });

  final String id;
  final String name;
  final String code;
  final String countryCode;

  /// `normal`, `warning`, `critical` or `unknown` (server policy).
  final String inventoryRisk;
  final int closedCuts;
  final int expectedCuts;
  final List<Map<String, dynamic>> tanks;
  final double soldLiters;
  final double salesUsd;

  List<FuelLevel> get fuelLevels => fuelLevelsFromTanks(tanks);
}

/// One day of `dailySeries`.
class DailyPoint {
  const DailyPoint({
    required this.date,
    required this.salesUsd,
    required this.soldLiters,
    required this.closedCuts,
  });
  final String date;
  final double salesUsd;
  final double soldLiters;
  final int closedCuts;
}

/// Parsed, tolerant view of the consolidated network response.
class NetworkDashboardData {
  const NetworkDashboardData({
    required this.periodDays,
    required this.rows,
    required this.daily,
    required this.countries,
    required this.canSales,
    required this.canInventory,
    required this.lastSourceAt,
  });

  final int periodDays;
  final List<NetworkBranchRow> rows;
  final List<DailyPoint> daily;
  final List<NetworkCountry> countries;
  final bool canSales;
  final bool canInventory;
  final String? lastSourceAt;

  static const empty = NetworkDashboardData(
    periodDays: 7,
    rows: [],
    daily: [],
    countries: [],
    canSales: false,
    canInventory: false,
    lastSourceAt: null,
  );

  /// [countryByBranchId] supplies countries for servers whose branch rows do
  /// not carry `countryCode` yet; unknown branches default to 'SV'.
  factory NetworkDashboardData.parse(
    Map<String, dynamic> data, {
    Map<String, String> countryByBranchId = const {},
  }) {
    final permissions = _m(data['permissions']);
    final rows = _l(data['branches']).map((b) {
      final id = (b['id'] ?? '').toString();
      final products = _l(b['products']);
      return NetworkBranchRow(
        id: id,
        name: (b['name'] ?? '').toString(),
        code: (b['code'] ?? '').toString(),
        countryCode: b['countryCode'] != null
            ? normalizeCountryCode(b['countryCode'])
            : normalizeCountryCode(countryByBranchId[id]),
        inventoryRisk: (b['inventoryRisk'] ?? 'unknown').toString(),
        closedCuts: _i(b['closedCuts']),
        expectedCuts: _i(b['expectedCuts']),
        tanks: _l(b['tanks']),
        soldLiters: products.fold(0.0, (s, p) => s + _d(p['soldLiters'])),
        salesUsd: products.fold(0.0, (s, p) => s + _d(p['salesUsd'])),
      );
    }).toList(growable: false);
    return NetworkDashboardData(
      periodDays: _i(data['periodDays']) == 0 ? 7 : _i(data['periodDays']),
      rows: rows,
      daily: _l(data['dailySeries'])
          .map(
            (p) => DailyPoint(
              date: (p['date'] ?? '').toString(),
              salesUsd: _d(p['salesUsd']),
              soldLiters: _d(p['soldLiters']),
              closedCuts: _i(p['closedCuts']),
            ),
          )
          .toList(growable: false),
      countries: NetworkCountry.listFrom(data['countries']),
      canSales: permissions['sales'] == true,
      canInventory: permissions['inventory'] == true,
      lastSourceAt: data['lastSourceAt']?.toString(),
    );
  }

  /// Rows after applying the country filter locally. Keeps the screen correct
  /// even when an older server ignores the `countryCode` query.
  List<NetworkBranchRow> visibleRows({String? countryCode}) {
    if (countryCode == null || countryCode.isEmpty) return rows;
    final wanted = normalizeCountryCode(countryCode);
    return rows
        .where((r) => r.countryCode == wanted)
        .toList(growable: false);
  }

  int closedCutsOf(List<NetworkBranchRow> list) =>
      list.fold(0, (s, r) => s + r.closedCuts);
  int expectedCutsOf(List<NetworkBranchRow> list) =>
      list.fold(0, (s, r) => s + r.expectedCuts);

  /// Fuel levels aggregated across the given branches.
  List<FuelLevel> fuelLevelsOf(List<NetworkBranchRow> list) =>
      fuelLevelsFromTanks(list.expand((r) => r.tanks));
}

import 'app_theme.dart';

/// Rubric thresholds: <= 30 % critical, <= 60 % medium, above 60 % optimal.
const double kTankCriticalMaxPercent = 30;
const double kTankMediumMaxPercent = 60;

DlcStatus tankStatusForPercent(double percent) {
  if (percent <= kTankCriticalMaxPercent) return DlcStatus.critical;
  if (percent <= kTankMediumMaxPercent) return DlcStatus.medium;
  return DlcStatus.optimal;
}

String tankStatusText(DlcStatus status) => switch (status) {
  DlcStatus.optimal => 'Nivel óptimo',
  DlcStatus.medium => 'Nivel medio',
  DlcStatus.critical => 'Nivel crítico',
  DlcStatus.warning => 'Atención',
  DlcStatus.info => 'Información',
};

const _familyOrder = ['super', 'regular', 'diesel'];

String fuelFamilyLabel(String family, {String? fallbackName}) =>
    switch (family) {
      'super' => 'Súper',
      'regular' => 'Regular',
      'diesel' => 'Diésel',
      _ =>
        (fallbackName != null && fallbackName.trim().isNotEmpty)
            ? fallbackName.trim()
            : 'Otro',
    };

double? _toDouble(Object? value) =>
    value == null ? null : double.tryParse(value.toString());

/// Aggregated level of one fuel family across the supplied tanks.
class FuelLevel {
  const FuelLevel({
    required this.family,
    required this.label,
    required this.percent,
    required this.liters,
    required this.capacityLiters,
    required this.tankCount,
    required this.unmeasuredTanks,
  });

  final String family;
  final String label;

  /// 0-100, or null when no tank of this fuel has a measurement.
  final double? percent;
  final double liters;
  final double capacityLiters;
  final int tankCount;
  final int unmeasuredTanks;

  DlcStatus? get status =>
      percent == null ? null : tankStatusForPercent(percent!);

  bool get isPartial => percent != null && unmeasuredTanks > 0;

  /// Text alternative used by screen readers and the visible caption.
  String get description {
    if (percent == null) return '$label: sin medición';
    final p = percent!.toStringAsFixed(0);
    final partial = isPartial ? ', medición parcial' : '';
    return '$label: $p %, ${tankStatusText(status!).toLowerCase()}$partial';
  }
}

/// Groups raw tank maps (`family`, `fuelName`, `onHandLiters`,
/// `capacityLiters`) by fuel family: Súper, Regular, Diésel, then the rest.
/// Only measured tanks contribute to the percentage.
List<FuelLevel> fuelLevelsFromTanks(Iterable<Map<String, dynamic>> tanks) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final tank in tanks) {
    final family = (tank['family'] ?? 'other').toString();
    groups.putIfAbsent(family, () => []).add(tank);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      int rank(String k) {
        final i = _familyOrder.indexOf(k);
        return i < 0 ? _familyOrder.length : i;
      }

      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
  return [
    for (final family in keys)
      _aggregate(family, groups[family]!),
  ];
}

FuelLevel _aggregate(String family, List<Map<String, dynamic>> tanks) {
  var liters = 0.0, measuredCapacity = 0.0, capacity = 0.0;
  var unmeasured = 0;
  for (final tank in tanks) {
    final cap = _toDouble(tank['capacityLiters']) ?? 0;
    capacity += cap;
    final onHand = _toDouble(tank['onHandLiters']);
    final missing = _toDouble(tank['missingBaselines'])?.toInt() ?? 0;
    if (onHand == null) {
      unmeasured += missing < 1 ? 1 : missing;
      continue;
    }
    unmeasured += missing;
    liters += onHand;
    measuredCapacity += cap;
  }
  final percent = measuredCapacity > 0
      ? (liters / measuredCapacity * 100).clamp(0, 100).toDouble()
      : null;
  return FuelLevel(
    family: family,
    label: fuelFamilyLabel(
      family,
      fallbackName: tanks.first['fuelName']?.toString(),
    ),
    percent: percent,
    liters: liters,
    capacityLiters: capacity,
    tankCount: tanks.length,
    unmeasuredTanks: unmeasured,
  );
}

/// Percentage for a single tank map: server `percentage` first, otherwise
/// computed from liters and capacity. Null when not measured.
double? tankPercent(Map<String, dynamic> tank) {
  final direct = _toDouble(tank['percentage']);
  if (direct != null) return direct.clamp(0, 100).toDouble();
  final onHand = _toDouble(tank['onHandLiters']);
  final capacity = _toDouble(tank['capacityLiters']);
  if (onHand == null || capacity == null || capacity <= 0) return null;
  return (onHand / capacity * 100).clamp(0, 100).toDouble();
}

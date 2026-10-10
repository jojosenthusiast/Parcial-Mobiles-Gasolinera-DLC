/// Data handed from an alert (low tank, cut summary) to the purchase order
/// flow so the order opens prefilled with fuel, tank and a suggested volume.
class PurchasePrefill {
  const PurchasePrefill({
    this.fuelProductId,
    this.tankId,
    this.tankCode,
    this.fuelName,
    this.suggestedLiters,
  });

  final String? fuelProductId, tankId, tankCode, fuelName;
  final double? suggestedLiters;

  bool get isEmpty =>
      (fuelProductId ?? '').isEmpty &&
      (tankId ?? '').isEmpty &&
      (fuelName ?? '').isEmpty;

  /// Suggested litres as plain text without decimals ("" when unknown).
  String get suggestedText {
    final v = suggestedLiters;
    if (v == null || v <= 0) return '';
    return v.round().toString();
  }
}

/// Litres needed to bring a tank back to [targetFraction] of its capacity,
/// rounded down to hundreds of litres. Null when capacity is unknown.
double? suggestedPurchaseLiters(
  double? capacityLiters,
  double? currentLiters, {
  double targetFraction = 0.9,
}) {
  if (capacityLiters == null || capacityLiters <= 0) return null;
  final missing = capacityLiters * targetFraction - (currentLiters ?? 0);
  if (missing <= 0) return 0;
  return (missing / 100).floorToDouble() * 100;
}

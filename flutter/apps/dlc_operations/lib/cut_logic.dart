/// Pure logic of the guided cut (no widgets): meter grid, validations,
/// per-fuel totals (sales / receipts / losses) and the tank outlook with the
/// 30 / 60 rule. Everything is table-testable.
library;

import 'app_theme.dart';
import 'tank_levels.dart';
import 'validators.dart';

const double kLitersPerUsGallon = 3.785411784;

double litersToGallons(double liters) => liters / kLitersPerUsGallon;

/// Steps of the guided cut, in order.
enum CutStep {
  choose('Elegir corte'),
  readings('Lecturas por bomba'),
  receipts('Recepciones'),
  losses('Pérdidas'),
  summary('Resumen y cierre');

  const CutStep(this.label);
  final String label;
}

/// Cut states in which readings / receipts / losses can still be captured.
bool cutAcceptsCapture(String? status) =>
    status == 'open' || status == 'in_progress';

/// States where the cut is already past capture (jump to the summary).
bool cutPastCapture(String? status) =>
    status == 'prepared' || status == 'inReview' || status == 'closed';

bool cutNeedsOpening(String? status) =>
    status == 'scheduled' || status == 'pending' || status == null;

/// Fuel family from a display name: super, regular, diesel or other.
String fuelFamilyOfName(String? name) {
  final n = (name ?? '')
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('ú', 'u')
      .replaceAll('í', 'i');
  if (n.contains('diesel')) return 'diesel';
  if (n.contains('super') || n.contains('premium')) return 'super';
  if (n.contains('regular')) return 'regular';
  return 'other';
}

const _familyRank = {'super': 0, 'regular': 1, 'diesel': 2, 'other': 3};

class MeterCell {
  const MeterCell({
    required this.nozzleId,
    required this.dispenser,
    required this.nozzleCode,
    required this.family,
    required this.fuelLabel,
    required this.initial,
    required this.meterVersion,
    required this.captured,
    this.capturedLiters,
  });
  final String nozzleId, dispenser, nozzleCode, family, fuelLabel;

  /// Last known meter value (the "initial" reading of the window), if any.
  final double? initial;
  final int meterVersion;
  final bool captured;
  final String? capturedLiters;
}

class MeterGrid {
  const MeterGrid(this.dispensers, this.families, this.cells);

  /// Pump codes in display order.
  final List<String> dispensers;

  /// Fuel families that exist in the grid (Súper, Regular, Diésel, ...).
  final List<String> families;
  final List<MeterCell> cells;

  List<MeterCell> forDispenser(String code) => [
    for (final c in cells)
      if (c.dispenser == code) c,
  ];

  int get total => cells.length;
  int get capturedCount => cells.where((c) => c.captured).length;
  int get pendingCount => total - capturedCount;
}

/// Builds the pump x fuel grid from the `nozzles` of `GET cuts/:id/assets`.
/// Excused nozzles are left out.
MeterGrid buildMeterGrid(Iterable<Map<String, dynamic>> nozzles) {
  final cells = <MeterCell>[];
  for (final n in nozzles) {
    if (n['participation'] == 'excused') continue;
    final id = (n['id'] ?? '').toString();
    if (id.isEmpty) continue;
    final fuelName = (n['fuelName'] ?? n['productName'] ?? '').toString();
    final family = fuelFamilyOfName(fuelName);
    cells.add(
      MeterCell(
        nozzleId: id,
        dispenser: (n['dispenserCode'] ?? n['dispenserId'] ?? '—').toString(),
        nozzleCode: (n['code'] ?? '—').toString(),
        family: family,
        fuelLabel: fuelFamilyLabel(family, fallbackName: fuelName),
        initial: double.tryParse('${n['lastMeterValue'] ?? ''}'),
        meterVersion: int.tryParse('${n['meterVersion'] ?? 0}') ?? 0,
        captured: n['cutReadingId'] != null,
        capturedLiters: n['measuredLiters']?.toString(),
      ),
    );
  }
  int rank(String f) => _familyRank[f] ?? 3;
  cells.sort((a, b) {
    final byPump = _naturalCompare(a.dispenser, b.dispenser);
    return byPump != 0 ? byPump : rank(a.family).compareTo(rank(b.family));
  });
  final dispensers = <String>[];
  for (final c in cells) {
    if (!dispensers.contains(c.dispenser)) dispensers.add(c.dispenser);
  }
  final families = <String>{for (final c in cells) c.family}.toList()
    ..sort((a, b) => rank(a).compareTo(rank(b)));
  return MeterGrid(dispensers, families, cells);
}

int _naturalCompare(String a, String b) {
  final na = int.tryParse(RegExp(r'\d+').firstMatch(a)?.group(0) ?? '');
  final nb = int.tryParse(RegExp(r'\d+').firstMatch(b)?.group(0) ?? '');
  if (na != null && nb != null && na != nb) return na.compareTo(nb);
  return a.compareTo(b);
}

/// Live validation of a typed meter reading (final >= initial).
String? validateMeterReading(String? text, double? initial) =>
    finalNotBelowInitial(text, initial, field: 'La lectura');

/// Translates a server message about a reading into plain Spanish while
/// keeping the original text when it is already readable.
String meterServerMessage(String message) {
  final m = message.toLowerCase();
  if (m.contains('continuidad') || m.contains('continuity')) {
    return 'La lectura no continúa la anterior: revisa el totalizador del surtidor. $message';
  }
  if (m.contains('duplic')) {
    return 'Esta lectura ya fue registrada. Actualiza el corte.';
  }
  return message;
}

/// Readings that can be sent now: non-empty, valid and not yet captured.
List<MeterCell> readyToSave(MeterGrid grid, Map<String, String> typed) => [
  for (final c in grid.cells)
    if (!c.captured &&
        (typed[c.nozzleId] ?? '').trim().isNotEmpty &&
        validateMeterReading(typed[c.nozzleId], c.initial) == null)
      c,
];

/// Typed readings that are invalid (blocks "Guardar").
List<MeterCell> invalidTyped(MeterGrid grid, Map<String, String> typed) => [
  for (final c in grid.cells)
    if (!c.captured &&
        (typed[c.nozzleId] ?? '').trim().isNotEmpty &&
        validateMeterReading(typed[c.nozzleId], c.initial) != null)
      c,
];

// ---------------------------------------------------------------------------
// Receipts and losses
// ---------------------------------------------------------------------------

/// Loss causes offered in the cut (code sent as `reasonCode`).
const Map<String, String> kLossCauses = {
  'evaporation': 'Evaporación',
  'spill': 'Derrame',
  'leak': 'Fuga',
  'calibration': 'Error de calibración',
  'theft': 'Robo o faltante',
  'contamination': 'Contaminación',
  'other': 'Otra causa',
};

String? validateReceiptLiters(String? text, double? freeCapacity) => notAbove(
  text,
  freeCapacity,
  field: 'Los litros recibidos',
  limitName: 'el espacio libre del tanque',
  maxDecimals: 3,
);

String? validateSupplier(String? v) =>
    minLengthText(v, 2, field: 'El proveedor') ??
    maxLengthText(v, 120, field: 'El proveedor');

String? validateFolio(String? v) =>
    requiredText(v, field: 'El folio') ?? maxLengthText(v, 120, field: 'El folio');

String? validateLossLiters(String? text, double? available) => notAbove(
  text,
  available,
  field: 'Los litros perdidos',
  limitName: 'lo que hay en el tanque',
  maxDecimals: 3,
);

String? validateLossExplanation(String? v) =>
    minLengthText(v, 8, field: 'La explicación') ??
    maxLengthText(v, 500, field: 'La explicación');

/// Space still free in a tank given its measured liters (null = unknown).
double? freeCapacity(double? capacity, double? measured) {
  if (capacity == null) return null;
  if (measured == null) return capacity;
  final free = capacity - measured;
  return free < 0 ? 0 : free;
}

// ---------------------------------------------------------------------------
// Totals per fuel (sales / receipts / losses)
// ---------------------------------------------------------------------------

class FuelTotals {
  const FuelTotals({
    required this.productId,
    required this.name,
    required this.soldLiters,
    required this.receiptsLiters,
    required this.lossLiters,
  });
  final String productId, name;
  final double soldLiters, receiptsLiters, lossLiters;

  double get soldGallons => litersToGallons(soldLiters);
}

/// Merges `postedDispenses` and `stockMovements` of `GET cuts/:id/progress`.
List<FuelTotals> fuelTotalsFromProgress(Map<String, dynamic> progress) {
  final byProduct = <String, ({String name, double sold, double rec, double loss})>{};
  void put(String id, String name, {double sold = 0, double rec = 0, double loss = 0}) {
    final cur = byProduct[id];
    byProduct[id] = (
      name: (cur?.name.isNotEmpty ?? false) ? cur!.name : name,
      sold: (cur?.sold ?? 0) + sold,
      rec: (cur?.rec ?? 0) + rec,
      loss: (cur?.loss ?? 0) + loss,
    );
  }

  for (final raw in (progress['postedDispenses'] as List? ?? const [])) {
    if (raw is! Map) continue;
    put(
      '${raw['fuelProductId']}',
      '${raw['productName'] ?? ''}',
      sold: double.tryParse('${raw['soldLiters'] ?? 0}') ?? 0,
    );
  }
  for (final raw in (progress['stockMovements'] as List? ?? const [])) {
    if (raw is! Map) continue;
    final liters = double.tryParse('${raw['liters'] ?? 0}') ?? 0;
    final isReceipt = raw['type'] == 'receipt';
    put(
      '${raw['fuelProductId']}',
      '${raw['productName'] ?? ''}',
      rec: isReceipt ? liters : 0,
      loss: raw['type'] == 'loss' ? liters : 0,
    );
  }
  for (final raw in (progress['products'] as List? ?? const [])) {
    if (raw is! Map) continue;
    put('${raw['fuelProductId']}', '${raw['productName'] ?? ''}');
  }
  final rows = [
    for (final e in byProduct.entries)
      FuelTotals(
        productId: e.key,
        name: e.value.name,
        soldLiters: e.value.sold,
        receiptsLiters: e.value.rec,
        lossLiters: e.value.loss,
      ),
  ];
  int rank(FuelTotals t) => _familyRank[fuelFamilyOfName(t.name)] ?? 3;
  rows.sort((a, b) => rank(a).compareTo(rank(b)));
  return rows;
}

// ---------------------------------------------------------------------------
// Tank outlook
// ---------------------------------------------------------------------------

enum Replenishment { none, advisory, urgent }

class TankOutlook {
  const TankOutlook({
    required this.tankId,
    required this.code,
    required this.fuelName,
    required this.fuelProductId,
    required this.capacityLiters,
    required this.measuredLiters,
  });
  final String tankId, code, fuelName, fuelProductId;
  final double? capacityLiters, measuredLiters;

  bool get measured => measuredLiters != null;

  double? get percent {
    final cap = capacityLiters, m = measuredLiters;
    if (cap == null || cap <= 0 || m == null) return null;
    return (m / cap * 100).clamp(0, 100).toDouble();
  }

  DlcStatus? get status => percent == null ? null : tankStatusForPercent(percent!);

  /// <= 30 % urgent purchase; <= 60 % plan a purchase; otherwise none.
  Replenishment get replenishment => switch (status) {
    DlcStatus.critical => Replenishment.urgent,
    DlcStatus.medium => Replenishment.advisory,
    _ => Replenishment.none,
  };
}

List<TankOutlook> tankOutlooks(Iterable<Map<String, dynamic>> tanks) => [
  for (final t in tanks)
    TankOutlook(
      tankId: '${t['id']}',
      code: '${t['code'] ?? 'Tanque'}',
      fuelName: '${t['fuelName'] ?? 'Combustible'}',
      fuelProductId: '${t['fuelProductId'] ?? ''}',
      capacityLiters: double.tryParse('${t['capacityLiters'] ?? ''}'),
      measuredLiters: double.tryParse('${t['measuredLiters'] ?? ''}'),
    ),
];

/// Everything needed before "Preparar conciliación": every pump reading and
/// every active tank measured.
({bool ready, List<String> missing}) cutReadiness(
  MeterGrid grid,
  List<TankOutlook> tanks,
) {
  final missing = <String>[];
  if (grid.pendingCount > 0) {
    missing.add('${grid.pendingCount} lectura(s) de bomba');
  }
  final unmeasured = tanks.where((t) => !t.measured).length;
  if (unmeasured > 0) missing.add('$unmeasured medición(es) de tanque');
  return (ready: missing.isEmpty, missing: missing);
}

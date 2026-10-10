import 'package:dlc_api/dlc_api.dart' show normalizeCountryCode;

/// Pure number, money and volume formatting shared by every screen.
///
/// Rules (DESIGN.md section 6):
///  * money and prices: 2 decimals by default (user preference 0-4),
///    thousands separator, the currency of the BRANCH (never a fixed USD);
///  * never add amounts of different currencies: use [MoneyTotals];
///  * volume in the chosen unit (litres or US gallons), litres without
///    decimals on cards and [DisplayPrefs.decimals] in detail views.

/// Litres in one US gallon.
const double kLitersPerGallon = 3.785411784;

enum VolumeUnit {
  liters,
  gallons;

  String get symbol => this == VolumeUnit.liters ? 'L' : 'gal';
  String get label => this == VolumeUnit.liters ? 'Litros' : 'Galones';
  String get storage => name;

  static VolumeUnit fromStorage(String? raw) =>
      raw == 'gallons' ? VolumeUnit.gallons : VolumeUnit.liters;
}

const int kDefaultDecimals = 2;
const int kMinDecimals = 0;
const int kMaxDecimals = 4;

int clampDecimals(int? value) =>
    (value ?? kDefaultDecimals).clamp(kMinDecimals, kMaxDecimals);

/// Currency (ISO 4217) of the branches of each country.
const Map<String, String> kCurrencyByCountry = {
  'SV': 'USD',
  'GT': 'GTQ',
  'HN': 'HNL',
  'NI': 'NIO',
  'CR': 'CRC',
  'PA': 'USD',
  'MX': 'MXN',
  'US': 'USD',
  'CO': 'COP',
};

/// Currency of a branch from its country; unknown countries fall back to USD.
String currencyForCountry(String? countryCode) =>
    kCurrencyByCountry[normalizeCountryCode(countryCode)] ?? 'USD';

const Map<String, String> _symbols = {
  'USD': 'US\$',
  'GTQ': 'Q',
  'NIO': 'C\$',
  'MXN': 'MX\$',
  'COP': 'COL\$',
};

/// Short symbol, or the ISO code when the symbol would be ambiguous.
String currencySymbol(String currency) {
  final code = currency.trim().toUpperCase();
  return _symbols[code] ?? (code.isEmpty ? 'US\$' : code);
}

/// "1,234.50" with a thousands separator and a fixed number of decimals.
String groupDigits(double value, {int decimals = 0}) {
  if (value.isNaN || value.isInfinite) return '-';
  final d = decimals.clamp(0, 9);
  final fixed = value.abs().toStringAsFixed(d);
  final parts = fixed.split('.');
  final digits = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  final isZero = double.parse(fixed) == 0;
  final sign = value < 0 && !isZero ? '-' : '';
  return '$sign$buffer${parts.length > 1 ? '.${parts[1]}' : ''}';
}

/// "US$ 1,234.50", "Q 1,234.50", "HNL 1,234.50".
String formatMoney(
  double value, {
  String currency = 'USD',
  int decimals = kDefaultDecimals,
}) => '${currencySymbol(currency)} ${groupDigits(value, decimals: clampDecimals(decimals))}';

double litersToUnit(double liters, VolumeUnit unit) =>
    unit == VolumeUnit.gallons ? liters / kLitersPerGallon : liters;

double unitToLiters(double value, VolumeUnit unit) =>
    unit == VolumeUnit.gallons ? value * kLitersPerGallon : value;

/// "1,500 L" / "396 gal". [decimals] 0 for cards, the user preference for
/// detail views.
String formatVolume(
  double liters, {
  VolumeUnit unit = VolumeUnit.liters,
  int decimals = 0,
}) => '${groupDigits(litersToUnit(liters, unit), decimals: decimals)} ${unit.symbol}';

/// Price of one litre shown per litre or per gallon: "US$ 3.45 / L".
String formatPricePerUnit(
  double pricePerLiter, {
  String currency = 'USD',
  VolumeUnit unit = VolumeUnit.liters,
  int decimals = kDefaultDecimals,
}) {
  final perUnit = unit == VolumeUnit.gallons
      ? pricePerLiter * kLitersPerGallon
      : pricePerLiter;
  return '${formatMoney(perUnit, currency: currency, decimals: decimals)} / ${unit.symbol}';
}

String formatPercent(double value, {int decimals = 0}) =>
    '${groupDigits(value, decimals: decimals)} %';

/// Signed variation "+2.5 %" / "-1.0 %" (for price arrows).
String formatVariation(double percent, {int decimals = 1}) {
  final text = groupDigits(percent.abs(), decimals: decimals);
  if (percent > 0 && double.parse(text.replaceAll(',', '')) != 0) return '+$text %';
  if (percent < 0 && double.parse(text.replaceAll(',', '')) != 0) return '-$text %';
  return '$text %';
}

/// Parses a server decimal string ("12.50000000"); null when missing/invalid.
double? parseAmount(Object? raw) =>
    raw == null ? null : double.tryParse(raw.toString().trim());

/// Formats a raw server amount ("12.50000000") as money; "-" when missing or
/// invalid. Used by screens that only have the server string.
String moneyRaw(
  Object? raw, {
  String currency = 'USD',
  int decimals = kDefaultDecimals,
}) {
  final v = parseAmount(raw);
  return v == null ? '-' : formatMoney(v, currency: currency, decimals: decimals);
}

/// Per-currency running totals. Different currencies are never added.
class MoneyTotals {
  MoneyTotals();

  /// Builds totals from already grouped (currency, amount) pairs.
  MoneyTotals.fromEntries(Iterable<MapEntry<String, double>> entries) {
    for (final e in entries) {
      add(e.key, e.value);
    }
  }

  final Map<String, double> _byCurrency = {};

  void add(String currency, double amount) {
    final code = currency.trim().toUpperCase();
    _byCurrency[code] = (_byCurrency[code] ?? 0) + amount;
  }

  bool get isEmpty => _byCurrency.isEmpty;
  bool get isMixed => _byCurrency.length > 1;
  int get currencyCount => _byCurrency.length;

  double of(String currency) => _byCurrency[currency.toUpperCase()] ?? 0;

  /// Entries sorted by amount (largest first), then by code.
  List<MapEntry<String, double>> get entries {
    final list = _byCurrency.entries.toList()
      ..sort((a, b) {
        final byAmount = b.value.compareTo(a.value);
        return byAmount != 0 ? byAmount : a.key.compareTo(b.key);
      });
    return list;
  }

  /// "US$ 1,200.00 + Q 340.50".
  String format({int decimals = kDefaultDecimals, String separator = ' + '}) =>
      entries
          .map((e) => formatMoney(e.value, currency: e.key, decimals: decimals))
          .join(separator);
}

/// User display preferences applied by every formatter.
class DisplayPrefs {
  const DisplayPrefs({
    this.unit = VolumeUnit.liters,
    this.decimals = kDefaultDecimals,
  });

  final VolumeUnit unit;
  final int decimals;

  static const defaults = DisplayPrefs();

  DisplayPrefs copyWith({VolumeUnit? unit, int? decimals}) => DisplayPrefs(
    unit: unit ?? this.unit,
    decimals: clampDecimals(decimals ?? this.decimals),
  );

  String money(double v, {String currency = 'USD'}) =>
      formatMoney(v, currency: currency, decimals: decimals);

  String totals(MoneyTotals t) => t.format(decimals: decimals);

  /// Litres in cards: no decimals.
  String volumeCard(double liters) =>
      formatVolume(liters, unit: unit, decimals: 0);

  /// Litres in detail views: the user's decimals.
  String volumeDetail(double liters) =>
      formatVolume(liters, unit: unit, decimals: decimals);

  String price(double perLiter, {String currency = 'USD'}) =>
      formatPricePerUnit(
        perLiter,
        currency: currency,
        unit: unit,
        decimals: decimals,
      );

  @override
  bool operator ==(Object other) =>
      other is DisplayPrefs && other.unit == unit && other.decimals == decimals;

  @override
  int get hashCode => Object.hash(unit, decimals);
}

/// "14:32" in 24 h from a local date.
String formatClock(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

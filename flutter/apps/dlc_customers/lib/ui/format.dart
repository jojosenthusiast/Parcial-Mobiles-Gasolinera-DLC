import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'tokens.dart';

// ---------------------------------------------------------------------------
// Loose JSON helpers shared by the UI layer.
// ---------------------------------------------------------------------------

String asStr(dynamic value) => value?.toString() ?? '';

Map<String, dynamic> asMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

List<Map<String, dynamic>> asMaps(dynamic value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false)
    : const [];

List<String> asStrings(dynamic value) => value is List
    ? value.map((item) => item.toString()).toList(growable: false)
    : const [];

/// Parses numbers that may arrive as num or as decimal strings.
double? parseNum(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(asStr(value).trim());
}

// ---------------------------------------------------------------------------
// Numbers
// ---------------------------------------------------------------------------

/// Fixed decimals plus a comma thousands separator: 1234.5 -> "1,234.50".
String formatNumber(num value, {int decimals = 2}) {
  final places = decimals.clamp(0, 6);
  var text = value.abs().toStringAsFixed(places);
  var fraction = '';
  final dot = text.indexOf('.');
  if (dot >= 0) {
    fraction = text.substring(dot);
    text = text.substring(0, dot);
  }
  final grouped = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) grouped.write(',');
    grouped.write(text[i]);
  }
  final isZero = double.parse(value.abs().toStringAsFixed(places)) == 0;
  final sign = value < 0 && !isZero ? '-' : '';
  return '$sign$grouped$fraction';
}

/// Whole points with thousands separator ("1,250"). Missing values read "0".
String formatPoints(dynamic value) =>
    formatNumber((parseNum(value) ?? 0).round(), decimals: 0);

/// "+120" / "-45" for ledger rows.
String formatSignedPoints(dynamic value) {
  final n = (parseNum(value) ?? 0).round();
  final body = formatNumber(n.abs(), decimals: 0);
  if (n > 0) return '+$body';
  if (n < 0) return '−$body';
  return body;
}

/// Money with currency code: "USD 1,234.50". Missing values read "—".
String formatMoney(dynamic value, {int decimals = 2, String currency = 'USD'}) {
  final n = parseNum(value);
  if (n == null) return '—';
  return '$currency ${formatNumber(n, decimals: decimals)}';
}

// ---------------------------------------------------------------------------
// Volume units
// ---------------------------------------------------------------------------

enum VolumeUnit {
  liter('Litros', 'litro', 'L'),
  gallon('Galones', 'galón', 'gal');

  const VolumeUnit(this.label, this.singular, this.short);
  final String label, singular, short;
}

const double litersPerUsGallon = 3.785411784;

/// Converts a price expressed per [from] ('us_gallon' or anything else = liter)
/// into the unit chosen by the customer.
double pricePerUnit(double price, String from, VolumeUnit to) {
  final fromGallon = from == 'us_gallon' || from == 'gallon';
  final toGallon = to == VolumeUnit.gallon;
  if (fromGallon == toGallon) return price;
  return fromGallon ? price / litersPerUsGallon : price * litersPerUsGallon;
}

// ---------------------------------------------------------------------------
// Dates (Spanish, device-local time)
// ---------------------------------------------------------------------------

const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

DateTime? parseDate(dynamic value) {
  final text = asStr(value).trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}

/// "10 oct 2026"; unparseable input falls back to the raw text.
String formatDate(dynamic value) {
  final date = parseDate(value);
  if (date == null) return asStr(value).isEmpty ? '—' : asStr(value);
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}

String formatTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

/// "10 oct 2026, 14:32"
String formatDateTime(dynamic value) {
  final date = parseDate(value);
  if (date == null) return formatDate(value);
  return '${formatDate(value)}, ${formatTime(date)}';
}

// ---------------------------------------------------------------------------
// Spanish labels with graceful fallback
// ---------------------------------------------------------------------------

/// Turns an internal key into readable text: "points_multiplier" ->
/// "Points multiplier". Never throws and never returns an empty string.
String humanize(dynamic raw) {
  final text = asStr(raw).trim().replaceAll(RegExp(r'[_\-]+'), ' ');
  if (text.isEmpty) return '—';
  return text[0].toUpperCase() + text.substring(1);
}

/// Visual identity of one ledger / status value.
@immutable
class StatusLook {
  const StatusLook(this.label, this.icon, this.kind);
  final String label;
  final IconData icon;
  final ToneKind kind;
}

enum ToneKind { ok, warn, crit, info, brand }

DlcTone toneFor(DlcColors colors, ToneKind kind, ColorScheme scheme) =>
    switch (kind) {
      ToneKind.ok => colors.ok,
      ToneKind.warn => colors.warn,
      ToneKind.crit => colors.crit,
      ToneKind.info => colors.info,
      ToneKind.brand => DlcTone(
        scheme.onPrimaryContainer,
        scheme.primaryContainer,
      ),
    };

/// Points ledger event types (server enum: earn, reserve, redeem, release,
/// expire, reverse, adjust).
StatusLook pointEventLook(dynamic type) => switch (asStr(type)) {
  'earn' => const StatusLook(
    'Puntos ganados',
    CupertinoIcons.plus_circle,
    ToneKind.ok,
  ),
  'reserve' => const StatusLook(
    'Puntos reservados',
    CupertinoIcons.lock,
    ToneKind.warn,
  ),
  'redeem' => const StatusLook(
    'Canje de puntos',
    CupertinoIcons.gift,
    ToneKind.brand,
  ),
  'release' => const StatusLook(
    'Reserva liberada',
    CupertinoIcons.lock_open,
    ToneKind.info,
  ),
  'expire' => const StatusLook(
    'Puntos vencidos',
    CupertinoIcons.timer,
    ToneKind.crit,
  ),
  'reverse' => const StatusLook(
    'Puntos revertidos',
    CupertinoIcons.arrow_uturn_left,
    ToneKind.crit,
  ),
  'adjust' => const StatusLook(
    'Ajuste de puntos',
    CupertinoIcons.slider_horizontal_3,
    ToneKind.info,
  ),
  _ => StatusLook(humanize(type), CupertinoIcons.circle, ToneKind.info),
};

/// Points-payment request statuses.
StatusLook quoteStatusLook(dynamic status) => switch (asStr(status)) {
  'pending' ||
  'open' => const StatusLook('Pendiente', CupertinoIcons.clock, ToneKind.warn),
  'confirmed' || 'approved' => const StatusLook(
    'Confirmada',
    CupertinoIcons.check_mark_circled,
    ToneKind.ok,
  ),
  'declined' || 'rejected' => const StatusLook(
    'Rechazada',
    CupertinoIcons.xmark_circle,
    ToneKind.crit,
  ),
  'expired' => const StatusLook('Vencida', CupertinoIcons.timer, ToneKind.warn),
  'cancelled' || 'canceled' => const StatusLook(
    'Cancelada',
    CupertinoIcons.nosign,
    ToneKind.crit,
  ),
  _ => StatusLook(humanize(status), CupertinoIcons.circle, ToneKind.info),
};

String pointEventLabel(dynamic type) => pointEventLook(type).label;
String quoteStatusLabel(dynamic status) => quoteStatusLook(status).label;

/// Notification event types: unknown ones still get a bell.
IconData notificationIcon(dynamic type) => switch (asStr(type)) {
  final t when t.contains('point') => CupertinoIcons.star,
  final t when t.contains('promo') => CupertinoIcons.tag,
  final t when t.contains('campaign') => CupertinoIcons.sparkles,
  _ => CupertinoIcons.bell,
};

const _countries = {
  'SV': 'El Salvador',
  'GT': 'Guatemala',
  'HN': 'Honduras',
  'NI': 'Nicaragua',
  'CR': 'Costa Rica',
  'PA': 'Panamá',
  'MX': 'México',
  'BZ': 'Belice',
  'CO': 'Colombia',
  'US': 'Estados Unidos',
};

/// Country name from an ISO code; unknown codes are shown upper-cased.
String countryName(dynamic code) {
  final key = asStr(code).trim().toUpperCase();
  if (key.isEmpty) return 'Sin país';
  return _countries[key] ?? key;
}

String promotionKindLabel(dynamic kind) => switch (asStr(kind)) {
  'unit_discount' => 'Descuento por volumen',
  'percent_discount' => 'Descuento porcentual',
  'cashback' => 'Cashback',
  'points_multiplier' => 'Puntos multiplicados',
  _ => 'Promoción informativa',
};

IconData promotionKindIcon(dynamic kind) => switch (asStr(kind)) {
  'unit_discount' => CupertinoIcons.drop,
  'percent_discount' => CupertinoIcons.percent,
  'cashback' => CupertinoIcons.money_dollar_circle,
  'points_multiplier' => CupertinoIcons.star,
  _ => CupertinoIcons.tag,
};

const _weekdays = {
  'mon': 'Lun',
  'monday': 'Lun',
  '1': 'Lun',
  'tue': 'Mar',
  'tuesday': 'Mar',
  '2': 'Mar',
  'wed': 'Mié',
  'wednesday': 'Mié',
  '3': 'Mié',
  'thu': 'Jue',
  'thursday': 'Jue',
  '4': 'Jue',
  'fri': 'Vie',
  'friday': 'Vie',
  '5': 'Vie',
  'sat': 'Sáb',
  'saturday': 'Sáb',
  '6': 'Sáb',
  'sun': 'Dom',
  'sunday': 'Dom',
  '0': 'Dom',
  '7': 'Dom',
};

String weekdayLabel(dynamic value) =>
    _weekdays[asStr(value).trim().toLowerCase()] ?? humanize(value);

/// Human headline for a promotion. Unit prices honour the customer's volume
/// unit and money decimals.
String promotionHeadline(
  Map<String, dynamic> promotion, {
  VolumeUnit unit = VolumeUnit.liter,
  int decimals = 2,
}) {
  final value = parseNum(promotion['value']);
  switch (asStr(promotion['kind'])) {
    case 'unit_discount':
      if (value == null) return promotionKindLabel('unit_discount');
      final from = asStr(promotion['valueUnit']);
      final converted = pricePerUnit(value, from, unit);
      final fromGallon = from == 'us_gallon' || from == 'gallon';
      final changed = fromGallon != (unit == VolumeUnit.gallon);
      final places = changed && decimals < 3 ? 3 : decimals;
      return '${formatMoney(converted, decimals: places)} menos por ${unit.singular}';
    case 'percent_discount':
      return value == null
          ? promotionKindLabel('percent_discount')
          : '${formatNumber(value, decimals: value == value.roundToDouble() ? 0 : 2)}% de descuento';
    case 'cashback':
      final cap = parseNum(promotion['benefitCapUsd']);
      final pct = value == null
          ? 'Cashback'
          : '${formatNumber(value, decimals: value == value.roundToDouble() ? 0 : 2)}% cashback';
      return cap == null
          ? pct
          : '$pct · tope ${formatMoney(cap, decimals: decimals)}';
    case 'points_multiplier':
      return value == null
          ? promotionKindLabel('points_multiplier')
          : '${formatNumber(value, decimals: value == value.roundToDouble() ? 0 : 1)}× puntos';
    default:
      return 'Promoción informativa';
  }
}

String recurrenceLabel(Map<String, dynamic> recurrence) => switch (asStr(
  recurrence['kind'],
)) {
  'weekly' =>
    'Semanal · ${asStrings(recurrence['weekdays']).map(weekdayLabel).join(', ')}',
  'monthly' => 'Mensual · día ${asStr(recurrence['dayOfMonth'])}',
  _ => 'Una vez',
};

/// Two-letter initials for avatars.
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return 'DL';
  final list = parts.toList();
  final first = list.first[0];
  final second = list.length > 1 ? list[1][0] : '';
  return (first + second).toUpperCase();
}

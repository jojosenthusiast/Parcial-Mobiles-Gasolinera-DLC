/// Display helpers for operational cuts. The window always comes from the API (`startsAt` / `endsAt`);
/// nothing here knows the schedule, so a branch template can change (academicLab22: 06:00-14:00 and
/// 14:00-22:00, with 22:00-06:00 outside any cut) without touching the clients.
library;

/// Spanish name of a cut by its slot ("Matutino" = slot 1, "Vespertino" = slot 2).
String cutName(Object? slot) {
  final value = slot?.toString();
  return value == '1'
      ? 'Matutino'
      : value == '2'
      ? 'Vespertino'
      : 'Corte ${value ?? '—'}';
}

/// "06:00–14:00" in the device's local time, or an empty string when the cut has no usable window.
String cutWindowLabel(Map<String, dynamic> cut) {
  final start = DateTime.tryParse(cut['startsAt']?.toString() ?? '')?.toLocal();
  final end = DateTime.tryParse(cut['endsAt']?.toString() ?? '')?.toLocal();
  if (start == null || end == null) return '';
  String hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  return '${hm(start)}–${hm(end)}';
}

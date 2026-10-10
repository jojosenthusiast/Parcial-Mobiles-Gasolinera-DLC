import 'package:dlc_operations/cut_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cut names follow the slot', () {
    expect(cutName(1), 'Matutino');
    expect(cutName('2'), 'Vespertino');
    expect(cutName(3), 'Corte 3');
    expect(cutName(null), 'Corte —');
  });

  test('the window is derived from the API timestamps, not from a schedule', () {
    String expected(String iso) {
      final d = DateTime.parse(iso).toLocal();
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    // academicLab22 in El Salvador (UTC-6): evening 14:00-22:00 local = 20:00Z-04:00Z.
    final evening = {
      'slot': 2,
      'startsAt': '2026-10-10T20:00:00.000Z',
      'endsAt': '2026-10-11T04:00:00.000Z',
    };
    expect(
      cutWindowLabel(evening),
      '${expected('2026-10-10T20:00:00Z')}–${expected('2026-10-11T04:00:00Z')}',
    );
    // Any other window renders as given: a legacy 14:00-06:00 evening is shown honestly too.
    final legacy = {
      'startsAt': '2026-10-10T20:00:00Z',
      'endsAt': '2026-10-11T12:00:00Z',
    };
    expect(
      cutWindowLabel(legacy),
      '${expected('2026-10-10T20:00:00Z')}–${expected('2026-10-11T12:00:00Z')}',
    );
  });

  test('a cut without a usable window renders nothing', () {
    expect(cutWindowLabel({'startsAt': 'nope', 'endsAt': null}), '');
    expect(cutWindowLabel({}), '');
  });
}

import 'package:dlc_operations/app_theme.dart';
import 'package:dlc_operations/tank_levels.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> tank(
  String family,
  Object? onHand,
  Object? capacity, {
  Object? missing,
}) => {
  'family': family,
  'fuelName': family,
  'onHandLiters': onHand,
  'capacityLiters': capacity,
  if (missing != null) 'missingBaselines': missing,
};

void main() {
  group('tankStatusForPercent', () {
    test('<= 30 is critical', () {
      expect(tankStatusForPercent(0), DlcStatus.critical);
      expect(tankStatusForPercent(29.9), DlcStatus.critical);
      expect(tankStatusForPercent(30), DlcStatus.critical);
    });
    test('<= 60 is medium', () {
      expect(tankStatusForPercent(30.01), DlcStatus.medium);
      expect(tankStatusForPercent(45), DlcStatus.medium);
      expect(tankStatusForPercent(60), DlcStatus.medium);
    });
    test('> 60 is optimal', () {
      expect(tankStatusForPercent(60.01), DlcStatus.optimal);
      expect(tankStatusForPercent(100), DlcStatus.optimal);
    });
    test('every status has accessible text', () {
      expect(tankStatusText(DlcStatus.critical), 'Nivel crítico');
      expect(tankStatusText(DlcStatus.medium), 'Nivel medio');
      expect(tankStatusText(DlcStatus.optimal), 'Nivel óptimo');
    });
  });

  group('fuelLevelsFromTanks', () {
    test('orders Súper, Regular, Diésel and aggregates liters', () {
      final levels = fuelLevelsFromTanks([
        tank('diesel', '800', '1000'),
        tank('super', '100', '1000'),
        tank('super', '300', '1000'),
        tank('regular', '650', '1000'),
      ]);
      expect(levels.map((l) => l.label), ['Súper', 'Regular', 'Diésel']);
      expect(levels[0].percent, 20);
      expect(levels[0].status, DlcStatus.critical);
      expect(levels[0].tankCount, 2);
      expect(levels[0].liters, 400);
      expect(levels[1].status, DlcStatus.optimal);
      expect(levels[2].status, DlcStatus.optimal);
    });

    test('unmeasured tanks do not count towards the percentage', () {
      final levels = fuelLevelsFromTanks([
        tank('regular', '500', '1000'),
        tank('regular', null, '1000'),
      ]);
      expect(levels.single.percent, 50);
      expect(levels.single.unmeasuredTanks, 1);
      expect(levels.single.isPartial, isTrue);
      expect(levels.single.description, contains('medición parcial'));
    });

    test('no measurements gives null percent and no status', () {
      final level = fuelLevelsFromTanks([tank('super', null, '1000')]).single;
      expect(level.percent, isNull);
      expect(level.status, isNull);
      expect(level.description, 'Súper: sin medición');
    });

    test('percent is clamped to 0-100 and other fuels keep their name', () {
      final levels = fuelLevelsFromTanks([
        tank('super', '1500', '1000'),
        {...tank('other', '10', '100'), 'fuelName': 'Kerosene'},
      ]);
      expect(levels.first.percent, 100);
      expect(levels.last.label, 'Kerosene');
    });

    test('description is a full text alternative', () {
      final level = fuelLevelsFromTanks([tank('diesel', '250', '1000')]).single;
      expect(level.description, 'Diésel: 25 %, nivel crítico');
    });
  });

  group('tankPercent', () {
    test('uses the server percentage first', () {
      expect(tankPercent({'percentage': '42.5', 'onHandLiters': '1'}), 42.5);
    });
    test('falls back to liters / capacity', () {
      expect(tankPercent(tank('super', '250', '1000')), 25);
    });
    test('null when not measurable', () {
      expect(tankPercent(tank('super', null, '1000')), isNull);
      expect(tankPercent(tank('super', '10', '0')), isNull);
    });
  });
}

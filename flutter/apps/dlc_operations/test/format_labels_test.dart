import 'package:dlc_operations/app_theme.dart';
import 'package:dlc_operations/code_suggest.dart';
import 'package:dlc_operations/format.dart';
import 'package:dlc_operations/labels.dart';
import 'package:dlc_operations/ui/wizard_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money', () {
    test('2 decimals, thousands separator and the currency symbol', () {
      expect(formatMoney(1234.5), 'US\$ 1,234.50');
      expect(formatMoney(0.9), 'US\$ 0.90');
      expect(formatMoney(1234567.891), 'US\$ 1,234,567.89');
      expect(formatMoney(-1234.5), 'US\$ -1,234.50');
      expect(formatMoney(3.456789, decimals: 0), 'US\$ 3');
      expect(formatMoney(3.456789, decimals: 4), 'US\$ 3.4568');
      expect(formatMoney(3.45, decimals: 9), 'US\$ 3.4500', reason: 'clamped to 4');
    });

    test('currency comes from the branch country', () {
      expect(currencyForCountry('SV'), 'USD');
      expect(currencyForCountry('GT'), 'GTQ');
      expect(currencyForCountry('HN'), 'HNL');
      expect(currencyForCountry('NI'), 'NIO');
      expect(currencyForCountry('CR'), 'CRC');
      expect(currencyForCountry('PA'), 'USD');
      expect(currencyForCountry('MX'), 'MXN');
      expect(currencyForCountry('US'), 'USD');
      expect(currencyForCountry('CO'), 'COP');
      expect(currencyForCountry('gt'), 'GTQ');
      expect(formatMoney(100, currency: 'GTQ'), 'Q 100.00');
      expect(formatMoney(100, currency: 'HNL'), 'HNL 100.00');
    });

    test('never adds different currencies', () {
      final t = MoneyTotals()
        ..add('USD', 100)
        ..add('GTQ', 250.5)
        ..add('USD', 20);
      expect(t.isMixed, isTrue);
      expect(t.of('USD'), 120);
      expect(t.of('GTQ'), 250.5);
      expect(t.format(), 'Q 250.50 + US\$ 120.00');
    });

    test('raw server strings are never shown with 8 decimals', () {
      expect(moneyRaw('12.50000000'), 'US\$ 12.50');
      expect(moneyRaw('0.85123400', decimals: 4), 'US\$ 0.8512');
      expect(moneyRaw(null), '-');
      expect(moneyRaw('abc'), '-');
    });
  });

  group('volume', () {
    test('converts litres and gallons with 3.785411784', () {
      expect(kLitersPerGallon, 3.785411784);
      expect(litersToUnit(3.785411784, VolumeUnit.gallons), closeTo(1, 1e-9));
      expect(unitToLiters(10, VolumeUnit.gallons), closeTo(37.85411784, 1e-9));
      expect(litersToUnit(100, VolumeUnit.liters), 100);
      expect(
        unitToLiters(litersToUnit(1234.5, VolumeUnit.gallons), VolumeUnit.gallons),
        closeTo(1234.5, 1e-9),
      );
    });

    test('cards without decimals, detail with the preference', () {
      expect(formatVolume(15000), '15,000 L');
      expect(formatVolume(3785.411784, unit: VolumeUnit.gallons), '1,000 gal');
      const prefs = DisplayPrefs(unit: VolumeUnit.gallons, decimals: 3);
      expect(prefs.volumeCard(3785.411784), '1,000 gal');
      expect(prefs.volumeDetail(1), '0.264 gal');
      expect(
        formatPricePerUnit(1, unit: VolumeUnit.gallons),
        'US\$ 3.79 / gal',
      );
      expect(formatPricePerUnit(0.9124), 'US\$ 0.91 / L');
    });

    test('decimals preference is clamped to 0..4', () {
      expect(clampDecimals(null), 2);
      expect(clampDecimals(-3), 0);
      expect(clampDecimals(9), 4);
      expect(const DisplayPrefs().copyWith(decimals: 12).decimals, 4);
    });

    test('variation text has sign and no -0', () {
      expect(formatVariation(2.54), '+2.5 %');
      expect(formatVariation(-1), '-1.0 %');
      expect(formatVariation(0.001), '0.0 %');
    });
  });

  group('status labels', () {
    test('server statuses are shown in Spanish', () {
      expect(statusLabel('active'), 'Activa');
      expect(statusLabel('configured'), 'En configuración');
      expect(statusLabel('draft'), 'Borrador');
      expect(statusLabel('suspended'), 'Suspendida');
      expect(statusLabel('pending_approval'), 'Pendiente de aprobación');
      expect(statusLabel('in_progress'), 'En proceso');
      expect(statusLabel('operational'), 'Disponible');
    });

    test('unknown or missing values fall back without raw snake_case', () {
      expect(statusLabel('partially_shipped'), 'Partially shipped');
      expect(statusLabel(null), 'Sin estado');
      expect(statusLabel(''), 'Sin estado');
      expect(statusSpec('weird_value').tone, DlcStatus.info);
      expect(statusLabel('inReview'), 'Requiere revisión');
    });

    test('severity ordering for alert centres', () {
      expect(severityRank('critical'), lessThan(severityRank('high')));
      expect(severityRank('high'), lessThan(severityRank('warning')));
      expect(severityRank('warning'), lessThan(severityRank('low')));
      expect(severityRank('whatever'), greaterThan(severityRank('low')));
    });
  });

  group('next code suggestion', () {
    test('keeps prefix and zero padding', () {
      expect(suggestNextCode(['QA-GT-01']), 'QA-GT-02');
      expect(suggestNextCode(['SV-001']), 'SV-002');
      expect(suggestNextCode(['SV-9', 'SV-10']), 'SV-11');
      expect(suggestNextCode(['A-099']), 'A-100');
    });

    test('uses the highest number with the same prefix', () {
      expect(suggestNextCode(['QA-GT-02', 'QA-GT-07', 'OTHER-90']), 'QA-GT-08');
    });

    test('empty list uses the fallback prefix', () {
      expect(suggestNextCode([], fallbackPrefix: 'EMP'), 'EMP-01');
      expect(suggestNextCode([]), isNull);
      expect(suggestNextCode(['sin-numero'], fallbackPrefix: 'SV-'), 'SV-01');
    });

    test('uniqueness is case-insensitive and explains how to fix it', () {
      expect(codeExists(['SV-001'], ' sv-001 '), isTrue);
      expect(codeExists(['SV-001'], 'SV-002'), isFalse);
      final validator = uniqueCodeValidator(() => ['SV-001']);
      expect(validator('sv-001'), contains('SV-002'));
      expect(validator('SV-002'), isNull);
      expect(validator(''), isNull);
      expect(uniqueCodeValidator(() => ['SV-001'], ignore: 'SV-001')('SV-001'), isNull);
    });

    test('branch code per country', () {
      expect(suggestBranchCode(['SV-001', 'GT-004'], 'SV'), 'SV-002');
      expect(suggestBranchCode(['SV-001', 'GT-004'], 'gt'), 'GT-005');
      expect(suggestBranchCode(const [], 'HN'), 'HN-01');
    });
  });

  group('wizard rules', () {
    test('resumes at the first step without a checkpoint', () {
      expect(resumeStepFor({'identity': {}}), 1);
      expect(resumeStepFor({'identity': {}, 'dispensers': {}}), 2);
      expect(resumeStepFor({'dispensers': {}, 'staff': {}}), 3);
      expect(resumeStepFor({'dispensers': {}, 'staff': {}, 'review': {}}), 4);
    });

    test('profile and tank rules', () {
      expect(profileForPumps(6), 'academicLab22');
      expect(profileForPumps(8), 'operational');
      expect(tanksForFuels('3', 3), isNull);
      expect(tanksForFuels('2', 3), contains('al menos un tanque por tipo'));
      expect(tanksForFuels('abc', 1), isNotNull);
      expect(tanksForFuels('21', 1), isNotNull);
      expect(wizardStepTitles.length, kWizardSteps);
      expect(wizardStepHints.length, kWizardSteps);
    });
  });
}

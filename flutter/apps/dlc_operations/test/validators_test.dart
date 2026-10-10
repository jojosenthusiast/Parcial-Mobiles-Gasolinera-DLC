import 'package:dlc_operations/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseDecimal', () {
    test('accepts dot and comma decimals', () {
      expect(parseDecimal('12.5'), 12.5);
      expect(parseDecimal(' 12,5 '), 12.5);
      expect(parseDecimal('0'), 0);
      expect(parseDecimal('-3'), -3);
    });
    test('rejects junk', () {
      expect(parseDecimal(''), isNull);
      expect(parseDecimal(null), isNull);
      expect(parseDecimal('1e3'), isNull);
      expect(parseDecimal('12.'), isNull);
      expect(parseDecimal('abc'), isNull);
    });
  });

  group('positiveNumber', () {
    test('required, numeric and > 0', () {
      expect(positiveNumber(''), contains('obligatorio'));
      expect(positiveNumber('x'), contains('número válido'));
      expect(positiveNumber('0'), contains('mayor que cero'));
      expect(positiveNumber('-1'), contains('mayor que cero'));
      expect(positiveNumber('1.5'), isNull);
    });
    test('zero allowed but not negatives', () {
      expect(positiveNumber('0', allowZero: true), isNull);
      expect(positiveNumber('-1', allowZero: true), contains('negativo'));
    });
    test('decimals and maximum', () {
      expect(positiveNumber('1.2345', maxDecimals: 3), contains('3 decimales'));
      expect(positiveNumber('1.234', maxDecimals: 3), isNull);
      expect(positiveNumber('11', max: 10), contains('no puede superar'));
    });
    test('uses the supplied field name', () {
      expect(
        positiveNumber('', field: 'El monto'),
        'El monto es un dato obligatorio.',
      );
    });
  });

  group('finalNotBelowInitial', () {
    test('final must be >= initial', () {
      expect(finalNotBelowInitial('100', 100), isNull);
      expect(finalNotBelowInitial('150.5', 100), isNull);
      expect(finalNotBelowInitial('99.9', 100), contains('menor que la inicial'));
    });
    test('without initial it only checks the number', () {
      expect(finalNotBelowInitial('5', null), isNull);
      expect(finalNotBelowInitial('', null), contains('obligatorio'));
      expect(finalNotBelowInitial('-1', null), contains('negativo'));
    });
  });

  group('notAbove and tank measure', () {
    test('quantity cannot exceed the limit', () {
      expect(notAbove('10', 10), isNull);
      expect(notAbove('10.1', 10), contains('no puede superar'));
      expect(notAbove('5', null), isNull);
      expect(notAbove('0', 10), contains('mayor que cero'));
    });
    test('tank liters allow zero but not above capacity', () {
      expect(tankMeasureLiters('0', 1000), isNull);
      expect(tankMeasureLiters('1000', 1000), isNull);
      expect(tankMeasureLiters('1001', 1000), contains('capacidad del tanque'));
    });
  });

  group('lossExplanation', () {
    test('no loss, no explanation needed', () {
      expect(lossExplanation('', lossAmount: 0), isNull);
      expect(lossExplanation('', lossAmount: null), isNull);
    });
    test('any loss requires a written explanation', () {
      expect(lossExplanation('', lossAmount: 5), contains('obligatorio'));
      expect(lossExplanation('corta', lossAmount: 5), contains('al menos 10'));
      expect(lossExplanation('Fuga en la manguera 3', lossAmount: 5), isNull);
    });
  });

  group('optionalNumber', () {
    test('empty is fine', () {
      expect(optionalNumber(''), isNull);
      expect(optionalNumber(null), isNull);
    });
    test('signed values for temperature', () {
      expect(optionalNumber('-5'), contains('negativo'));
      expect(optionalNumber('-5', signed: true), isNull);
      expect(optionalNumber('abc', signed: true), contains('número válido'));
    });
  });

  group('text validators', () {
    test('requiredText and length', () {
      expect(requiredText('  '), contains('obligatorio'));
      expect(requiredText('a'), isNull);
      expect(minLengthText('abc', 5, field: 'La nota'), contains('al menos 5'));
      expect(minLengthText('', 5), contains('obligatorio'));
      expect(maxLengthText('abcd', 3), contains('no puede superar 3'));
      expect(maxLengthText(null, 3), isNull);
    });
    test('emailAddress', () {
      expect(emailAddress(''), contains('obligatorio'));
      expect(emailAddress('a@b'), contains('válido'));
      expect(emailAddress('gerente@dlc.com'), isNull);
    });
    test('branchCode', () {
      expect(branchCode(''), contains('obligatorio'));
      expect(branchCode('SV 01'), contains('letras'));
      expect(branchCode('-SV'), contains('letras'));
      expect(branchCode('SV-001'), isNull);
      expect(branchCode('A' * 25), contains('24'));
    });
    test('ianaTimezone', () {
      expect(ianaTimezone(''), contains('obligatoria'));
      expect(ianaTimezone('Madrid'), contains('IANA'));
      expect(ianaTimezone('America/El_Salvador'), isNull);
      expect(ianaTimezone('UTC'), isNull);
    });
    test('personName', () {
      expect(personName(''), contains('obligatorio'));
      expect(personName('Al'), contains('3'));
      expect(personName('Ana Pérez'), isNull);
    });
    test('integerInRange', () {
      expect(integerInRange('x', min: 1, max: 200), contains('entero'));
      expect(integerInRange('0', min: 1, max: 200), contains('entre 1 y 200'));
      expect(integerInRange('201', min: 1, max: 200), contains('entre 1 y 200'));
      expect(integerInRange('6', min: 1, max: 200), isNull);
    });
  });

  group('composition', () {
    test('composeValidators returns the first failure', () {
      final v = composeValidators([
        (s) => requiredText(s),
        (s) => minLengthText(s, 4),
      ]);
      expect(v(''), contains('obligatorio'));
      expect(v('abc'), contains('al menos 4'));
      expect(v('abcd'), isNull);
    });
    test('allValid', () {
      expect(allValid([null, null]), isTrue);
      expect(allValid([null, 'error']), isFalse);
      expect(allValid(const []), isTrue);
    });
  });
}

import 'package:dlc_customers/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validators', () {
    test('validateEmail accepts a standard address', () {
      expect(validateEmail(' cliente@dlc.com '), isNull);
    });

    test('validateEmail rejects empty and malformed addresses', () {
      for (final value in [
        null,
        '',
        'cliente',
        'cliente@',
        '@dlc.com',
        'a b@dlc.com',
        'cliente@dlc',
      ]) {
        expect(
          validateEmail(value),
          'Escribe un correo válido.',
          reason: 'value: $value',
        );
      }
    });

    test('validatePassword requires at least 8 characters', () {
      expect(validatePassword(null), isNotNull);
      expect(validatePassword('1234567'), isNotNull);
      expect(validatePassword('12345678'), isNull);
    });

    test('validateFullName requires two non-blank characters', () {
      expect(validateFullName(null), isNotNull);
      expect(validateFullName(' A '), isNotNull);
      expect(validateFullName('Ana'), isNull);
    });
  });

  testWidgets('sign-in form shows email errors inline and blocks submit', (
    tester,
  ) async {
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthScreen(
            busy: false,
            onAction: (action) async {
              submitted = true;
              return true;
            },
            onChanged: () {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, 'correo');
    await tester.pump();
    expect(find.text('Escribe un correo válido.'), findsOneWidget);

    final signIn = find.text('Iniciar sesión');
    await tester.ensureVisible(signIn);
    await tester.tap(signIn);
    await tester.pump();
    expect(submitted, isFalse);
  });
}

import 'package:dlc_customers/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('promotion detail displays terms and branch', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PromotionDetailPage(
          promotion: {
            'title': 'Ahorro de prueba',
            'branchName': 'Sucursal Centro',
            'motive': 'Promoción de QA',
            'startsAt': '2026-10-01',
            'endsAt': '2026-10-31',
            'timeZone': 'America/Guatemala',
            'terms': {
              'applies': ['Gasolina regular'],
              'excludes': ['Diesel'],
            },
          },
        ),
      ),
    );
    expect(find.text('Ahorro de prueba'), findsOneWidget);
    expect(find.text('Sucursal: Sucursal Centro'), findsOneWidget);
    expect(find.text('Gasolina regular'), findsOneWidget);
    expect(find.text('Diesel'), findsOneWidget);
  });
}

import 'package:dlc_operations/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MetricCard presents its label, value and detail', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MetricCard(label: 'Ventas', value: '125', detail: 'Hoy', icon: Icons.payments, color: Colors.green))));
    expect(find.text('Ventas'), findsOneWidget);
    expect(find.text('125'), findsOneWidget);
    expect(find.text('Hoy'), findsOneWidget);
  });
}

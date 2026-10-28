import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movetrack_ai/widgets/stat_tile.dart';

void main() {
  testWidgets('StatTile menampilkan nilai dan satuan', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: StatTile('Jarak', '5.00', unit: 'km')),
    ));
    expect(find.text('5.00'), findsOneWidget);
    expect(find.text('km'), findsOneWidget);
  });
}

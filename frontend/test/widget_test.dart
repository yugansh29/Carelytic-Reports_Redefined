import 'package:carelytic_reports/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init();
  });

  testWidgets('ClinicNoteApp builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ClinicNoteApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.textContaining('Carelytic'), findsWidgets);
  });
}

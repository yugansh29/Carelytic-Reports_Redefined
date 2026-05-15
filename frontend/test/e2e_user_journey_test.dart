import 'dart:convert';

import 'package:carelytic_reports/api.dart';
import 'package:carelytic_reports/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UI journeys with mocked API (widget tests block real HTTP by default).
http.Client _mockBackend() {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.contains('/ehr/')) {
      final id = path.split('/ehr/').last;
      return http.Response(
        jsonEncode({
          'patient_id': id,
          'name': 'Demo',
          'active_problems': ['HTN'],
          'medications': ['Med 1'],
          'allergies': ['NKDA'],
          'recent_records': [
            {'type': 'Note', 'date': '2024-01-01', 'finding': 'Stable'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.contains('generate-soap')) {
      return http.Response(
        jsonEncode({
          'subjective': 'Patient reports back pain.',
          'objective': 'Vitals stable.',
          'assessment': 'Musculoskeletal pain.',
          'plan': 'Follow up in 2 weeks.',
          'differential_diagnoses': ['Strain'],
          'risk_assessment': 'Low.',
          'confidence_flags': <String>[],
          'is_fallback': false,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.contains('suggest-questions')) {
      return http.Response(
        jsonEncode({'questions': ['Any fever?', 'Trauma?']}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.contains('patient-summary')) {
      return http.Response(
        jsonEncode({
          'summary':
              'What We Found:\nYou have a minor strain.\n\nYour Next Steps:\n- Rest\n- Stretch',
          'is_fallback': false,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(jsonEncode({'detail': 'unmocked $path'}), 404);
  });
}

Future<void> _withE2eSurface(WidgetTester tester, Future<void> Function() body) async {
  ApiService.httpClient = _mockBackend();
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  SharedPreferences.setMockInitialValues({});
  await AppSettings.init();
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  try {
    await tester.pumpWidget(const ClinicNoteApp());
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 5));
    await body();
  } finally {
    ApiService.httpClient = null;
    debugDefaultTargetPlatformOverride = null;
    tester.binding.setSurfaceSize(null);
  }
}

Future<void> _tapHistory(WidgetTester tester) async {
  if (find.text('Report History').evaluate().isNotEmpty) {
    await tester.tap(find.text('Report History').first);
  } else {
    await tester.tap(find.text('History').first);
  }
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Dashboard loads and lists demo patients', (tester) async {
    await _withE2eSurface(tester, () async {
      expect(find.textContaining('Patient Visits'), findsOneWidget);
      expect(find.text('Raj Sharma'), findsOneWidget);
      expect(find.text('Register New Patient'), findsOneWidget);
    });
  });

  testWidgets('Compose: transcript + Generate SOAP shows SOAP sections', (tester) async {
    await _withE2eSurface(tester, () async {
      await tester.tap(find.text('Raj Sharma'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('Generate SOAP'), findsOneWidget);

      final transcriptField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText?.contains('Transcript') ?? false),
      );
      expect(transcriptField, findsOneWidget);
      await tester.enterText(
        transcriptField,
        'Doctor: How is the pain? Patient: Lower back pain for two weeks.',
      );
      await tester.pump();

      await tester.tap(find.text('Generate SOAP'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('SUBJECTIVE'), findsOneWidget);
      expect(find.text('OBJECTIVE'), findsOneWidget);

      expect(find.text('Patient Letter'), findsOneWidget);
      expect(find.text('Sign & Save'), findsOneWidget);
    });
  });

  testWidgets('Save note then open History', (tester) async {
    await _withE2eSurface(tester, () async {
      await tester.tap(find.text('Raj Sharma'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final transcriptField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText?.contains('Transcript') ?? false),
      );
      await tester.enterText(transcriptField, 'Brief visit: cough and fever.');
      await tester.pump();
      await tester.tap(find.text('Generate SOAP'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('SUBJECTIVE'), findsOneWidget);

      await tester.tap(find.text('Sign & Save'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await _tapHistory(tester);

      expect(find.textContaining('Reports History'), findsOneWidget);
      expect(find.text('Raj Sharma'), findsWidgets);
    });
  });

  testWidgets('Settings: open API configuration dialog', (tester) async {
    await _withE2eSurface(tester, () async {
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('Doctor Profile'), findsOneWidget);
      expect(find.text('API Configuration'), findsOneWidget);

      await tester.tap(find.text('API Configuration'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.textContaining('Backend API URL'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });
  });

  testWidgets('Register New Patient navigates to compose', (tester) async {
    await _withE2eSurface(tester, () async {
      await tester.tap(find.text('Register New Patient'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.textContaining('New Patient Encounter'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Integration Test Patient');
      await tester.pump();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), '40');
      await tester.pump();
      await tester.enterText(fields.last, 'Sore throat');
      await tester.pump();

      await tester.tap(find.text('Start Live Dictation'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('Generate SOAP'), findsOneWidget);
    });
  });
}

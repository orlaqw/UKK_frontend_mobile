// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:koshunter6/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App launches and routes to login when logged out', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MyApp());

    // Splash shows a loader first.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Splash waits 500ms then navigates based on stored token.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    // With empty prefs, token is null -> should land on login page.
    expect(find.text('Masuk untuk melanjutkan'), findsOneWidget);
  });
}

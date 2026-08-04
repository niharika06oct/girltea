// Smoke test for the GirlTea login screen.
//
// LoginScreen is self-contained (no Supabase call on build), so we can
// pump it directly without initializing the Supabase client.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:girltea/main.dart';

void main() {
  testWidgets('Login screen shows branding and Send code button',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('GirlTea'), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget);
    // Email field is pre-filled for the local dev slice.
    expect(find.text('diya@example.com'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:penny_ledger/services/auth_service.dart';
import 'package:penny_ledger/screens/login_screen.dart';

void main() {
  testWidgets('Login screen shows sign-in button', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [Provider<AuthService>(create: (_) => AuthService())],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.text('PennyLedger'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}

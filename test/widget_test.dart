import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';
import 'package:aegis_net/src/providers/theme_provider.dart';
import 'package:aegis_net/src/screens/main_navigation_screen.dart';

void main() {
  testWidgets('AegisApp smoke test & widget rendering',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    final vpnProvider = VpnProvider(enableSimulation: false);
    final themeProvider = ThemeProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: vpnProvider),
          ChangeNotifierProvider.value(value: themeProvider),
        ],
        child: const MaterialApp(
          home: MainNavigationScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('AEGIS NET'), findsOneWidget);

    vpnProvider.dispose();
    themeProvider.dispose();
  });
}

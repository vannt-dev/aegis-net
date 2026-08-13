import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../i18n/app_strings.dart';
import '../providers/theme_provider.dart';
import 'dashboard_screen.dart';
import 'rules_screen.dart';
import 'logs_screen.dart';
import 'analytics_screen.dart';
import 'settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  /// Built fresh on every build, deliberately.
  ///
  /// This was a `const` list held in a field, so `IndexedStack` received the
  /// identical widget objects each time and Flutter short-circuited the whole
  /// subtree. Only this widget rebuilt on a language change: the tab labels
  /// switched to the new language while every screen behind them stayed in the
  /// old one. New instances of the same types at the same positions keep their
  /// State, so nothing is lost by rebuilding them.
  /// `const` is wrong on these for the same reason: a const constructor is
  /// canonicalised, so `const RulesScreen()` is the same object every time and
  /// the subtree is skipped again.
  // ignore: prefer_const_constructors
  List<Widget> get _screens => [
        // ignore: prefer_const_constructors
        DashboardScreen(),
        // ignore: prefer_const_constructors
        RulesScreen(),
        // ignore: prefer_const_constructors
        LogsScreen(),
        // ignore: prefer_const_constructors
        AnalyticsScreen(),
        // ignore: prefer_const_constructors
        SettingsScreen(),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final accent = theme.primaryAccent;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF161B22),
          border: Border(top: BorderSide(color: Colors.white10, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: const Color(0xFF161B22),
          selectedItemColor: accent,
          unselectedItemColor: Colors.grey.shade500,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.shield_outlined),
              activeIcon: const Icon(Icons.shield_rounded),
              label: AppStrings.get('nav_dashboard'),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.list_alt_rounded),
              activeIcon: const Icon(Icons.list_alt_sharp),
              label: AppStrings.get('nav_rules'),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.history_toggle_off_rounded),
              activeIcon: const Icon(Icons.history_rounded),
              label: AppStrings.get('nav_logs'),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.analytics_outlined),
              activeIcon: const Icon(Icons.analytics),
              label: AppStrings.get('nav_analytics'),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_outlined),
              activeIcon: const Icon(Icons.settings),
              label: AppStrings.get('nav_settings'),
            ),
          ],
        ),
      ),
    );
  }
}

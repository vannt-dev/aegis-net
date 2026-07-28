import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NeonTheme {
  cyan,
  emerald,
  purple,
  gold,
}

class ThemeProvider extends ChangeNotifier {
  NeonTheme _currentTheme = NeonTheme.cyan;

  NeonTheme get currentTheme => _currentTheme;

  Color get primaryAccent {
    switch (_currentTheme) {
      case NeonTheme.cyan:
        return Colors.cyanAccent;
      case NeonTheme.emerald:
        return const Color(0xFF10B981);
      case NeonTheme.purple:
        return Colors.purpleAccent.shade100;
      case NeonTheme.gold:
        return Colors.amberAccent;
    }
  }

  Color get primaryDarkAccent {
    switch (_currentTheme) {
      case NeonTheme.cyan:
        return Colors.cyan.shade900;
      case NeonTheme.emerald:
        return const Color(0xFF065F46);
      case NeonTheme.purple:
        return Colors.purple.shade900;
      case NeonTheme.gold:
        return Colors.amber.shade900;
    }
  }

  String get themeName {
    switch (_currentTheme) {
      case NeonTheme.cyan:
        return 'Neon Cyan';
      case NeonTheme.emerald:
        return 'Emerald Green';
      case NeonTheme.purple:
        return 'Electric Purple';
      case NeonTheme.gold:
        return 'Sunset Gold';
    }
  }

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt('neon_theme_idx') ?? 0;
    if (index >= 0 && index < NeonTheme.values.length) {
      _currentTheme = NeonTheme.values[index];
      notifyListeners();
    }
  }

  void setTheme(NeonTheme theme) async {
    _currentTheme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('neon_theme_idx', theme.index);
    notifyListeners();
  }
}

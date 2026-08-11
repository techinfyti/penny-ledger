import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeColor {
  final String id;
  final String label;
  final Color seed;
  final Color appBarColor;
  final Color background;

  const AppThemeColor({
    required this.id,
    required this.label,
    required this.seed,
    required this.appBarColor,
    required this.background,
  });
}

const List<AppThemeColor> supportedThemeColors = [
  AppThemeColor(
    id: 'blue',
    label: 'Blue',
    seed: Colors.lightBlue,
    appBarColor: Color(0xFF0D3B66),
    background: Color(0xFFE3F2FD),
  ),
  AppThemeColor(
    id: 'green',
    label: 'Green',
    seed: Colors.green,
    appBarColor: Color(0xFF1B5E20),
    background: Color(0xFFE8F5E9),
  ),
  AppThemeColor(
    id: 'purple',
    label: 'Purple',
    seed: Colors.purple,
    appBarColor: Color(0xFF4A148C),
    background: Color(0xFFF3E5F5),
  ),
  AppThemeColor(
    id: 'orange',
    label: 'Orange',
    seed: Colors.orange,
    appBarColor: Color(0xFFE65100),
    background: Color(0xFFFFF3E0),
  ),
  AppThemeColor(
    id: 'red',
    label: 'Red',
    seed: Colors.red,
    appBarColor: Color(0xFFB71C1C),
    background: Color(0xFFFFEBEE),
  ),
  AppThemeColor(
    id: 'teal',
    label: 'Teal',
    seed: Colors.teal,
    appBarColor: Color(0xFF004D40),
    background: Color(0xFFE0F2F1),
  ),
];

class ThemeService extends ChangeNotifier {
  static const _prefsKey = 'theme_color_id';

  AppThemeColor _color = supportedThemeColors.first;
  AppThemeColor get color => _color;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_prefsKey);
    _color = supportedThemeColors.firstWhere(
      (c) => c.id == id,
      orElse: () => supportedThemeColors.first,
    );
    notifyListeners();
  }

  Future<void> setColor(AppThemeColor color) async {
    _color = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, color.id);
    notifyListeners();
  }
}

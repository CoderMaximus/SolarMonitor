import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  ThemeProvider() {
    initialize();
  }

  String currentTheme = 'dark';
  String currentSeed = 'blue';
  String uiMode = 'standard';
  String rustIp = '';
  String rustPort = '';
  bool isInitialized = false;

  ThemeMode get themeMode {
    switch (currentTheme) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Color get seedColor => switch (currentSeed) {
    'cyan' => Colors.cyan,
    'purple' => Colors.purple,
    'indigo' => Colors.indigo,
    'teal' => Colors.teal,
    _ => Colors.blue,
  };

  String get wsUrl => "ws://$rustIp:$rustPort";

  Future<void> updateNetwork(String ip, String port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rustIp', ip);
    await prefs.setString('rustPort', port);
    rustIp = ip;
    rustPort = port;
    notifyListeners();
  }

  Future<void> changeTheme(String theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', theme);
    currentTheme = theme;
    notifyListeners();
  }

  Future<void> changeSeed(String seed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('seed', seed);
    currentSeed = seed;
    notifyListeners();
  }

  // New method for UI Mode
  Future<void> changeUiMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('uiMode', mode);
    uiMode = mode;
    notifyListeners();
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    currentTheme = prefs.getString('theme') ?? 'dark';
    currentSeed = prefs.getString('seed') ?? 'blue';
    uiMode = prefs.getString('uiMode') ?? 'standard';
    rustIp = prefs.getString('rustIp') ?? '192.168.1.100';
    rustPort = prefs.getString('rustPort') ?? '3001';
    isInitialized = true;
    notifyListeners();
  }
}

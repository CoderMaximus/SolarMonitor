import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  ThemeProvider() {
    initialize();
  }

  String currentTheme = 'dark';
  String currentSeed = 'blue';
  String rustIp = '';
  String rustPort = '';
  bool isInitialized = false;

  ThemeMode get themeMode =>
      currentTheme == 'light' ? ThemeMode.light : ThemeMode.dark;

  Color get seedColor => switch (currentSeed) {
    'green' => Colors.green,
    'cyan' => Colors.cyan,
    'purple' => Colors.purple,
    'indigo' => Colors.indigo,
    'teal' => Colors.teal,
    _ => Colors.blue,
  };

  // WebSocket URL helper
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

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    currentTheme = prefs.getString('theme') ?? 'dark';
    currentSeed = prefs.getString('seed') ?? 'blue';
    rustIp =
        prefs.getString('rustIp') ?? '192.168.1.100'; // Fallback if never saved
    rustPort = prefs.getString('rustPort') ?? '3001';
    isInitialized = true;
    notifyListeners();
  }
}

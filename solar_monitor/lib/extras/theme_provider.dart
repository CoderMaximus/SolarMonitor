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
  String rustPort = '3001'; // WebSocket port
  String rustHttpPort = '3000'; // HTTP/History port
  bool isInitialized = false;

  // Advanced connection options (for ngrok, playit.gg, etc.)
  bool useDirectUrl = false; // When true, use direct URLs instead of ip:port
  String directDataProtocol = 'wss'; // Protocol for data: 'http', 'https', 'ws', 'wss'
  String directDataHost = ''; // Host without protocol (e.g., 'example.ngrok.io/ws')
  String directHistoryProtocol = 'https'; // Protocol for history: 'http', 'https', 'ws', 'wss'
  String directHistoryHost = ''; // Host without protocol (e.g., 'example.ngrok.io')

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

  // Data URL for live data stream (can be ws, wss, http, https)
  String get dataUrl {
    if (useDirectUrl && directDataHost.isNotEmpty) {
      return "$directDataProtocol://$directDataHost";
    }
    return "ws://$rustIp:$rustPort";
  }

  // Check if data endpoint uses WebSocket protocol
  bool get isDataWebSocket {
    if (useDirectUrl && directDataHost.isNotEmpty) {
      return directDataProtocol == 'ws' || directDataProtocol == 'wss';
    }
    return true; // Default IP:Port mode uses WebSocket
  }

  // Check if data endpoint uses HTTP protocol
  bool get isDataHttp => !isDataWebSocket;

  // Alias for backwards compatibility
  String get wsUrl => dataUrl;

  // Backward-compatible getters for checking if direct URLs are configured
  String get directWsUrl => directDataHost.isNotEmpty ? "$directDataProtocol://$directDataHost" : '';
  String get directHttpUrl => directHistoryHost.isNotEmpty ? "$directHistoryProtocol://$directHistoryHost" : '';

  // History URL (can be http, https, ws, wss)
  String get historyUrl {
    if (useDirectUrl && directHistoryHost.isNotEmpty) {
      return "$directHistoryProtocol://$directHistoryHost";
    }
    return "http://$rustIp:$rustHttpPort/history";
  }

  // Base HTTP URL (without /history) - for compatibility
  String get httpUrl {
    if (useDirectUrl && directHistoryHost.isNotEmpty) {
      // Remove /history suffix if present for base URL
      final host = directHistoryHost.endsWith('/history')
          ? directHistoryHost.substring(0, directHistoryHost.length - 8)
          : directHistoryHost;
      return "$directHistoryProtocol://$host";
    }
    return "http://$rustIp:$rustHttpPort";
  }

  Future<void> updateNetwork(String ip, String wsPort, String httpPort) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rustIp', ip);
    await prefs.setString('rustPort', wsPort);
    await prefs.setString('rustHttpPort', httpPort);
    rustIp = ip;
    rustPort = wsPort;
    rustHttpPort = httpPort;
    notifyListeners();
  }

  Future<void> updateAdvancedConnection({
    required bool useDirectUrl,
    required String directDataProtocol,
    required String directDataHost,
    required String directHistoryProtocol,
    required String directHistoryHost,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useDirectUrl', useDirectUrl);
    await prefs.setString('directDataProtocol', directDataProtocol);
    await prefs.setString('directDataHost', directDataHost);
    await prefs.setString('directHistoryProtocol', directHistoryProtocol);
    await prefs.setString('directHistoryHost', directHistoryHost);
    this.useDirectUrl = useDirectUrl;
    this.directDataProtocol = directDataProtocol;
    this.directDataHost = directDataHost;
    this.directHistoryProtocol = directHistoryProtocol;
    this.directHistoryHost = directHistoryHost;
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
    rustHttpPort = prefs.getString('rustHttpPort') ?? '3000';
    // Advanced connection options (for ngrok, playit.gg, etc.)
    useDirectUrl = prefs.getBool('useDirectUrl') ?? false;
    directDataProtocol = prefs.getString('directDataProtocol') ?? 'wss';
    directDataHost = prefs.getString('directDataHost') ?? '';
    directHistoryProtocol = prefs.getString('directHistoryProtocol') ?? 'https';
    directHistoryHost = prefs.getString('directHistoryHost') ?? '';
    isInitialized = true;
    notifyListeners();
  }
}

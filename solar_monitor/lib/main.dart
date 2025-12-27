import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'extras/theme_provider.dart';
import 'pages/tiles_page.dart';
import 'pages/settings_page.dart';
import 'pages/dashboard_page.dart';

void main() => runApp(
  ChangeNotifierProvider(
    create: (_) => ThemeProvider(),
    child: const InverterApp(),
  ),
);

class InverterApp extends StatelessWidget {
  const InverterApp({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: p.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: p.seedColor,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: p.seedColor,
        brightness: Brightness.dark,
      ),
      home: const MainEntryPage(),
    );
  }
}

class MainEntryPage extends StatefulWidget {
  const MainEntryPage({super.key});
  @override
  State<MainEntryPage> createState() => _MainEntryPageState();
}

class _MainEntryPageState extends State<MainEntryPage> {
  int _currentIndex = 1;

  final List<Widget> _pages = [
    const DashboardPage(),
    const TilesPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.power_outlined),
            label: 'Units',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Config',
          ),
        ],
      ),
    );
  }
}

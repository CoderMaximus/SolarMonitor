import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_nav_bar/google_nav_bar.dart'; // Add this import
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
    final p = context.watch<ThemeProvider>();
    final color = p.seedColor;

    return Scaffold(
      body: _pages[_currentIndex],
      // Container wrapper provides the background and shadow for the nav bar
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              blurRadius: 20,
              color: Colors.black.withValues(alpha: .1),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8),
            child: GNav(
              rippleColor: color.withValues(alpha: 0.3),
              hoverColor: color.withValues(alpha: 0.1),
              haptic: true,
              tabBorderRadius: 20,
              curve: Curves.easeInCirc,
              duration: const Duration(milliseconds: 300),
              gap: 8,
              color: Theme.of(context).hintColor,
              activeColor: color,
              iconSize: 24,
              tabBackgroundColor: color.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              selectedIndex: _currentIndex,
              onTabChange: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              tabs: const [
                GButton(icon: Icons.dashboard_outlined, text: 'Dashboard'),
                GButton(icon: Icons.power_outlined, text: 'Units'),
                GButton(icon: Icons.settings_outlined, text: 'Config'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

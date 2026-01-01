import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'extras/theme_provider.dart';
import 'pages/tiles_page.dart';
import 'pages/settings_page.dart';
import 'pages/graph_page.dart';
import 'alt/alt_dashboard.dart';

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
  int _currentIndex = 0;

  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>();
    final color = p.seedColor;

    final List<Widget> pages = p.uiMode == 'standard'
        ? [const GraphPage(), const TilesPage(), const SettingsPage()]
        : [const AltDashboard(), const GraphPage(), const SettingsPage()];

    final List<GButton> tabs = p.uiMode == 'standard'
        ? const [
            GButton(icon: Icons.dashboard_rounded, text: 'Dashboard'),
            GButton(icon: Icons.power_rounded, text: 'Units'),
            GButton(icon: Icons.settings_rounded, text: 'Settings'),
          ]
        : const [
            GButton(icon: Icons.bolt_rounded, text: 'Live'),
            GButton(icon: Icons.analytics_rounded, text: 'Statistics'),
            GButton(icon: Icons.settings_rounded, text: 'Settings'),
          ];

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: pages,
      ),
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
              curve: Curves.easeInOutCubic,
              duration: const Duration(milliseconds: 250),
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
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                );
              },
              tabs: tabs,
            ),
          ),
        ),
      ),
    );
  }
}

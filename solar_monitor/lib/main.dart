import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'extras/theme_provider.dart';
import 'pages/tiles_page.dart';
import 'pages/settings_page.dart';
import 'pages/graph_page.dart';
import 'pages/history_page.dart';
import 'alt/alt_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const InverterApp(),
    ),
  );
}

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

  // Icon pairs: [outlined, filled]
  static const List<List<IconData>> _standardIcons = [
    [Icons.dashboard_outlined, Icons.dashboard_rounded],
    [Icons.history_outlined, Icons.history_rounded],
    [Icons.power_outlined, Icons.power_rounded],
    [Icons.settings_outlined, Icons.settings_rounded],
  ];

  static const List<List<IconData>> _altIcons = [
    [Icons.bolt_outlined, Icons.bolt_rounded],
    [Icons.analytics_outlined, Icons.analytics_rounded],
    [Icons.history_outlined, Icons.history_rounded],
    [Icons.settings_outlined, Icons.settings_rounded],
  ];

  static const List<String> _standardLabels = ['Dashboard', 'History', 'Units', 'Settings'];
  static const List<String> _altLabels = ['Live', 'Statistics', 'History', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThemeProvider>();
    final color = provider.seedColor;

    final List<Widget> pages = provider.uiMode == 'standard'
        ? [const GraphPage(), const HistoryPage(), const TilesPage(), const SettingsPage()]
        : [const AltDashboard(), const GraphPage(), const HistoryPage(), const SettingsPage()];

    final icons = provider.uiMode == 'standard' ? _standardIcons : _altIcons;
    final labels = provider.uiMode == 'standard' ? _standardLabels : _altLabels;

    return Scaffold(
      body: PageView(
        physics: const NeverScrollableScrollPhysics(),
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
              tabs: List.generate(pages.length, (index) {
                final isSelected = _currentIndex == index;
                return GButton(
                  icon: isSelected ? icons[index][1] : icons[index][0],
                  text: labels[index],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

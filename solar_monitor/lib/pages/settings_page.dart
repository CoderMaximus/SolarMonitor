import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../extras/theme_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>();

    if (_ipController.text.isEmpty && p.isInitialized) {
      _ipController.text = p.rustIp;
      _portController.text = p.rustPort;
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Configuration"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: [
          _sectionHeader("Connection"),
          const SizedBox(height: 12),
          _buildSleekCard(
            child: Column(
              children: [
                _buildTextField(_ipController, "Server IP", Icons.lan_outlined),
                const Divider(height: 1, indent: 50),
                _buildTextField(
                  _portController,
                  "Port",
                  Icons.settings_ethernet,
                  isNumber: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              p.updateNetwork(_ipController.text, _portController.text);
              FocusScope.of(context).unfocus();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Network Settings Updated"),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.sync_rounded),
            label: const Text("Apply Network Changes"),
          ),
          const SizedBox(height: 32),
          _sectionHeader("Appearance"),
          const SizedBox(height: 12),
          _buildSleekCard(
            child: Column(
              children: [
                _buildSleekDropdown<String>(
                  label: "Theme Mode",
                  icon: Icons.palette_outlined,
                  value: p.currentTheme,
                  items: const [
                    DropdownMenuItem(value: 'dark', child: Text("Dark Mode")),
                    DropdownMenuItem(value: 'light', child: Text("Light Mode")),
                    DropdownMenuItem(
                      value: 'system',
                      child: Text("System Default"),
                    ),
                  ],
                  onChanged: (val) => p.changeTheme(val!),
                ),
                const Divider(height: 1, indent: 50),
                _buildSleekDropdown<String>(
                  label: "Accent Color",
                  icon: Icons.colorize_rounded,
                  value: p.currentSeed,
                  items: [
                    _colorOption('Blue', Colors.blue, 'blue'),
                    _colorOption('Green', Colors.green, 'green'),
                    _colorOption('Cyan', Colors.cyan, 'cyan'),
                    _colorOption('Purple', Colors.purple, 'purple'),
                    _colorOption('Teal', Colors.teal, 'teal'),
                    _colorOption('Indigo', Colors.indigo, 'indigo'),
                  ],
                  onChanged: (val) => p.changeSeed(val!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          const Center(
            child: Opacity(
              opacity: 0.5,
              child: Text(
                "Hardware Protocol: QPGS v1.2\nFull Data Stream Active",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildSleekCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
        ),
      ),
      child: child,
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isNumber = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildSleekDropdown<T>({
    required String label,
    required IconData icon,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                items: items,
                onChanged: onChanged,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                ),
                icon: const Icon(Icons.unfold_more_rounded, size: 20),
                borderRadius: BorderRadius.circular(12),
                dropdownColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHigh,
              ),
            ),
          ),
        ],
      ),
    );
  }

  DropdownMenuItem<String> _colorOption(
    String label,
    Color color,
    String value,
  ) {
    return DropdownMenuItem(
      value: value,
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }
}

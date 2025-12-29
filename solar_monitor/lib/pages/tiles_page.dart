import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../extras/theme_provider.dart';
import '../extras/router.dart';
import 'detail_page.dart';

class TilesPage extends StatelessWidget {
  const TilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>();

    // Safety check for initialization
    if (!p.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Connect to the WebSocket port (3001) as configured in your Rust server
    final channel = WebSocketChannel.connect(Uri.parse(p.wsUrl));

    return Scaffold(
      appBar: AppBar(title: const Text("System Units"), centerTitle: true),
      body: StreamBuilder(
        stream: channel.stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("Connection Error"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // The Rust server sends a Map: {"1": {...}, "2": {...}}
          Map<String, dynamic> unitsMap = jsonDecode(snapshot.data);

          // 1. Sort the keys (IDs) numerically so Unit 1 is always at the top
          List<String> sortedIds = unitsMap.keys.toList()
            ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedIds.length,
            itemBuilder: (context, index) {
              final String idKey = sortedIds[index];
              final Map<String, dynamic> invData = unitsMap[idKey];
              final List<dynamic> raw = invData['raw_data'];

              // 2. Extract the 14-digit Serial Number (BBBBBBBBBBBBBBB section)
              // In QPGS, the first field (index 0) is the 14-digit SN.
              String serialNumber = "Unknown SN";
              if (raw.isNotEmpty) {
                serialNumber = raw[1].toString().trim();
              }

              // Extracting secondary info for the subtitle
              final String loadW = raw.length > 9 ? "${raw[9]}W" : "---";
              final String battV = raw.length > 11 ? "${raw[11]}V" : "---";

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.1),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: p.seedColor.withValues(alpha: 0.1),
                    child: Icon(
                      Icons.developer_board_rounded,
                      color: p.seedColor,
                    ),
                  ),
                  title: Text(
                    serialNumber, // Shows the 14-digit string
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 0.5,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      "Unit #$idKey  •  $loadW  •  $battV",
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => Navigator.push(
                    context,
                    CustomPageRouter(
                      page: InverterDetailPage(
                        inverterId: int.parse(idKey),
                        initialData: invData,
                      ),
                      transitionType: TransitionType.slideFromRight,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

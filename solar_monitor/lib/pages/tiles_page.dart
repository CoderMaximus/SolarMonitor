import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../extras/theme_provider.dart';
import '../extras/router.dart';
import 'detail_page.dart';

class TilesPage extends StatefulWidget {
  const TilesPage({super.key});

  @override
  State<TilesPage> createState() => _TilesPageState();
}

class _TilesPageState extends State<TilesPage> {
  WebSocketChannel? _channel;
  // Use a broadcast stream to ensure the listener doesn't hang
  Stream? _broadcastStream;

  @override
  void initState() {
    super.initState();
    // We use a post-frame callback to ensure the context is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connect();
    });
  }

  void _connect() {
    final p = context.read<ThemeProvider>();
    if (p.rustIp.isEmpty) return;

    _cleanup(); // Close any old connections first

    try {
      final ws = WebSocketChannel.connect(Uri.parse(p.wsUrl));
      setState(() {
        _channel = ws;
        // Converting to broadcast stream helps prevent "loading forever"
        // because it allows multiple listeners and handles late subscribers better.
        _broadcastStream = _channel!.stream.asBroadcastStream();
      });
    } catch (e) {
      debugPrint("WS Connection Error: $e");
    }
  }

  void _cleanup() {
    _channel?.sink.close();
    _channel = null;
    _broadcastStream = null;
  }

  void _refresh() {
    setState(() {
      _cleanup();
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _connect();
    });
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>();

    if (!p.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("System Units"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Connection",
            onPressed: _refresh,
          ),
        ],
      ),
      body: _broadcastStream == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder(
              stream: _broadcastStream,
              builder: (context, snapshot) {
                // Handle Errors
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "Connection Lost",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _refresh,
                          child: const Text("Retry"),
                        ),
                      ],
                    ),
                  );
                }

                // Handle Loading/Waiting
                if (snapshot.connectionState == ConnectionState.waiting ||
                    !snapshot.hasData) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          "Awaiting data pulse...",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                try {
                  final Map<String, dynamic> unitsMap = jsonDecode(
                    snapshot.data.toString(),
                  );

                  if (unitsMap.isEmpty) {
                    return const Center(child: Text("No units detected."));
                  }

                  final sortedIds = unitsMap.keys.toList()
                    ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: sortedIds.length,
                    itemBuilder: (context, index) {
                      final String idKey = sortedIds[index];
                      final Map<String, dynamic> invData = unitsMap[idKey];
                      final List<dynamic> raw = invData['raw_data'] ?? [];

                      String serialNumber = "Unknown SN";
                      if (raw.isNotEmpty && raw.length > 1) {
                        serialNumber = raw[1].toString().trim();
                      }

                      final String loadW = raw.length > 9
                          ? "${raw[9]}W"
                          : "---";
                      final String battV = raw.length > 11
                          ? "${raw[11]}V"
                          : "---";

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
                            backgroundColor: p.seedColor.withValues(
                              alpha: 0.08,
                            ),
                            child: Icon(
                              Icons.developer_board_rounded,
                              color: p.seedColor,
                            ),
                          ),
                          title: Text(
                            serialNumber,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text("Unit #$idKey  •  $loadW  •  $battV"),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                          ),
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
                } catch (e) {
                  return const Center(child: Text("Data Sync Error"));
                }
              },
            ),
    );
  }
}

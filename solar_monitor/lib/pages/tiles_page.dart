import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:intl/intl.dart';
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
  Stream? _broadcastStream;
  Timer? _httpPollTimer;
  Map<String, dynamic>? _httpData;
  bool _isDisposed = false;

  final _f = NumberFormat("#,##0", "en_US");

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed) _connect();
    });
  }

  String _formatVal(dynamic val, String unit) {
    if (val == null) return "---";
    String s = val.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    double? num = double.tryParse(s);
    if (num == null) return "---";
    return "${_f.format(num)}$unit";
  }

  void _connect() {
    if (!mounted || _isDisposed) return;
    try {
      final provider = Provider.of<ThemeProvider>(context, listen: false);
      // Check if we have valid connection settings
      if (!provider.useDirectUrl && provider.rustIp.isEmpty) return;
      if (provider.useDirectUrl && provider.directWsUrl.isEmpty) return;
      _cleanup();

      if (provider.isDataWebSocket) {
        // Use WebSocket for ws:// or wss://
        final ws = WebSocketChannel.connect(Uri.parse(provider.dataUrl));
        if (mounted && !_isDisposed) {
          setState(() {
            _channel = ws;
            _broadcastStream = _channel!.stream.asBroadcastStream();
          });
        }
      } else {
        // Use HTTP polling for http:// or https://
        _startHttpPolling(provider);
      }
    } catch (e) {
      debugPrint("Connection Error: $e");
    }
  }

  void _startHttpPolling(ThemeProvider provider) {
    _fetchHttpData(provider);
    _httpPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && !_isDisposed) {
        _fetchHttpData(provider);
      }
    });
  }

  Future<void> _fetchHttpData(ThemeProvider provider) async {
    if (!mounted || _isDisposed) return;
    try {
      final response = await http.get(Uri.parse(provider.dataUrl));
      if (response.statusCode == 200 && mounted && !_isDisposed) {
        setState(() {
          _httpData = jsonDecode(response.body);
        });
      }
    } catch (e) {
      debugPrint("HTTP Fetch Error: $e");
    }
  }

  void _cleanup() {
    _channel?.sink.close();
    _channel = null;
    _broadcastStream = null;
    _httpPollTimer?.cancel();
    _httpPollTimer = null;
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _cleanup());
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted && !_isDisposed) _connect();
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
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
      body: _buildBody(p),
    );
  }

  Widget _buildBody(ThemeProvider p) {
    // HTTP polling mode
    if (p.isDataHttp) {
      if (_httpData == null) {
        return _buildWaitingUI();
      }
      return _buildUnitsList(_httpData!, p);
    }

    // WebSocket mode
    if (_broadcastStream == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder(
      stream: _broadcastStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _buildErrorUI();
        if (!snapshot.hasData) return _buildWaitingUI();

        try {
          final Map<String, dynamic> unitsMap = jsonDecode(
            snapshot.data.toString(),
          );
          return _buildUnitsList(unitsMap, p);
        } catch (e) {
          return const Center(child: Text("Data Sync Error"));
        }
      },
    );
  }

  Widget _buildUnitsList(Map<String, dynamic> unitsMap, ThemeProvider p) {
    if (unitsMap.isEmpty) {
      return const Center(child: Text("No units detected."));
    }

    // Numeric sort: 1, 2, 3...
    final sortedIds = unitsMap.keys.toList()
      ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedIds.length,
      itemBuilder: (context, index) {
        final String idKey = sortedIds[index];
        final Map<String, dynamic> invData = unitsMap[idKey];
        final List<dynamic> raw = invData['raw_data'] ?? [];

        String serialNumber = raw.isNotEmpty
            ? raw[1].toString().trim()
            : "Unknown SN";
        final String loadW = raw.length > 9
            ? _formatVal(raw[9], "W")
            : "---";
        final String battV = raw.length > 11
            ? _formatVal(raw[11], "V")
            : "---";

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: p.seedColor.withValues(alpha: 0.08),
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
            onTap: () {
              Navigator.push(
                context,
                CustomPageRouter(
                  page: InverterDetailPage(
                    inverterId: int.parse(idKey),
                    initialData: invData,
                  ),
                  transitionType: TransitionType.slideFromRight,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildErrorUI() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey),
        const SizedBox(height: 16),
        const Text(
          "Connection Lost",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: _refresh, child: const Text("Retry")),
      ],
    ),
  );

  Widget _buildWaitingUI() => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text("Awaiting data pulse...", style: TextStyle(color: Colors.grey)),
      ],
    ),
  );
}

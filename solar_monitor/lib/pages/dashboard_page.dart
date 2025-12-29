import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../extras/theme_provider.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final List<FlSpot> _loadSpots = [];
  final List<FlSpot> _pvSpots = [];
  bool _isFetchingHistory = false;
  bool _showPV = true;
  bool _showLoad = true;
  bool _hasInitialized = false;

  final double visibleMinutes = 120.0;
  WebSocketChannel? _channel;
  late TransformationController _transformationController;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _connectWebSocket();
    _fetchHistory();
  }

  void _initializeZoom() {
    if (!mounted) return;
    double calculatedScale = 1440 / visibleMinutes;
    setState(() {
      _transformationController.value = Matrix4.identity()
        ..scaleByDouble(calculatedScale, 1.0, 1.0, 1.0);
      _hasInitialized = true;
    });
  }

  void _connectWebSocket() {
    final p = context.read<ThemeProvider>();
    if (p.rustIp.isEmpty) return;
    _channel = WebSocketChannel.connect(Uri.parse("ws://${p.rustIp}:3001"));
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _transformationController.dispose();
    super.dispose();
  }

  double _parse(dynamic val) {
    if (val == null) return 0.0;
    String s = val.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(s) ?? 0.0;
  }

  Future<void> _fetchHistory() async {
    final provider = context.read<ThemeProvider>();
    if (_isFetchingHistory || provider.rustIp.isEmpty) return;
    setState(() => _isFetchingHistory = true);
    try {
      final res = await http.get(
        Uri.parse("http://${provider.rustIp}:3000/history"),
      );
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        final List<FlSpot> tempLoad = [];
        final List<FlSpot> tempPv = [];
        for (var pt in data) {
          double x = (pt['x'] as num).toDouble();
          tempLoad.add(FlSpot(x, (pt['load'] as num).toDouble()));
          tempPv.add(FlSpot(x, (pt['pv'] as num).toDouble()));
        }
        setState(() {
          _loadSpots.clear();
          _pvSpots.clear();
          _loadSpots.addAll(tempLoad);
          _pvSpots.addAll(tempPv);
        });
      }
    } catch (e) {
      debugPrint("History error: $e");
    }
    setState(() => _isFetchingHistory = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>();
    final color = p.seedColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "System Dashboard",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_out_map),
            onPressed: _initializeZoom,
          ),
        ],
      ),
      body: StreamBuilder(
        stream: _channel?.stream,
        builder: (context, snapshot) {
          double totalLoadWatts = 0;
          double totalPvWatts = 0;
          double totalKwhToday = 0;

          if (snapshot.hasData) {
            try {
              final Map<String, dynamic> data = jsonDecode(
                snapshot.data.toString(),
              );
              data.forEach((key, inv) {
                final List<dynamic> raw = inv['raw_data'] ?? [];
                if (raw.length >= 29) {
                  // PV Indices based on 29-field length
                  final double pv1V = _parse(raw[14]);
                  final double pv1A = _parse(raw[25]);
                  final double pv2V = _parse(raw[27]);
                  final double pv2A = _parse(raw[28]);

                  totalPvWatts += (pv1V * pv1A) + (pv2V * pv2A);
                  totalLoadWatts += _parse(raw[9]);
                }
                // FIXED: Rust already sends kWh, do not divide by 1000 here.
                totalKwhToday +=
                    double.tryParse(inv['qed']?.toString() ?? "0") ?? 0.0;
              });
            } catch (e) {
              debugPrint("Stream error: $e");
            }
          }

          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatHeader(
                  totalPvWatts,
                  totalLoadWatts,
                  totalKwhToday,
                  color,
                ),
                const SizedBox(height: 16),
                _buildToggles(color),
                const SizedBox(height: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (!_hasInitialized && constraints.maxWidth > 0) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _initializeZoom(),
                        );
                      }
                      return Container(
                        padding: const EdgeInsets.fromLTRB(5, 20, 15, 10),
                        child: LineChart(
                          transformationConfig: FlTransformationConfig(
                            scaleAxis: FlScaleAxis.horizontal,
                            minScale: 1.0,
                            maxScale: 25.0,
                            panEnabled: true,
                            scaleEnabled: true,
                            transformationController: _transformationController,
                          ),
                          _fixedChartData(color),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  LineChartData _fixedChartData(Color col) {
    return LineChartData(
      minX: 0,
      maxX: 1440,
      minY: 0,
      maxY: 16000,
      gridData: FlGridData(
        show: true,
        verticalInterval: 60,
        horizontalInterval: 4000,
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (v, m) => Text(
              "${(v / 1000).toInt()}k",
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 120,
            getTitlesWidget: (v, m) {
              int h = v.toInt() ~/ 60;
              return Text(
                "${h.toString().padLeft(2, '0')}:00",
                style: const TextStyle(fontSize: 9),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        if (_showPV && _pvSpots.isNotEmpty) _barData(_pvSpots, Colors.orange),
        if (_showLoad && _loadSpots.isNotEmpty) _barData(_loadSpots, col),
      ],
    );
  }

  LineChartBarData _barData(List<FlSpot> spots, Color c) => LineChartBarData(
    spots: spots,
    isCurved: false,
    color: c,
    barWidth: 2,
    dotData: const FlDotData(show: false),
    belowBarData: BarAreaData(show: true, color: c.withValues(alpha: 0.05)),
  );

  Widget _buildStatHeader(double pv, double load, double kwh, Color color) {
    return Row(
      children: [
        Expanded(
          child: _miniStat(
            "Solar",
            "${pv.toInt()}W",
            Icons.wb_sunny_rounded,
            Colors.orange,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniStat(
            "Load",
            "${load.toInt()}W",
            Icons.bolt_rounded,
            color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniStat(
            "Today",
            "${kwh.toStringAsFixed(1)}kWh",
            Icons.calendar_today_rounded,
            Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String label, String val, IconData icon, Color col) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, color: col, size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: col.withValues(alpha: 0.7),
            ),
          ),
          Text(
            val,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: col,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggles(Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _toggleCheck(
          "Solar",
          Colors.orange,
          _showPV,
          (v) => setState(() => _showPV = v!),
        ),
        const SizedBox(width: 24),
        _toggleCheck(
          "Load",
          color,
          _showLoad,
          (v) => setState(() => _showLoad = v!),
        ),
      ],
    );
  }

  Widget _toggleCheck(String l, Color c, bool v, Function(bool?) o) => Row(
    children: [
      Checkbox(
        value: v,
        onChanged: o,
        activeColor: c,
        visualDensity: VisualDensity.compact,
      ),
      Text(
        l,
        style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    ],
  );
}

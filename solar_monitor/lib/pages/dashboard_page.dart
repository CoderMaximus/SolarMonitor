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

  // --- CONFIGURATION ---
  // How many minutes of the day do you want to see on screen at once?
  // Lower number = Zoomed IN more. Higher number = Zoomed OUT.
  // 180 means 3 hours will fill the screen width.
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

  // Calculates and applies the zoom based on screen width
  void _initializeZoom() {
    if (!mounted) return;

    // The total width of the chart is 1440 minutes.
    // Scale = Total / What we want to see.
    double calculatedScale = 1440 / visibleMinutes;

    setState(() {
      // Apply the horizontal scale
      _transformationController.value = Matrix4.identity()
        ..scale(calculatedScale, 1.0, 1.0);
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

  Future<void> _fetchHistory() async {
    final p = context.read<ThemeProvider>();
    if (_isFetchingHistory || p.rustIp.isEmpty) return;
    setState(() => _isFetchingHistory = true);
    try {
      final res = await http.get(Uri.parse("http://${p.rustIp}:3000/history"));
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
      debugPrint("Fetch error: $e");
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
                if (raw.length > 15) {
                  totalPvWatts +=
                      (double.tryParse(raw[11].toString()) ?? 0) *
                          (double.tryParse(raw[12].toString()) ?? 0) +
                      (double.tryParse(raw[14].toString()) ?? 0) *
                          (double.tryParse(raw[15].toString()) ?? 0);
                  totalLoadWatts += double.tryParse(raw[9].toString()) ?? 0.0;
                }
                totalKwhToday +=
                    (double.tryParse(inv['qed']?.toString() ?? "0") ?? 0) /
                    1000.0;
              });
            } catch (_) {}
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
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _initializeZoom();
                        });
                      }

                      return Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
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
                const SizedBox(height: 12),
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
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (spot) => Colors.blueGrey.withValues(alpha: 0.9),
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              return LineTooltipItem(
                "${spot.y.toInt()} W",
                TextStyle(color: spot.bar.color, fontWeight: FontWeight.bold),
              );
            }).toList();
          },
        ),
      ),
      gridData: FlGridData(
        show: true,
        verticalInterval: 30,
        horizontalInterval: 4000,
        getDrawingHorizontalLine: (v) =>
            FlLine(color: Colors.grey.withValues(alpha: 0.05), strokeWidth: 1),
        getDrawingVerticalLine: (v) =>
            FlLine(color: Colors.grey.withValues(alpha: 0.08), strokeWidth: 1),
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
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 30,
            getTitlesWidget: (v, m) {
              if (v < 0 || v > 1440) return const SizedBox();
              int totalMinutes = v.toInt();
              int hour = totalMinutes ~/ 60;
              int minute = totalMinutes % 60;
              return SideTitleWidget(
                meta: m,
                space: 8,
                child: Text(
                  "${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}",
                  style: const TextStyle(fontSize: 8, color: Colors.grey),
                ),
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

  Widget _miniStat(String label, String val, IconData icon, Color col) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: col.withValues(alpha: 0.15)),
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
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              val,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: col,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleCheck(
    String label,
    Color col,
    bool val,
    Function(bool?) onChanged,
  ) {
    return Row(
      children: [
        Checkbox(
          value: val,
          onChanged: onChanged,
          activeColor: col,
          visualDensity: VisualDensity.compact,
        ),
        Text(
          label,
          style: TextStyle(
            color: col,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

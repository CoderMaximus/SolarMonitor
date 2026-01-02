import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:intl/intl.dart';
import '../extras/theme_provider.dart';

class GraphPage extends StatefulWidget {
  const GraphPage({super.key});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  final List<FlSpot> _loadSpots = [];
  final List<FlSpot> _pvSpots = [];
  bool _isFetchingHistory = false;
  bool _showPV = true;
  bool _showLoad = true;

  bool _hasJumpedOnce = false;
  bool _hasInitialized = false;

  final double visibleWindowMinutes = 100.0;
  final double totalMinutesInDay = 1440.0;
  final double leftReservedSize = 40.0;

  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;
  Timer? _refreshTimer;
  late TransformationController _transformationController;
  final GlobalKey _chartKey = GlobalKey();

  final _formatter = NumberFormat("#,##0", "en_US");

  double _currentPV = 0;
  double _currentLoad = 0;
  double _currentQed = 0;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _fetchHistory();
    _connectWebSocket();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _fetchHistory(shouldJump: false);
    });
  }

  void _jumpToCurrentTime() {
    if (!mounted) return;
    final RenderBox? box =
        _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return;

    final double chartDrawingWidth = box.size.width - leftReservedSize - 20;
    double scaleX = totalMinutesInDay / visibleWindowMinutes;

    final now = DateTime.now();
    final double currentMinutes = (now.hour * 60 + now.minute).toDouble();

    double totalZoomedWidth = chartDrawingWidth * scaleX;
    double nowPixelPos =
        (currentMinutes / totalMinutesInDay) * totalZoomedWidth;

    double scrollOffset = nowPixelPos - (chartDrawingWidth * 0.8);
    double maxScroll = totalZoomedWidth - chartDrawingWidth;
    scrollOffset = scrollOffset.clamp(0.0, maxScroll);

    setState(() {
      _transformationController.value = Matrix4.identity()
        ..scaleByDouble(scaleX, 1.0, 1.0, 1.0)
        ..translateByDouble(-scrollOffset / scaleX, 0.0, 0.0, 1.0);
      _hasInitialized = true;
      _hasJumpedOnce = true;
    });
  }

  void _connectWebSocket() {
    final p = context.read<ThemeProvider>();
    if (p.rustIp.isEmpty) return;

    try {
      _channel = WebSocketChannel.connect(Uri.parse("ws://${p.rustIp}:3001"));
      _wsSubscription = _channel?.stream.listen(
        (message) => _handleIncomingData(message),
        onError: (err) {
          debugPrint("WS Error: $err");
          Future.delayed(const Duration(seconds: 5), _connectWebSocket);
        },
        onDone: () =>
            Future.delayed(const Duration(seconds: 5), _connectWebSocket),
      );
    } catch (e) {
      debugPrint("WS Connection Error: $e");
    }
  }

  void _handleIncomingData(dynamic message) {
    try {
      final data = jsonDecode(message.toString());
      double newPV = 0, newLoad = 0, newQed = 0;

      data.forEach((k, v) {
        final raw = v['raw_data'] ?? [];
        if (raw.length >= 29) {
          newPV +=
              (_parse(raw[14]) * _parse(raw[25])) +
              (_parse(raw[27]) * _parse(raw[28]));
          newLoad += _parse(raw[9]);
        }
        newQed += _parse(v['qed']);
      });

      final now = DateTime.now();
      final double x = (now.hour * 60 + now.minute).toDouble();

      if (mounted) {
        setState(() {
          _currentPV = newPV;
          _currentLoad = newLoad;
          _currentQed = newQed;

          if (_pvSpots.isEmpty || _pvSpots.last.x != x) {
            _pvSpots.add(FlSpot(x, newPV));
            _loadSpots.add(FlSpot(x, newLoad));
            if (_pvSpots.length > 2000) {
              _pvSpots.removeAt(0);
              _loadSpots.removeAt(0);
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Data handling error: $e");
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _channel?.sink.close();
    _refreshTimer?.cancel();
    _transformationController.dispose();
    super.dispose();
  }

  double _parse(dynamic val) {
    if (val == null) return 0.0;
    String string = val.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(string) ?? 0.0;
  }

  Future<void> _fetchHistory({bool shouldJump = true}) async {
    final p = context.read<ThemeProvider>();
    if (_isFetchingHistory || p.rustIp.isEmpty) return;
    setState(() => _isFetchingHistory = true);

    try {
      final res = await http.get(Uri.parse("http://${p.rustIp}:3000/history"));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        final List<FlSpot> tLoad = [];
        final List<FlSpot> tPv = [];
        for (var pt in data) {
          double x = (pt['x'] as num).toDouble();
          tLoad.add(FlSpot(x, (pt['load'] as num).toDouble()));
          tPv.add(FlSpot(x, (pt['pv'] as num).toDouble()));
        }
        tLoad.sort((a, b) => a.x.compareTo(b.x));
        tPv.sort((a, b) => a.x.compareTo(b.x));

        if (mounted) {
          setState(() {
            _loadSpots.clear();
            _pvSpots.clear();
            _loadSpots.addAll(tLoad);
            _pvSpots.addAll(tPv);
            if (shouldJump || !_hasJumpedOnce) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _jumpToCurrentTime(),
              );
            }
          });
        }
      }
    } catch (e) {
      debugPrint("History Error: $e");
    }
    if (mounted) setState(() => _isFetchingHistory = false);
  }

  void _manualRefresh() {
    _fetchHistory(shouldJump: true);
    _startAutoRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>();
    final color = p.seedColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "System Dashboard",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.access_time_filled_rounded),
            onPressed: _jumpToCurrentTime,
            tooltip: "Jump to Now",
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _manualRefresh,
            tooltip: "Refresh Data",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatHeader(_currentPV, _currentLoad, _currentQed, color),
            const SizedBox(height: 16),
            _buildToggles(color),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (!_hasInitialized && constraints.maxWidth > 0) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _jumpToCurrentTime(),
                    );
                  }
                  return Container(
                    key: _chartKey,
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
                      _mainChartData(color),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _mainChartData(Color color) {
    return LineChartData(
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        touchTooltipData: LineTouchTooltipData(
          maxContentWidth: 120,
          getTooltipColor: (touchedSpot) => Colors.black.withValues(alpha: 0.8),
          getTooltipItems: (List<LineBarSpot> touchedSpots) {
            return touchedSpots.map((LineBarSpot touchedSpot) {
              final isSolar = touchedSpot.barIndex == 0;
              final textColor = isSolar ? Colors.green : color;
              final int totalMinutes = touchedSpot.x.toInt();
              final String hour = (totalMinutes ~/ 60).toString().padLeft(
                2,
                '0',
              );
              final String min = (totalMinutes % 60).toString().padLeft(2, '0');

              return LineTooltipItem(
                '$hour:$min\n',
                const TextStyle(color: Colors.white, fontSize: 10),
                children: [
                  TextSpan(
                    text: '${_formatter.format(touchedSpot.y)} W',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              );
            }).toList();
          },
        ),
      ),
      minX: 0,
      maxX: 1440,
      minY: 0,
      maxY: 16000,
      gridData: FlGridData(
        show: true,
        verticalInterval: 60,
        horizontalInterval: 4000,
        getDrawingHorizontalLine: (v) =>
            FlLine(color: Colors.grey.withValues(alpha: 0.1), strokeWidth: 1),
        getDrawingVerticalLine: (v) =>
            FlLine(color: Colors.grey.withValues(alpha: 0.1), strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: leftReservedSize,
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
              if (h < 0 || h >= 24) return const SizedBox();
              return Text(
                "${h.toString().padLeft(2, '0')}:00",
                style: const TextStyle(fontSize: 8),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        if (_showPV && _pvSpots.isNotEmpty) _barData(_pvSpots, Colors.green),
        if (_showLoad && _loadSpots.isNotEmpty) _barData(_loadSpots, color),
      ],
    );
  }

  LineChartBarData _barData(List<FlSpot> spots, Color c) => LineChartBarData(
    spots: spots,
    isCurved: true,
    color: c,
    barWidth: 2.0,
    dotData: const FlDotData(show: false),
    belowBarData: BarAreaData(show: true, color: c.withValues(alpha: 0.05)),
  );

  Widget _buildStatHeader(double pv, double load, double kwh, Color color) {
    return Row(
      children: [
        Expanded(
          child: _miniStat(
            "Solar",
            "${_formatter.format(pv)}W",
            Icons.wb_sunny_rounded,
            Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniStat(
            "Load",
            "${_formatter.format(load)}W",
            Icons.bolt_rounded,
            color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniStat(
            "Today",
            "${kwh.toStringAsFixed(2)}kWh",
            Icons.calendar_today_rounded,
            Colors.yellow[700]!,
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
          Icon(icon, color: col, size: 24),
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
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: col,
              ),
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
          Colors.green,
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

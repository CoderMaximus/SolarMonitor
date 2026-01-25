import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../extras/theme_provider.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final List<FlSpot> _loadSpots = [];
  final List<FlSpot> _pvSpots = [];
  final Map<double, String> _timeLabels = {};
  bool _isFetching = false;
  bool _showPV = true;
  bool _showLoad = true;
  bool _hasInitialized = false;

  late DateTime _selectedDate;
  late TransformationController _transformationController;
  final GlobalKey _chartKey = GlobalKey();

  final double visibleWindowMinutes = 100.0;
  final double totalMinutesInDay = 1440.0;
  final double leftReservedSize = 40.0;

  final _formatter = NumberFormat("#,##0", "en_US");
  final _dateFormatter = DateFormat('yyyy-MM-dd');

  double _totalQed = 0;
  Map<String, double> _qedPerInverter = {};

  // Available dates from server
  List<String> _availableDates = [];
  DateTime? _earliestDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _transformationController = TransformationController();
    _fetchAvailableDates();
    _fetchHistoryForDate();
  }

  Future<void> _fetchAvailableDates() async {
    if (!mounted) return;
    final p = context.read<ThemeProvider>();
    if (!p.useDirectUrl && p.rustIp.isEmpty) return;
    if (p.useDirectUrl && p.directHttpUrl.isEmpty) return;

    try {
      final res = await http.get(Uri.parse("${p.httpUrl}/dates"));
      if (res.statusCode == 200) {
        final List<dynamic> dates = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _availableDates = dates.cast<String>();
            // Always include today
            final today = _dateFormatter.format(DateTime.now());
            if (!_availableDates.contains(today)) {
              _availableDates.add(today);
            }
            _availableDates.sort();

            if (_availableDates.isNotEmpty) {
              _earliestDate = DateTime.tryParse(_availableDates.first);
            } else {
              // If no dates available, set earliest to today
              _earliestDate = DateTime.now();
            }
            debugPrint(
              "Available dates: $_availableDates, earliest: $_earliestDate",
            );
          });
        }
      } else {
        // If endpoint fails, set earliest to today
        if (mounted) {
          setState(() {
            _earliestDate = DateTime.now();
            _availableDates = [_dateFormatter.format(DateTime.now())];
          });
        }
      }
    } catch (e) {
      debugPrint("Fetch available dates error: $e");
      // On error, default to today only
      if (mounted) {
        setState(() {
          _earliestDate = DateTime.now();
          _availableDates = [_dateFormatter.format(DateTime.now())];
        });
      }
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  bool get _canGoBack {
    if (_earliestDate == null) return false; // No data, can't go back
    // Compare dates only (ignore time)
    final selectedDateOnly = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final earliestDateOnly = DateTime(
      _earliestDate!.year,
      _earliestDate!.month,
      _earliestDate!.day,
    );
    // Can go back if selected date is after earliest date
    return selectedDateOnly.isAfter(earliestDateOnly);
  }

  bool get _canGoBackMonth {
    if (_earliestDate == null) return false; // No data, can't go back
    final prevMonth = DateTime(
      _selectedDate.year,
      _selectedDate.month - 1,
      _selectedDate.day,
    );
    final earliestDateOnly = DateTime(
      _earliestDate!.year,
      _earliestDate!.month,
      _earliestDate!.day,
    );
    // Can go back if previous month would still be >= earliest date
    return !prevMonth.isBefore(earliestDateOnly);
  }

  void _goToPreviousDay() {
    if (!_canGoBack) return;
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
      _hasInitialized = false;
    });
    _fetchHistoryForDate();
  }

  void _goToNextDay() {
    final tomorrow = _selectedDate.add(const Duration(days: 1));
    if (tomorrow.isAfter(DateTime.now())) return; // Don't go to future
    setState(() {
      _selectedDate = tomorrow;
      _hasInitialized = false;
    });
    _fetchHistoryForDate();
  }

  void _goToPreviousMonth() {
    if (!_canGoBackMonth) return;
    setState(() {
      _selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month - 1,
        _selectedDate.day,
      );
      _hasInitialized = false;
    });
    _fetchHistoryForDate();
  }

  void _goToNextMonth() {
    final nextMonth = DateTime(
      _selectedDate.year,
      _selectedDate.month + 1,
      _selectedDate.day,
    );
    if (nextMonth.isAfter(DateTime.now())) return; // Don't go to future
    setState(() {
      _selectedDate = nextMonth;
      _hasInitialized = false;
    });
    _fetchHistoryForDate();
  }

  void _resetView() {
    if (!mounted) return;
    final RenderBox? box =
        _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return;

    final double chartDrawingWidth = box.size.width - leftReservedSize - 20;
    double scaleX = totalMinutesInDay / visibleWindowMinutes;

    // For historical data, start at 6:00 AM
    const double startMinutes = 6 * 60;

    double totalZoomedWidth = chartDrawingWidth * scaleX;
    double pixelPos = (startMinutes / totalMinutesInDay) * totalZoomedWidth;

    double scrollOffset = pixelPos - (chartDrawingWidth * 0.1);
    double maxScroll = totalZoomedWidth - chartDrawingWidth;
    scrollOffset = scrollOffset.clamp(0.0, maxScroll);

    setState(() {
      _transformationController.value = Matrix4.identity()
        ..scaleByDouble(scaleX, 1.0, 1.0, 1.0)
        ..translateByDouble(-scrollOffset / scaleX, 0.0, 0.0, 1.0);
      _hasInitialized = true;
    });
  }

  Future<void> _fetchHistoryForDate() async {
    if (!mounted) return;
    final p = context.read<ThemeProvider>();
    if (_isFetching) return;
    if (!p.useDirectUrl && p.rustIp.isEmpty) return;
    if (p.useDirectUrl && p.directHttpUrl.isEmpty) return;

    setState(() => _isFetching = true);

    try {
      final dateStr = _dateFormatter.format(_selectedDate);
      final url = "${p.httpUrl}/history/$dateStr";
      debugPrint("Fetching history from: $url");
      final res = await http.get(Uri.parse(url));

      debugPrint(
        "Response status: ${res.statusCode}, body length: ${res.body.length}",
      );

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        // Handle both direct HistoryFile and wrapped response
        final Map<String, dynamic> json = decoded is Map<String, dynamic>
            ? decoded
            : {};
        final List<dynamic> data = json['data'] ?? [];
        final Map<String, dynamic> qedData = json['qed'] != null
            ? Map<String, dynamic>.from(json['qed'])
            : {};

        debugPrint(
          "Parsed data points: ${data.length}, QED entries: ${qedData.length}",
        );

        final List<FlSpot> tLoad = [];
        final List<FlSpot> tPv = [];
        final Map<double, String> tLabels = {};

        for (var pt in data) {
          final String timeStr = pt['time'] ?? "00:00:00";
          final parts = timeStr.split(':');
          final int hours = int.tryParse(parts[0]) ?? 0;
          final int minutes =
              int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
          final int seconds =
              int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0;

          double x = hours * 60 + minutes + (seconds / 60.0);

          tLoad.add(FlSpot(x, (pt['load'] as num).toDouble()));
          tPv.add(FlSpot(x, (pt['pv'] as num).toDouble()));
          tLabels[x] = timeStr;
        }

        tLoad.sort((a, b) => a.x.compareTo(b.x));
        tPv.sort((a, b) => a.x.compareTo(b.x));

        // Parse QED data
        Map<String, double> qedMap = {};
        double totalQed = 0;
        qedData.forEach((serial, value) {
          double qedVal = (value as num).toDouble();
          qedMap[serial] = qedVal;
          totalQed += qedVal;
        });

        if (mounted) {
          setState(() {
            _loadSpots.clear();
            _pvSpots.clear();
            _timeLabels.clear();
            _loadSpots.addAll(tLoad);
            _pvSpots.addAll(tPv);
            _timeLabels.addAll(tLabels);
            _qedPerInverter = qedMap;
            _totalQed = totalQed;
          });

          WidgetsBinding.instance.addPostFrameCallback((_) => _resetView());
        }
      } else if (res.statusCode == 404) {
        // No data for this date
        if (mounted) {
          setState(() {
            _loadSpots.clear();
            _pvSpots.clear();
            _timeLabels.clear();
            _qedPerInverter = {};
            _totalQed = 0;
          });
        }
      }
    } catch (e) {
      debugPrint("History Fetch Error: $e");
    }

    if (mounted) setState(() => _isFetching = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>();
    final color = p.seedColor;
    final isToday =
        _dateFormatter.format(_selectedDate) ==
        _dateFormatter.format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "History",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Date navigation bar
            _buildDateNavigator(color, isToday),
            const SizedBox(height: 12),
            // QED Stats
            _buildQedStats(color),
            const SizedBox(height: 12),
            // Toggles
            _buildToggles(color),
            const SizedBox(height: 8),
            // Chart
            Expanded(
              child: _isFetching
                  ? const Center(child: CircularProgressIndicator())
                  : _loadSpots.isEmpty && _pvSpots.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 64,
                            color: Colors.grey.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "No data for ${_dateFormatter.format(_selectedDate)}",
                            style: TextStyle(
                              color: Colors.grey.withValues(alpha: 0.7),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        if (!_hasInitialized && constraints.maxWidth > 0) {
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _resetView(),
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
                              transformationController:
                                  _transformationController,
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

  Widget _buildDateNavigator(Color color, bool isToday) {
    final disabledColor = Colors.grey.withValues(alpha: 0.4);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Double left arrow (previous month)
          IconButton(
            onPressed: _canGoBackMonth ? _goToPreviousMonth : null,
            icon: Icon(
              Icons.keyboard_double_arrow_left_rounded,
              color: _canGoBackMonth ? color : disabledColor,
            ),
            tooltip: "Previous Month",
          ),
          // Single left arrow (previous day)
          IconButton(
            onPressed: _canGoBack ? _goToPreviousDay : null,
            icon: Icon(
              Icons.chevron_left_rounded,
              color: _canGoBack ? color : disabledColor,
              size: 28,
            ),
            tooltip: "Previous Day",
          ),
          // Date display
          Expanded(
            child: GestureDetector(
              onTap: () => _selectDate(context),
              child: Text(
                _dateFormatter.format(_selectedDate),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ),
          // Single right arrow (next day)
          IconButton(
            onPressed: isToday ? null : _goToNextDay,
            icon: Icon(
              Icons.chevron_right_rounded,
              color: isToday ? disabledColor : color,
              size: 28,
            ),
            tooltip: "Next Day",
          ),
          // Double right arrow (next month)
          IconButton(
            onPressed: isToday ? null : _goToNextMonth,
            icon: Icon(
              Icons.keyboard_double_arrow_right_rounded,
              color: isToday ? disabledColor : color,
            ),
            tooltip: "Next Month",
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: _earliestDate ?? DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _hasInitialized = false;
      });
      _fetchHistoryForDate();
    }
  }

  Widget _buildQedStats(Color color) {
    final entries = _qedPerInverter.entries.toList();

    return Row(
      children: [
        // Per-inverter tiles
        ...entries.map((e) {
          return Expanded(
            child: _qedTile(
              e.key,
              "${e.value.toStringAsFixed(2)} kWh",
              Icons.bolt_rounded,
              Colors.yellow[700]!,
            ),
          );
        }),
        if (entries.isNotEmpty) const SizedBox(width: 8),
        // Total tile
        Expanded(
          child: _qedTile(
            "Total",
            "${_totalQed.toStringAsFixed(2)} kWh",
            Icons.calendar_today_rounded,
            Colors.yellow[700]!,
          ),
        ),
      ],
    );
  }

  Widget _qedTile(String label, String value, IconData icon, Color col) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: col, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: col.withValues(alpha: 0.7),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: col,
                ),
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

              String timeDisplay;
              if (_timeLabels.containsKey(touchedSpot.x)) {
                timeDisplay = _timeLabels[touchedSpot.x]!;
              } else {
                final int totalMinutes = touchedSpot.x.toInt();
                final int seconds = ((touchedSpot.x - totalMinutes) * 60)
                    .round();
                final String hour = (totalMinutes ~/ 60).toString().padLeft(
                  2,
                  '0',
                );
                final String min = (totalMinutes % 60).toString().padLeft(
                  2,
                  '0',
                );
                final String sec = seconds.toString().padLeft(2, '0');
                timeDisplay = '$hour:$min:$sec';
              }

              return LineTooltipItem(
                '$timeDisplay\n',
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
}

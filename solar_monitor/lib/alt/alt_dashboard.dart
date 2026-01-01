import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:intl/intl.dart';
import '../extras/theme_provider.dart';

class AltDashboard extends StatefulWidget {
  const AltDashboard({super.key});

  @override
  State<AltDashboard> createState() => _AltDashboardState();
}

class _AltDashboardState extends State<AltDashboard> {
  WebSocketChannel? _channel;
  Stream? _broadcastStream;
  bool _isDisposed = false;

  final _f = NumberFormat("#,##0", "en_US");
  final _d = NumberFormat("#,##0.0", "en_US");

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed) _connect();
    });
  }

  void _cleanup() {
    _channel?.sink.close();
    _channel = null;
    _broadcastStream = null;
  }

  void _connect() {
    if (!mounted || _isDisposed) return;
    try {
      final p = Provider.of<ThemeProvider>(context, listen: false);
      if (p.rustIp.isEmpty) return;
      _cleanup();
      _channel = WebSocketChannel.connect(Uri.parse(p.wsUrl));
      if (mounted && !_isDisposed) {
        setState(() {
          _broadcastStream = _channel!.stream.asBroadcastStream();
        });
      }
    } catch (e) {
      debugPrint("Connection error: $e");
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cleanup();
    super.dispose();
  }

  double _parse(dynamic val) {
    if (val == null) return 0.0;
    String s = val.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(s) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>();
    final color = p.seedColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "System Overview",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: "Refresh Connection",
            onPressed: _connect,
          ),
        ],
      ),
      body: StreamBuilder(
        stream: _broadcastStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return _buildErrorState();
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          try {
            final Map<String, dynamic> unitsMap = jsonDecode(
              snapshot.data.toString(),
            );

            double totalPV = 0;
            double totalLoad = 0;
            double totalQedRaw = 0;
            double totalChg = 0;
            double totalDischg = 0;
            double sumBattV = 0;
            int unitCount = 0;

            unitsMap.forEach((k, v) {
              final raw = v['raw_data'] ?? [];
              if (raw.length >= 29) {
                unitCount++;
                totalPV +=
                    (_parse(raw[14]) * _parse(raw[25])) +
                    (_parse(raw[27]) * _parse(raw[28]));
                totalLoad += _parse(raw[9]);
                totalChg += _parse(raw[12]);
                totalDischg += _parse(raw.length > 31 ? raw[31] : raw[26]);
                sumBattV += _parse(raw[11]);
              }
              totalQedRaw += _parse(v['qed']);
            });

            double netPowerW = totalPV - totalLoad;
            double avgBattV = unitCount > 0 ? sumBattV / unitCount : 0.0;
            double netBattA = totalChg - totalDischg;
            double totalTodayKwh = totalQedRaw > 100
                ? totalQedRaw / 1000.0
                : totalQedRaw;

            String powerLabel =
                "${netPowerW >= 0 ? '+' : '-'}${_f.format(netPowerW.abs())}W";
            String battLabel =
                "${_d.format(avgBattV)}V, ${netBattA >= 0 ? '+' : '-'}${_d.format(netBattA.abs())}A";

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(
                  children: [
                    _miniStat(
                      "Solar",
                      "${_f.format(totalPV)}W",
                      Icons.wb_sunny_rounded,
                      Colors.green,
                    ),
                    const SizedBox(width: 8),
                    _miniStat(
                      "Load",
                      "${_f.format(totalLoad)}W",
                      Icons.bolt_rounded,
                      color,
                    ),
                    const SizedBox(width: 8),
                    _miniStat(
                      "Today",
                      "${totalTodayKwh.toStringAsFixed(2)}kWh",
                      Icons.calendar_today_rounded,
                      Colors.yellow[700]!,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _miniStat(
                      netPowerW >= 0 ? "Feeding" : "Drawing",
                      powerLabel,
                      netPowerW >= 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      netPowerW >= 0 ? Colors.cyan : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    _miniStat(
                      netBattA >= 0 ? "Charging" : "Discharging",
                      battLabel,
                      netBattA >= 0
                          ? Icons.battery_charging_full_rounded
                          : Icons.battery_alert_rounded,
                      netBattA >= 0 ? Colors.teal : Colors.deepOrange,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: unitsMap.entries.map((entry) {
                    return SizedBox(
                      width: MediaQuery.of(context).size.width > 600
                          ? (MediaQuery.of(context).size.width / 2) - 18
                          : double.infinity,
                      child: _buildDetailedUnitCard(entry.key, entry.value, p),
                    );
                  }).toList(),
                ),
              ],
            );
          } catch (e) {
            return Center(child: Text("Parse Error: $e"));
          }
        },
      ),
    );
  }

  Widget _buildDetailedUnitCard(
    String id,
    Map<String, dynamic> inv,
    ThemeProvider p,
  ) {
    final List<dynamic> raw = inv['raw_data'] ?? [];
    if (raw.length < 29) return const SizedBox.shrink();

    final String sn = raw[1].toString();
    final double loadW = _parse(raw[9]);
    final double loadPct = _parse(raw[10]);
    final double battV = _parse(raw[11]);
    final double battCap = _parse(raw[13]);
    final double chgA = _parse(raw[12]);
    final double dischgA = _parse(raw.length > 31 ? raw[31] : raw[26]);
    final double pv1V = _parse(raw[14]);
    final double pv1W = pv1V * _parse(raw[25]);
    final double pv2V = _parse(raw[27]);
    final double pv2W = pv2V * _parse(raw[28]);
    final String qedValue = inv['qed']?.toString() ?? "0";

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.seedColor.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Unit #$id",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    Text(
                      "SN: $sn",
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    "ONLINE",
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _detailedSection(
            "Battery Status",
            Icons.battery_charging_full_rounded,
            p.seedColor,
            [
              _row(
                "Voltage / Capacity",
                "${_d.format(battV)}V / ${battCap.toInt()}%",
              ),
              _row(
                "Charging Current",
                "${_d.format(chgA)}A",
                color: Colors.green,
              ),
              _row(
                "Discharge Current",
                "${_d.format(dischgA)}A",
                color: Colors.orange,
              ),
            ],
          ),
          _detailedSection(
            "Solar Status",
            Icons.wb_sunny_rounded,
            Colors.orange,
            [
              _row("PV1", "${pv1V.toInt()}V / ${_f.format(pv1W)}W"),
              _row("PV2", "${pv2V.toInt()}V / ${_f.format(pv2W)}W"),
              _row(
                "Total Solar",
                "${_f.format(pv1W + pv2W)} W",
                color: Colors.orange,
              ),
              _row("Today Energy", "$qedValue kWh", color: p.seedColor),
            ],
          ),
          _detailedSection(
            "AC Output",
            Icons.electrical_services_rounded,
            Colors.blue,
            [
              _row("Output", "${raw[6]}V / ${raw[7]}Hz"),
              _row("Load", "${_f.format(loadW)}W / ${loadPct.toInt()}%"),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _detailedSection(
    String title,
    IconData icon,
    Color color,
    List<Widget> rows,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const Divider(height: 14),
          ...rows,
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _row(String l, String v, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(l, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        Text(
          v,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 14,
          ),
        ),
      ],
    ),
  );

  Widget _miniStat(String label, String val, IconData icon, Color col) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: col.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: col, size: 24),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                val,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: col,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: col.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          const Text("Connection Failed", style: TextStyle(fontSize: 16)),
          TextButton(
            onPressed: _connect,
            child: const Text("Retry", style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

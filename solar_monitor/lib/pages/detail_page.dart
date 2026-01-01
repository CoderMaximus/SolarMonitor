import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:intl/intl.dart';
import '../extras/theme_provider.dart';

class InverterDetailPage extends StatefulWidget {
  final int inverterId;
  final dynamic initialData;

  const InverterDetailPage({
    super.key,
    required this.inverterId,
    this.initialData,
  });

  @override
  State<InverterDetailPage> createState() => _InverterDetailPageState();
}

class _InverterDetailPageState extends State<InverterDetailPage>
    with SingleTickerProviderStateMixin {
  late Stream<dynamic> _unitStream;
  AnimationController? _bubbleController;
  WebSocketChannel? _channel;

  final _f = NumberFormat("#,##0", "en_US");

  @override
  void initState() {
    super.initState();
    _bubbleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    final p = context.read<ThemeProvider>();
    _channel = WebSocketChannel.connect(Uri.parse(p.wsUrl));

    _unitStream = _channel!.stream.map((event) {
      final Map<String, dynamic> allUnits = jsonDecode(event);
      return allUnits[widget.inverterId.toString()];
    }).asBroadcastStream();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _bubbleController?.dispose();
    super.dispose();
  }

  double _parse(dynamic val) {
    if (val == null) return 0.0;
    String s = val.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(s) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(title: Text("Unit ${widget.inverterId} Details")),
      body: StreamBuilder<dynamic>(
        stream: _unitStream,
        initialData: widget.initialData,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final inv = snapshot.data;
          final List<dynamic> raw = inv['raw_data'];

          final String sn = raw[1].toString();
          final double loadW = _parse(raw[9]);
          final double loadPct = _parse(raw[10]);
          final double battV = _parse(raw[11]);
          final double battCap = _parse(raw[13]);
          final double chgA = _parse(raw[12]);
          final double dischgA = _parse(raw[26]);

          final double pv1V = _parse(raw[14]);
          final double pv1A = _parse(raw[25]);
          final double pv1W = pv1V * pv1A;

          final double pv2V = raw.length > 27 ? _parse(raw[27]) : 0.0;
          final double pv2A = raw.length > 28 ? _parse(raw[28]) : 0.0;
          final double pv2W = pv2V * pv2A;

          final String qedValue = inv['qed']?.toString() ?? "0.00";

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    height: 220,
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    child: _buildFlowContent(
                      raw,
                      pv1W + pv2W,
                      loadW,
                      battV,
                      battCap.toInt(),
                      chgA,
                      dischgA,
                      theme,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _infoCard(
                      "Battery Status",
                      Icons.battery_charging_full_rounded,
                      [
                        _row("Battery Voltage", "$battV V"),
                        _row("Capacity", "${battCap.toInt()}%"),
                        _row(
                          "Charging Current",
                          "$chgA A",
                          color: Colors.green,
                        ),
                        _row(
                          "Discharge Current",
                          "$dischgA A",
                          color: Colors.orange,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _infoCard("Solar Status", Icons.wb_sunny_rounded, [
                      _row(
                        "PV1 Status",
                        "${pv1V.toInt()}V / ${_f.format(pv1W)}W",
                      ),
                      _row(
                        "PV2 Status",
                        "${pv2V.toInt()}V / ${_f.format(pv2W)}W",
                      ),
                      _row(
                        "Total Solar Power",
                        "${_f.format(pv1W + pv2W)} W",
                        color: Colors.orange,
                      ),
                      const Divider(),
                      _row("Today Energy", "$qedValue kWh", color: p.seedColor),
                    ]),
                    const SizedBox(height: 10),
                    _infoCard("AC Output", Icons.electrical_services_rounded, [
                      _row("Output Voltage", "${raw[6]} V"),
                      _row("Output Frequency", "${raw[7]} Hz"),
                      _row("Load Power", "${_f.format(loadW)} W"),
                      _row("Load Percent", "${loadPct.toInt()}%"),
                    ]),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          "S/N: $sn",
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFlowContent(
    List raw,
    double pvW,
    double loadW,
    double battV,
    int pct,
    double chg,
    double dischg,
    ThemeData theme,
  ) {
    if (_bubbleController == null) return const SizedBox.shrink();
    final p = context.watch<ThemeProvider>();
    return AnimatedBuilder(
      animation: _bubbleController!,
      builder: (context, _) => CustomPaint(
        painter: SolidFlowPainter(
          progress: _bubbleController!.value,
          hasSolar: pvW > 10,
          hasLoad: loadW > 15,
          isCharging: chg > 0.1,
          isDischarging: dischg > 0.1,
          lineColor: theme.dividerColor.withValues(alpha: 0.1),
          bubbleColor: p.seedColor,
        ),
        child: Stack(
          children: [
            _node(
              10,
              10,
              Icons.grid_view_rounded,
              "Grid",
              "${raw[4]}V",
              opacity: 0.3,
            ),
            _node(
              10,
              null,
              Icons.home_rounded,
              "Load",
              "${_f.format(loadW)}W",
              active: loadW > 15,
              right: 10,
            ),
            _node(
              null,
              10,
              Icons.wb_sunny_rounded,
              "Solar",
              "${_f.format(pvW)}W",
              active: pvW > 10,
              bottom: 10,
            ),
            _node(
              null,
              null,
              Icons.battery_std_rounded,
              "Battery",
              "${battV}V",
              color: pct > 25 ? Colors.green : Colors.red,
              bottom: 10,
              right: 10,
            ),
            const Center(
              child: Icon(Icons.bolt, size: 40, color: Colors.orange),
            ),
          ],
        ),
      ),
    );
  }

  Widget _node(
    double? t,
    double? l,
    IconData icon,
    String label,
    String val, {
    bool active = false,
    double opacity = 1.0,
    double? right,
    double? bottom,
    Color? color,
  }) {
    return Positioned(
      top: t,
      left: l,
      right: right,
      bottom: bottom,
      child: Opacity(
        opacity: opacity,
        child: Column(
          children: [
            Icon(
              icon,
              color: active ? Colors.orange : (color ?? Colors.grey),
              size: 24,
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
            ),
            Text(
              val,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(String t, IconData icon, List<Widget> children) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: context.read<ThemeProvider>().seedColor,
              ),
              const SizedBox(width: 8),
              Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(height: 20),
          ...children,
        ],
      ),
    ),
  );

  Widget _row(String l, String v, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
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
}

class SolidFlowPainter extends CustomPainter {
  final double progress;
  final bool hasSolar, hasLoad, isCharging, isDischarging;
  final Color lineColor, bubbleColor;

  SolidFlowPainter({
    required this.progress,
    required this.hasSolar,
    required this.hasLoad,
    required this.isCharging,
    required this.isDischarging,
    required this.lineColor,
    required this.bubbleColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pLine = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final pBub = Paint()
      ..color = bubbleColor
      ..style = PaintingStyle.fill;
    final center = Offset(size.width / 2, size.height / 2);
    final nodes = {
      'grid': const Offset(40, 40),
      'load': Offset(size.width - 40, 40),
      'solar': Offset(40, size.height - 40),
      'batt': Offset(size.width - 40, size.height - 40),
    };

    nodes.forEach((key, pos) {
      canvas.drawLine(pos, center, pLine);
      Offset? s, e;
      if (key == 'solar' && hasSolar) {
        s = pos;
        e = center;
      } else if (key == 'load' && hasLoad) {
        s = center;
        e = pos;
      } else if (key == 'batt') {
        if (isCharging) {
          s = center;
          e = pos;
        } else if (isDischarging) {
          s = pos;
          e = center;
        }
      }
      if (s != null && e != null) {
        canvas.drawCircle(Offset.lerp(s, e, progress)!, 4, pBub);
      }
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const ch = MethodChannel('taskman/stats');

void main() => runApp(MaterialApp(
    title: 'Task Manager',
    theme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
    home: const Home()));

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  bool pc = false;
  @override
  Widget build(BuildContext c) => Scaffold(
      appBar: AppBar(title: const Text('Task Manager')),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('This phone'), icon: Icon(Icons.smartphone)),
                  ButtonSegment(value: true, label: Text('My PC'), icon: Icon(Icons.computer)),
                ],
                selected: {pc},
                onSelectionChanged: (s) => setState(() => pc = s.first))),
        Expanded(
            child: pc
                ? const Center(child: Text('PC connection coming in the next step'))
                : IndexedStack(index: tab, children: const [Dashboard(), Apps()])),
      ]),
      bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.speed), label: 'Performance'),
            NavigationDestination(icon: Icon(Icons.apps), label: 'Apps'),
          ]));
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  @override
  State<Dashboard> createState() => _DashState();
}

class _DashState extends State<Dashboard> {
  Map<String, dynamic>? s;
  Timer? t;
  int? rx, tx;
  double down = 0, up = 0;
  final cpu = <double>[], ram = <double>[], dn = <double>[];

  @override
  void initState() {
    super.initState();
    poll();
    t = Timer.periodic(const Duration(seconds: 1), (_) => poll());
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  void add(List<double> l, double v) {
    l.add(v);
    if (l.length > 60) l.removeAt(0);
  }

  Future<void> poll() async {
    try {
      final m = await ch.invokeMapMethod<String, dynamic>('stats');
      if (m == null || !mounted) return;
      final r = m['rx'] as int, x = m['tx'] as int;
      if (rx != null && r >= 0) {
        down = (r - rx!) * 8 / 1e6;
        up = (x - tx!) * 8 / 1e6;
      }
      rx = r;
      tx = x;
      add(cpu, math.max(0, m['cpu'] as int).toDouble());
      add(ram, 100 * (1 - m['ramFree'] as num)/ (m['ramTotal'] as num));
      add(dn, down);
      setState(() => s = m);
    } catch (_) {}
  }

  String gb(num b) => (b / 1073741824).toStringAsFixed(1);

  @override
  Widget build(BuildContext c) {
    final m = s;
    if (m == null) return const Center(child: CircularProgressIndicator());
    final double ramUsed = 100 * (1 - (m['ramFree'] as num) / (m['ramTotal'] as num));
    final double diskUsed = 100 * (1 - (m['diskFree'] as num) / (m['diskTotal'] as num));
    final cp = m['cpu'] as int;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Tile('CPU', cp < 0 ? 'N/A' : '$cp%', 'Estimated from core clock speeds',
          cp < 0 ? 0 : cp.toDouble(), cpu, Colors.tealAccent),
      Tile('Memory', '${ramUsed.toStringAsFixed(0)}% used',
          '${gb(m['ramFree'])} GB free of ${gb(m['ramTotal'])} GB', ramUsed, ram, Colors.purpleAccent),
      Tile('Storage', '${diskUsed.toStringAsFixed(0)}% used',
          '${gb(m['diskFree'])} GB free of ${gb(m['diskTotal'])} GB', diskUsed, null, Colors.orangeAccent),
      Tile('Battery', '${m['battery']}%',
          '${m['batteryTemp']} °C · ${m['charging'] ? 'Charging' : 'On battery'}',
          (m['battery'] as int).toDouble(), null, Colors.greenAccent),
      Tile('Network', '↓ ${down.toStringAsFixed(1)} Mbps', '↑ ${up.toStringAsFixed(1)} Mbps',
          null, dn, Colors.lightBlueAccent),
    ]);
  }
}

class Tile extends StatelessWidget {
  final String title, big, sub;
  final double? pct;
  final List<double>? hist;
  final Color color;
  const Tile(this.title, this.big, this.sub, this.pct, this.hist, this.color, {super.key});
  @override
  Widget build(BuildContext c) => Card(
      child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(c).textTheme.labelLarge),
            Text(big, style: Theme.of(c).textTheme.headlineMedium),
            Text(sub, style: Theme.of(c).textTheme.bodySmall),
            if (pct != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(value: pct! / 100, color: color)),
            if (hist != null)
              SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: CustomPaint(painter: Spark(hist!, color, pct != null ? 100 : 0))),
          ])));
}

class Spark extends CustomPainter {
  final List<double> d;
  final Color c;
  final double max;
  Spark(this.d, this.c, this.max);
  @override
  void paint(Canvas cv, Size s) {
    if (d.length < 2) return;
    final mx = max > 0 ? max : math.max(1.0, d.reduce(math.max));
    final p = Path();
    for (var i = 0; i < d.length; i++) {
      final x = s.width * i / (d.length - 1), y = s.height * (1 - d[i] / mx);
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    cv.drawPath(p, Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_) => true;
}

class Apps extends StatefulWidget {
  const Apps({super.key});
  @override
  State<Apps> createState() => _AppsState();
}

class _AppsState extends State<Apps> {
  List<dynamic> list = [];
  @override
  void initState() {
    super.initState();
    ch.invokeListMethod('apps').then((l) {
      if (mounted) setState(() => list = l ?? []);
    });
  }

  @override
  Widget build(BuildContext c) => list.isEmpty
      ? const Center(child: CircularProgressIndicator())
      : ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final a = list[i];
            return ListTile(
                title: Text(a['name']),
                subtitle: Text(a['pkg']),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => ch.invokeMethod('openSettings', {'pkg': a['pkg']}));
          });
}

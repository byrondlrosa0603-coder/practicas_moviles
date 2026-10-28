import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Permite configurar Supabase al compilar la app.
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://isjlakqmnzlfnjnuqepd.supabase.co',
);
const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: '',//vacia porque git no me deja subir con la clave expuesta
);
const deviceName = String.fromEnvironment(
  'DEVICE_NAME',
  defaultValue: 'sensor-demo-01',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Windows usa SQLite por FFI; Android conserva su implementación nativa.
  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  if (supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }
  runApp(const TelemetriaApp());
}

class TelemetriaApp extends StatelessWidget {
  const TelemetriaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AeroSense · Telemetría',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff087e8b),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xfff5f8fa),
          fontFamily: 'Roboto',
        ),
        home: const MonitorPage(),
      );
}

class Reading {
  // Representa una lectura local o remota del sensor.
  const Reading({
    required this.device,
    required this.air,
    required this.humidity,
    required this.rssi,
    required this.temperature,
    required this.ts,
    this.id,
    this.synced = false,
  });

  final int? id;
  final String device;
  final double air;
  final double humidity;
  final int rssi;
  final double temperature;
  final int ts;
  final bool synced;

  Map<String, dynamic> toJson() => {
        'dispositivo': device,
        'air_quality_ppm': air,
        'humidity': humidity,
        'rssi': rssi,
        'temperature': temperature,
        'ts': ts,
      };

  Map<String, Object?> toDb() => {
        'dispositivo': device,
        'air_quality_ppm': air,
        'humidity': humidity,
        'rssi': rssi,
        'temperature': temperature,
        'ts': ts,
        'synced': synced ? 1 : 0,
      };

  factory Reading.fromDb(Map<String, Object?> row) => Reading(
        id: row['local_id'] as int?,
        device: row['dispositivo']! as String,
        air: (row['air_quality_ppm'] as num).toDouble(),
        humidity: (row['humidity'] as num).toDouble(),
        rssi: row['rssi']! as int,
        temperature: (row['temperature'] as num).toDouble(),
        ts: row['ts']! as int,
        synced: row['synced'] == 1,
      );
}

class TelemetryStore {
  Database? _db;
  Database get db => _db!;

  Future<void> open() async {
    // Crea la base local y evita guardar dos veces la misma lectura.
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, 'aerosense_telemetria.db'),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE lecturas (
          local_id INTEGER PRIMARY KEY AUTOINCREMENT,
          dispositivo TEXT NOT NULL,
          air_quality_ppm REAL NOT NULL,
          humidity REAL NOT NULL,
          rssi INTEGER NOT NULL,
          temperature REAL NOT NULL,
          ts INTEGER NOT NULL,
          synced INTEGER NOT NULL DEFAULT 0,
          UNIQUE(dispositivo, ts)
        )
      '''),
    );
  }

  Future<void> save(Reading reading) async => db.insert(
        'lecturas',
        reading.toDb(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  Future<List<Reading>> recent({int limit = 100}) async {
    // Devuelve las lecturas más recientes para el historial.
    final rows = await db.query('lecturas', orderBy: 'ts DESC', limit: limit);
    return rows.map(Reading.fromDb).toList();
  }

  Future<List<Reading>> pending() async {
    // Selecciona lecturas que todavía no llegaron a la nube.
    final rows = await db.query('lecturas', where: 'synced = 0', orderBy: 'ts');
    return rows.map(Reading.fromDb).toList();
  }

  Future<int> pendingCount() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM lecturas WHERE synced = 0')) ?? 0;

  Future<void> markSynced(Reading reading) async => db.update(
        'lecturas',
        {'synced': 1},
        where: 'dispositivo = ? AND ts = ?',
        whereArgs: [reading.device, reading.ts],
      );

  Future<void> mergeRemote(List<dynamic> rows) async {
    // Copia el historial remoto sin reemplazar lecturas locales.
    final batch = db.batch();
    for (final row in rows) {
      batch.insert(
        'lecturas',
        {
          'dispositivo': row['dispositivo'],
          'air_quality_ppm': row['air_quality_ppm'] ?? 0,
          'humidity': row['humidity'] ?? 0,
          'rssi': row['rssi'] ?? 0,
          'temperature': row['temperature'] ?? 0,
          'ts': row['ts'],
          'synced': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }
}

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  final _store = TelemetryStore();
  final _random = Random();
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _networkSub;
  List<Reading> _readings = [];
  Reading? _latest;
  int _pending = 0;
  bool _online = false;
  bool _loading = true;
  bool _syncing = false;
  String? _syncError;

  bool get _configured => supabaseAnonKey.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Abre SQLite, carga el historial y revisa la red al iniciar.
    await _store.open();
    await _refreshLocal();
    final initial = await Connectivity().checkConnectivity();
    _setConnectivity(initial);
    _networkSub = Connectivity().onConnectivityChanged.listen(_setConnectivity);
    if (_online && _configured) await _synchronize();
  }

  void _setConnectivity(List<ConnectivityResult> results) {
    // Al recuperar la red, inicia la sincronización automática.
    final online = results.any((r) => r != ConnectivityResult.none);
    if (!mounted) return;
    setState(() => _online = online);
    if (online && _configured) _synchronize();
  }

  Future<void> _refreshLocal() async {
    final readings = await _store.recent();
    final pending = await _store.pendingCount();
    if (!mounted) return;
    setState(() {
      _readings = readings;
      _latest = readings.isEmpty ? null : readings.first;
      _pending = pending;
      _loading = false;
    });
  }

  Future<void> _synchronize() async {
    // Envía pendientes y luego descarga lecturas recientes.
    if (!_configured || !_online || _syncing) return;
    setState(() { _syncing = true; _syncError = null; });
    try {
      final client = Supabase.instance.client;
      final pending = await _store.pending();
      for (final reading in pending) {
        // Supabase genera el id identity. La tabla compartida con el ESP32 no
        // requiere una restricción adicional sobre dispositivo y timestamp.
        await client.from('telemetria').insert(reading.toJson());
        await _store.markSynced(reading);
      }
      final remote = await client
          .from('telemetria')
          .select('dispositivo,air_quality_ppm,humidity,rssi,temperature,ts')
          .order('ts', ascending: false)
          .limit(100);
      await _store.mergeRemote(remote);
    } catch (error) {
      final detail = error is PostgrestException
          ? 'Código ${error.code ?? 'sin código'}: ${error.message}'
          : error.toString();
      _syncError = 'No se pudo enviar la lectura. Sigue guardada localmente.\n$detail';
      debugPrint('Supabase sync error: $detail');
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
        await _refreshLocal();
      }
    }
  }

  Future<void> _generate() async {
    // Simula una lectura, la guarda primero en SQLite y luego la envía.
    final now = DateTime.now().millisecondsSinceEpoch;
    final reading = Reading(
      device: deviceName,
      air: 280 + _random.nextDouble() * 420,
      humidity: 35 + _random.nextDouble() * 40,
      rssi: -40 - _random.nextInt(50),
      temperature: 19 + _random.nextDouble() * 12,
      ts: now,
    );
    await _store.save(reading);
    await _refreshLocal();
    if (_online && _configured) await _synchronize();
  }

  void _toggleSimulation() {
    // Genera una lectura inicial y continúa cada cinco segundos.
    if (_timer != null) {
      _timer?.cancel();
      setState(() => _timer = null);
    } else {
      _generate();
      setState(() => _timer = Timer.periodic(const Duration(seconds: 5), (_) => _generate()));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _networkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = _timer != null;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.sensors_rounded, color: Color(0xff087e8b)),
          SizedBox(width: 10),
          Text('AeroSense', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        actions: [
          IconButton(tooltip: 'Sincronizar ahora', onPressed: _synchronize, icon: const Icon(Icons.sync)),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _synchronize,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                  children: [
                    _statusBanner(),
                    if (!_configured) _configBanner(),
                    if (_syncError != null) _messageBanner(_syncError!, Colors.red),
                    const SizedBox(height: 22),
                    const Text('Panel de monitoreo', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Dispositivo  ·  $deviceName', style: TextStyle(color: Colors.blueGrey.shade600)),
                    const SizedBox(height: 18),
                    _latestCard(),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _toggleSimulation,
                      icon: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
                      label: Text(running ? 'Detener simulación' : 'Iniciar simulación'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: running ? const Color(0xffb42318) : const Color(0xff087e8b)),
                    ),
                    const SizedBox(height: 9),
                    Center(child: Text(running ? 'Generando una lectura cada 5 segundos' : 'Cada lectura se guarda primero en SQLite', style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12))),
                    const SizedBox(height: 24),
                    Row(children: [
                      const Expanded(child: Text('Historial de lecturas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                      Text('${_readings.length} registros', style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12)),
                    ]),
                    const SizedBox(height: 12),
                    if (_readings.isEmpty)
                      const _EmptyHistory()
                    else
                      ..._readings.map(_readingTile),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _statusBanner() {
    // Resume conexión, sincronización y cantidad pendiente.
    final color = _online ? const Color(0xff16805d) : const Color(0xffad6200);
    final title = _online ? 'Conectado a Internet' : 'Modo sin conexión';
    final subtitle = _syncing ? 'Sincronizando con Supabase…' : _pending > 0 ? '$_pending lecturas pendientes de envío' : 'Datos locales y nube al día';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: .22))),
      child: Row(children: [
        Icon(_online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: color),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color)), Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700))]),),
        if (_syncing) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
    );
  }

  Widget _configBanner() => _messageBanner('Falta configurar la clave pública anon de Supabase. La app funciona y conserva las lecturas localmente.', const Color(0xff185abd));

  Widget _messageBanner(String text, Color color) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12)),
      );

  Widget _latestCard() {
    // Muestra los valores de la lectura más reciente.
    final r = _latest;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xff102d3b), borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Expanded(child: Text('LECTURA MÁS RECIENTE', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w700))), Icon(Icons.sensors, color: runningColor, size: 19)]),
        const SizedBox(height: 16),
        if (r == null)
          const Text('Aún no hay lecturas', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700))
        else ...[
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(r.temperature.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 44, height: 1, fontWeight: FontWeight.w700)), const Padding(padding: EdgeInsets.only(bottom: 5, left: 5), child: Text('°C', style: TextStyle(color: Colors.white70, fontSize: 18))), const Spacer(), Text(_formatTime(r.ts), style: const TextStyle(color: Colors.white70, fontSize: 12))]),
          const SizedBox(height: 18),
          Row(children: [Expanded(child: _metric('Aire', '${r.air.toStringAsFixed(0)} ppm', Icons.air)), Expanded(child: _metric('Humedad', '${r.humidity.toStringAsFixed(1)}%', Icons.water_drop_outlined)), Expanded(child: _metric('Señal', '${r.rssi} dBm', Icons.wifi))]),
        ],
      ]),
    );
  }

  Widget _metric(String label, String value, IconData icon) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, size: 14, color: Colors.white60), const SizedBox(width: 4), Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11))]), const SizedBox(height: 5), Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))]);

  Widget _readingTile(Reading r) => Card(
        // Distingue visualmente lecturas sincronizadas y pendientes.
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 9),
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.blueGrey.withValues(alpha: .12))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xff087e8b).withValues(alpha: .09), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.sensors, color: Color(0xff087e8b), size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${r.temperature.toStringAsFixed(1)} °C  ·  ${r.air.toStringAsFixed(0)} ppm', style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text('${_formatDate(r.ts)}  ·  ${r.humidity.toStringAsFixed(0)}% HR  ·  ${r.rssi} dBm', style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600))])),
            const SizedBox(width: 4),
            Icon(r.synced ? Icons.cloud_done : Icons.schedule, color: r.synced ? const Color(0xff16805d) : const Color(0xffad6200), size: 19),
          ]),
        ),
      );

  String _formatTime(int ts) { final d = DateTime.fromMillisecondsSinceEpoch(ts); return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}'; }
  String _formatDate(int ts) { final d = DateTime.fromMillisecondsSinceEpoch(ts); return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${_formatTime(ts)}'; }
}

const runningColor = Color(0xff46c7b0);

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(children: [Icon(Icons.history, size: 32, color: Colors.blueGrey.shade300), const SizedBox(height: 8), const Text('El historial aparecerá aquí'), const SizedBox(height: 4), Text('Inicia la simulación para generar datos', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade500))]));
}

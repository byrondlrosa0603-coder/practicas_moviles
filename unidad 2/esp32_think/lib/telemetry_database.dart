import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Administra el almacenamiento local de telemetría en SQLite.
class TelemetryDatabase {
  // Evita crear más de una instancia de la base de datos.
  TelemetryDatabase._();

  static final TelemetryDatabase instance = TelemetryDatabase._();
  Future<Database>? _database;

  Future<Database> get database => _database ??= _openDatabase();

  // Abre la base y crea la tabla si aún no existe.
  Future<Database> _openDatabase() async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dbPath = await getDatabasesPath();
    return openDatabase(
      p.join(dbPath, 'esp32_telemetry.db'),
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE telemetry (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          recorded_at TEXT NOT NULL,
          temperature REAL,
          humidity REAL,
          air_quality_ppm REAL,
          rssi REAL
        )
      '''),
    );
  }

  // Guarda una muestra de telemetría.
  Future<void> insert(Map<String, Object?> values) async {
    final db = await database;
    await db.insert('telemetry', values);
  }

  // Devuelve las 100 lecturas más recientes.
  Future<List<Map<String, Object?>>> getRecent() async {
    final db = await database;
    return db.query('telemetry', orderBy: 'id DESC', limit: 100);
  }
}

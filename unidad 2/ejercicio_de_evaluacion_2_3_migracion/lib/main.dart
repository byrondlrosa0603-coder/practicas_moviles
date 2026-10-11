import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Punto de entrada principal
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Configura SQLite FFI únicamente para plataformas de escritorio (Windows/Linux)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const MyApp());
}

// Clase Singleton para administrar la base de datos y sus migraciones
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // Obtiene la instancia activa de la BD
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(1); // Inicia por defecto en versión 1
    return _database!;
  }

  // Inicializa la BD abriendo el archivo en la ruta local del dispositivo
  Future<Database> _initDB(int targetVersion) async {
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, 'sensores_migracion.db');

    return await openDatabase(
      fullPath,
      version: targetVersion,
      onCreate: (db, version) async {
        // Estructura base inicial (Versión 1)
        await db.execute('''
          CREATE TABLE lecturas (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sensorType TEXT NOT NULL,
            value REAL NOT NULL,
            timestamp TEXT NOT NULL
          )
        ''');

        // Si se instala directamente en versión 2 o superior
        if (version >= 2) {
          await db.execute(
            'ALTER TABLE lecturas ADD COLUMN ubicacion_nodo TEXT DEFAULT "Sin asignar";',
          );
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // MIGRACIÓN: v1 -> v2 (Añade la columna sin perder registros)
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE lecturas ADD COLUMN ubicacion_nodo TEXT DEFAULT "Sin asignar";',
          );
        }
      },
    );
  }

  // Retorna la versión actual registrada en la base de datos
  Future<int> getCurrentVersion() async {
    final db = await database;
    return await db.getVersion();
  }

  // Ejecuta la migración a la versión 2 reconectando la base de datos
  Future<bool> upgradeToV2() async {
    final currentV = await getCurrentVersion();
    if (currentV >= 2) return false;

    // Cierra la conexión activa actual
    if (_database != null) {
      await _database!.close();
      _database = null;
    }

    // Reabre la BD solicitando la versión 2 (dispara el callback onUpgrade)
    _database = await _initDB(2);
    return true;
  }

  // Inserta un registro de lectura en la tabla
  Future<int> insertReading(String sensorType, double value, [String? nodo]) async {
    final db = await database;
    final version = await db.getVersion();

    final Map<String, dynamic> row = {
      'sensorType': sensorType,
      'value': value,
      'timestamp': DateTime.now().toString().substring(0, 19),
    };

    if (version >= 2) {
      row['ubicacion_nodo'] = nodo ?? 'Nodo Principal';
    }

    return await db.insert('lecturas', row);
  }

  // Obtiene todos los registros almacenados
  Future<List<Map<String, dynamic>>> getAllReadings() async {
    final db = await database;
    return await db.query('lecturas', orderBy: 'id DESC');
  }

  // Vacía la tabla de registros
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('lecturas');
  }
}

// Widget raíz de la aplicación
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Migración SQLite v1 -> v2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Migración onUpgrade sqflite'),
    );
  }
}

// Pantalla principal con controles para la migración de la BD
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _readings = [];
  int _dbVersion = 1;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  // Refresca la lista de lecturas y la versión de la BD
  Future<void> _refreshData() async {
    final data = await _dbHelper.getAllReadings();
    final version = await _dbHelper.getCurrentVersion();
    setState(() {
      _readings = data;
      _dbVersion = version;
    });
  }

  // Agrega una lectura de prueba
  Future<void> _addSampleReading() async {
    await _dbHelper.insertReading(
      'Temperatura',
      24.5,
      _dbVersion >= 2 ? 'Nodo-Norte' : null,
    );
    _refreshData();
  }

  // Dispara el controlador de la migración a la versión 2
  Future<void> _runMigration() async {
    final success = await _dbHelper.upgradeToV2();
    await _refreshData();

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.teal,
          content: Text('¡Migración exitosa a v2! Columna "ubicacion_nodo" añadida.'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La BD ya se encuentra en la Versión 2.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () async {
              await _dbHelper.clearAll();
              _refreshData();
            },
          )
        ],
      ),
      body: Column(
        children: [
          // Banner con el estado actual de la versión de la base de datos
          Container(
            padding: const EdgeInsets.all(16),
            color: _dbVersion >= 2 ? Colors.teal.shade100 : Colors.amber.shade100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Versión Actual BD: v$_dbVersion',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                ElevatedButton.icon(
                  onPressed: _dbVersion >= 2 ? null : _runMigration,
                  icon: const Icon(Icons.upgrade),
                  label: const Text('Migrar a v2'),
                ),
              ],
            ),
          ),
          
          // Botón para agregar lecturas simuladas
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: ElevatedButton.icon(
              onPressed: _addSampleReading,
              icon: const Icon(Icons.sensors),
              label: const Text('Insertar Lectura de Prueba'),
            ),
          ),
          
          const Divider(),
          
          // Lista desplegable con los registros recuperados
          Expanded(
            child: _readings.isEmpty
                ? const Center(child: Text('No hay lecturas registradas.'))
                : ListView.builder(
                    itemCount: _readings.length,
                    itemBuilder: (context, index) {
                      final item = _readings[index];
                      final hasNodo = item.containsKey('ubicacion_nodo') && item['ubicacion_nodo'] != null;

                      return ListTile(
                        leading: CircleAvatar(child: Text('${item['id']}')),
                        title: Text('${item['sensorType']}: ${item['value']} °C'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Fecha: ${item['timestamp']}'),
                            // Muestra la ubicación ÚNICAMENTE si la BD está en v2 y existe la columna
                            if (_dbVersion >= 2 && hasNodo)
                              Text(
                                'Ubicación: ${item['ubicacion_nodo']}',
                                style: const TextStyle(
                                  color: Colors.teal,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
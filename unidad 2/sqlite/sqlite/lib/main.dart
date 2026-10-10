import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p; 

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Configura SQLite FFI para plataformas de escritorio 
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const MyApp());
}

// Modelo de datos para las lecturas de los sensores
class SensorReading {
  final int? id;
  final String sensorType;
  final double value;
  final String timestamp;

  SensorReading({
    this.id,
    required this.sensorType,
    required this.value,
    required this.timestamp,
  });

  // Convierte el objeto a un Map para insertarlo en SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sensorType': sensorType,
      'value': value,
      'timestamp': timestamp,
    };
  }
}

// Clase Singleton para la administración de la base de datos
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // Obtiene la instancia de la BD o la inicializa si aún no existe
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('iot_local.db');
    return _database!;
  }

  // Inicializa la BD en la ruta local y habilita claves foráneas
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, filePath);

    return await openDatabase(
      fullPath, 
      version: 1,
      onCreate: _createDB,
      onConfigure: (db) async {
        // Habilita el soporte de Foreign Keys en SQLite
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  // Crea la estructura inicial de la tabla
  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sensorType TEXT NOT NULL,
        value REAL NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');
  }

  // OPERACIONES

  // Inserta una nueva lectura en la tabla
  Future<int> insertReading(SensorReading reading) async {
    final db = await instance.database;
    return await db.insert('readings', reading.toMap());
  }

  // Consulta y mapea todas las lecturas ordenadas por ID descendente
  Future<List<SensorReading>> getAllReadings() async {
    final db = await instance.database;
    final result = await db.query('readings', orderBy: 'id DESC');

    return result.map((json) => SensorReading(
      id: json['id'] as int?,
      sensorType: json['sensorType'] as String,
      value: json['value'] as double,
      timestamp: json['timestamp'] as String,
    )).toList();
  }

  // Actualiza los campos de un registro mediante su ID
  Future<int> updateReading(SensorReading reading) async {
    final db = await instance.database;
    return db.update(
      'readings',
      reading.toMap(),
      where: 'id = ?',
      whereArgs: [reading.id],
    );
  }

  // Elimina un registro de la base de datos según su ID
  Future<int> deleteReading(int id) async {
    final db = await instance.database;
    return await db.delete(
      'readings',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Retorna el conteo total de registros almacenados
  Future<int> getCount() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM readings');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}

// UI

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Sensores SQLite CRUD'),
    );
  }
}

// Pantalla principal interactiva
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  List<SensorReading> _readings = [];

  // Controladores de texto para los campos del formulario
  final TextEditingController _typeController = TextEditingController();
  final TextEditingController _valueController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  // Libera la memoria utilizada por los controladores
  @override
  void dispose() {
    _typeController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  // Refresca el conteo total y la lista de registros desde la base de datos
  void _refreshData() async {
    final count = await DatabaseHelper.instance.getCount();
    final data = await DatabaseHelper.instance.getAllReadings();
    setState(() {
      _counter = count;
      _readings = data;
    });
  }

  // Elimina un registro por ID y actualiza la lista en pantalla
  void _deleteReading(int id) async {
    await DatabaseHelper.instance.deleteReading(id);
    _refreshData();
    
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Registro eliminado')),
    );
  }

  // Muestra el cuadro de diálogo para registrar o actualizar una lectura
  void _showFormDialog([SensorReading? existingReading]) {
    final isEditing = existingReading != null;
    
    // Precarga datos en el formulario si se está editando
    if (isEditing) {
      _typeController.text = existingReading.sensorType;
      _valueController.text = existingReading.value.toString();
    } else {
      _typeController.clear();
      _valueController.clear();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Editar Registro' : 'Nuevo Registro'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _typeController,
              decoration: const InputDecoration(labelText: 'Tipo de sensor'),
            ),
            TextField(
              controller: _valueController,
              decoration: const InputDecoration(labelText: 'Valor numérico'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Validaciones previas al guardado
              if (_typeController.text.isEmpty || _valueController.text.isEmpty) {
                return;
              }
              final valueParsed = double.tryParse(_valueController.text);
              if (valueParsed == null) return;

              // Construcción de la lectura con fecha/hora actual si es nuevo
              final reading = SensorReading(
                id: isEditing ? existingReading.id : null,
                sensorType: _typeController.text,
                value: valueParsed,
                timestamp: isEditing ? existingReading.timestamp : DateTime.now().toString().substring(0, 19),
              );

              // Inserta o actualiza dependiendo del caso
              if (isEditing) {
                await DatabaseHelper.instance.updateReading(reading);
              } else {
                await DatabaseHelper.instance.insertReading(reading);
              }

              _refreshData();
              if (!context.mounted) return; 
              Navigator.pop(context);
            },
            child: Text(isEditing ? 'Actualizar' : 'Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          // Header con el conteo total de registros
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Total de registros: $_counter',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const Divider(),
          // Tabla interactiva con scroll horizontal y vertical
          Expanded(
            child: _readings.isEmpty
                ? const Center(child: Text('No hay datos guardados aún.'))
                : SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('ID', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Tipo', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Valor', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Fecha/Hora', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        // Mapea las lecturas recuperadas a filas de la tabla
                        rows: _readings.map((reading) {
                          return DataRow(cells: [
                            DataCell(Text(reading.id.toString())),
                            DataCell(Text(reading.sensorType)),
                            DataCell(Text('${reading.value}')),
                            DataCell(Text(reading.timestamp)),
                            DataCell(
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => _showFormDialog(reading),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteReading(reading.id!),
                                  ),
                                ],
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      // Botón flotante para agregar nuevos registros
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormDialog(),
        tooltip: 'Añadir Lectura',
        child: const Icon(Icons.add),
      ),
    );
  }
}
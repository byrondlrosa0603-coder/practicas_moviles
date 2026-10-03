import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
//import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializar FFI en Windows o Linux
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  runApp(const MyApp());
}

// ==========================================
// 1. GESTOR DE BASE DE DATOS LOCAL (SQLite)
// ==========================================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('productos_acid.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            price REAL NOT NULL
          )
        ''');
      },
    );
  }

  // --- OPERACIONES CRUD ---

  // CREATE: Inserta un registro individual
  Future<int> insertItem(String name, double price) async {
    final db = await database;
    return await db.insert(
      'items',
      {'name': name, 'price': price},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // READ: Obtiene todos los registros
  Future<List<Map<String, dynamic>>> getItems() async {
    final db = await database;
    return await db.query('items', orderBy: 'id DESC');
  }

  // UPDATE: Actualiza un registro existente
  Future<int> updateItem(int id, String name, double price) async {
    final db = await database;
    return await db.update(
      'items',
      {'name': name, 'price': price},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // DELETE: Elimina un registro
  Future<int> deleteItem(int id) async {
    final db = await database;
    return await db.delete(
      'items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- TRANSACCIÓN ACID POR LOTE (BATCH) ---
  // Inserción masiva optimizada: Atomicidad y Durabilidad garantizadas
  Future<int> insertBatch(List<Map<String, dynamic>> itemsList) async {
    final db = await database;

    // db.transaction garantiza Atomicidad (todo o nada) y Aislamiento.
    // batch() compila las operaciones en un solo viaje al motor de SQLite.
    return await db.transaction<int>((txn) async {
      final batch = txn.batch();

      for (var item in itemsList) {
        batch.insert('items', item);
      }

      // commit ejecuta todas las sentencias en un único paso de I/O.
      // noResult: true ahorra memoria al procesar miles de registros.
      final results = await batch.commit(noResult: false);
      return results.length;
    });
  }

  // Limpieza total (útil para pruebas)
  Future<int> clearAll() async {
    final db = await database;
    return await db.delete('items');
  }
}

// ==========================================
// 2. INTERFAZ DE USUARIO (FLUTTER)
// ==========================================
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CRUD y ACID SQLite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'CRUD & Transacciones ACID'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshItems();
  }

  // READ (Actualiza la vista)
  Future<void> _refreshItems() async {
    setState(() => _isLoading = true);
    final data = await _dbHelper.getItems();
    setState(() {
      _items = data;
      _isLoading = false;
    });
  }

  // CREATE / UPDATE DIALOG
  void _showFormDialog({int? id, String? currentName, double? currentPrice}) {
    final nameController = TextEditingController(text: currentName ?? '');
    final priceController =
        TextEditingController(text: currentPrice?.toString() ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(id == null ? 'Nuevo Registro' : 'Editar Registro'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(labelText: 'Precio'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final price = double.tryParse(priceController.text) ?? 0.0;

              if (name.isEmpty) return;

              if (id == null) {
                // CREATE
                await _dbHelper.insertItem(name, price);
              } else {
                // UPDATE
                await _dbHelper.updateItem(id, name, price);
              }

              if (mounted) Navigator.pop(context);
              _refreshItems();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  // DELETE
  Future<void> _deleteItem(int id) async {
    await _dbHelper.deleteItem(id);
    _refreshItems();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro eliminado exitosamente')),
      );
    }
  }

  // INSERCIÓN MASIVA OPTIMIZADA (Batch + Transaction)
  Future<void> _runMassiveBatchInsert() async {
    setState(() => _isLoading = true);

    final stopwatch = Stopwatch()..start();

    // 1. Preparamos 1,000 registros en memoria
    final List<Map<String, dynamic>> massiveData = List.generate(
      1000,
      (index) => {
        'name': 'Producto Lote #${index + 1}',
        'price': (index + 1) * 1.5,
      },
    );

    // 2. Ejecución dentro del bloque transaccional
    final count = await _dbHelper.insertBatch(massiveData);
    stopwatch.stop();

    await _refreshItems();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade800,
          content: Text(
            '¡Éxito ACID! Se insertaron $count registros en ${stopwatch.elapsedMilliseconds} ms sin congelar la UI.',
          ),
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
            tooltip: 'Borrar toda la base de datos',
            icon: const Icon(Icons.delete_sweep),
            onPressed: () async {
              await _dbHelper.clearAll();
              _refreshItems();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Panel de control transaccional
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total registros: ${_items.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.bolt),
                        label: const Text('Insertar 1,000 (Batch ACID)'),
                        onPressed: _runMassiveBatchInsert,
                      ),
                    ],
                  ),
                ),
                // Lista de elementos (CRUD Read/Update/Delete)
                Expanded(
                  child: _items.isEmpty
                      ? const Center(child: Text('No hay registros guardados.'))
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text('${item['id']}'),
                              ),
                              title: Text(item['name']),
                              subtitle: Text(
                                '\$${(item['price'] as num).toStringAsFixed(2)}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => _showFormDialog(
                                      id: item['id'],
                                      currentName: item['name'],
                                      currentPrice: (item['price'] as num).toDouble(),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteItem(item['id']),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormDialog(),
        tooltip: 'Crear Registro',
        child: const Icon(Icons.add),
      ),
    );
  }
}

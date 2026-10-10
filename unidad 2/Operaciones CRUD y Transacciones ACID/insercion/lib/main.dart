import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // para que funcione en Windows
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const MyApp());
}


//  sqlite
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('productos_acid.db', targetVersion: 1);
    return _database!;
  }

  Future<Database> _initDB(String filePath, {int targetVersion = 1}) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: targetVersion,
      onCreate: (db, version) async {
        // Esquema base: Versión 1
        await db.execute('''
          CREATE TABLE items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            price REAL NOT NULL
          )
        ''');

        // Si se crea directamente en versión 2 o superior
        if (version >= 2) {
          await db.execute('ALTER TABLE items ADD COLUMN ubicacion_nodo TEXT;');
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // MIGRACIÓN MÓDULO 2: v1 -> v2
        // Agrega la columna ubicacion_nodo sin perder ningún registro previo
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE items ADD COLUMN ubicacion_nodo TEXT DEFAULT "Sin asignar";',
          );
        }
      },
    );
  }

  
  Future<int> getCurrentVersion() async {
    final db = await database;
    return await db.getVersion();
  }

  // Disparador de la migración a v2
  Future<bool> upgradeToV2() async {
    final currentV = await getCurrentVersion();
    if (currentV >= 2) {
      return false; 
    }

    
    if (_database != null) {
      await _database!.close();
      _database = null;
    }

   
    _database = await _initDB('productos_acid.db', targetVersion: 2);
    return true;
  }

  // --- OPERACIONES CRUD ---

  // CREATE
  Future<int> insertItem(String name, double price, [String? ubicacionNodo]) async {
    final db = await database;
    final Map<String, dynamic> row = {
      'name': name,
      'price': price,
    };

    final currentVersion = await db.getVersion();
    if (currentVersion >= 2 && ubicacionNodo != null) {
      row['ubicacion_nodo'] = ubicacionNodo;
    }

    return await db.insert(
      'items',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // READ
  Future<List<Map<String, dynamic>>> getItems() async {
    final db = await database;
    return await db.query('items', orderBy: 'id DESC');
  }

  // UPDATE
  Future<int> updateItem(int id, String name, double price, [String? ubicacionNodo]) async {
    final db = await database;
    final Map<String, dynamic> row = {
      'name': name,
      'price': price,
    };

    final currentVersion = await db.getVersion();
    if (currentVersion >= 2 && ubicacionNodo != null) {
      row['ubicacion_nodo'] = ubicacionNodo;
    }

    return await db.update(
      'items',
      row,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // DELETE
  Future<int> deleteItem(int id) async {
    final db = await database;
    return await db.delete(
      'items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- TRANSACCIÓN ACID POR LOTE (BATCH) ---
  Future<int> insertBatch(List<Map<String, dynamic>> itemsList) async {
    final db = await database;

    return await db.transaction<int>((txn) async {
      final batch = txn.batch();
      for (var item in itemsList) {
        batch.insert('items', item);
      }
      final results = await batch.commit(noResult: false);
      return results.length;
    });
  }

  // Limpieza total
  Future<int> clearAll() async {
    final db = await database;
    return await db.delete('items');
  }
}


// INTERFAZ 

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
      home: const MyHomePage(title: 'CRUD, ACID & Migración v2'),
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
  int _dbVersion = 1;

  @override
  void initState() {
    super.initState();
    _refreshItems();
  }

  Future<void> _refreshItems() async {
    setState(() => _isLoading = true);
    final data = await _dbHelper.getItems();
    final v = await _dbHelper.getCurrentVersion();
    setState(() {
      _items = data;
      _dbVersion = v;
      _isLoading = false;
    });
  }

  // ACCIÓN DEL BOTÓN: Migración a v2
  Future<void> _handleMigration() async {
    setState(() => _isLoading = true);
    final success = await _dbHelper.upgradeToV2();
    await _refreshItems();

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.teal,
          content: Text(
            '¡Migración exitosa a v2! Se añadió la columna "ubicacion_nodo" sin perder registros.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La base de datos ya se encuentra en la versión 2.'),
        ),
      );
    }
  }

  
  void _showFormDialog({
    int? id,
    String? currentName,
    double? currentPrice,
    String? currentNodo,
  }) {
    final nameController = TextEditingController(text: currentName ?? '');
    final priceController = TextEditingController(text: currentPrice?.toString() ?? '');
    final nodoController = TextEditingController(text: currentNodo ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(id == null ? 'Nuevo Registro' : 'Editar Registro'),
        content: SingleChildScrollView(
          child: Column(
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
              if (_dbVersion >= 2) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: nodoController,
                  decoration: const InputDecoration(
                    labelText: 'Ubicación Nodo (v2)',
                    hintText: 'Ej. Nodo-A1 / Almacén Central',
                    prefixIcon: Icon(Icons.hub_outlined),
                  ),
                ),
              ],
            ],
          ),
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
              final nodo = nodoController.text.trim();

              if (name.isEmpty) return;

              if (id == null) {
                await _dbHelper.insertItem(
                  name,
                  price,
                  _dbVersion >= 2 ? (nodo.isEmpty ? 'Sin asignar' : nodo) : null,
                );
              } else {
                await _dbHelper.updateItem(
                  id,
                  name,
                  price,
                  _dbVersion >= 2 ? nodo : null,
                );
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

  Future<void> _deleteItem(int id) async {
    await _dbHelper.deleteItem(id);
    _refreshItems();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro eliminado exitosamente')),
      );
    }
  }

  Future<void> _runMassiveBatchInsert() async {
    setState(() => _isLoading = true);
    final stopwatch = Stopwatch()..start();

    final List<Map<String, dynamic>> massiveData = List.generate(
      1000,
      (index) {
        final map = <String, dynamic>{
          'name': 'Producto Lote #${index + 1}',
          'price': (index + 1) * 1.5,
        };
        if (_dbVersion >= 2) {
          map['ubicacion_nodo'] = 'Nodo-${(index % 5) + 1}';
        }
        return map;
      },
    );

    final count = await _dbHelper.insertBatch(massiveData);
    stopwatch.stop();

    await _refreshItems();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade800,
          content: Text(
            '¡Éxito ACID! $count registros insertados en ${stopwatch.elapsedMilliseconds} ms.',
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
                // Barra de Estado de Versión y Control de Migración
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: _dbVersion >= 2 ? Colors.teal.shade50 : Colors.amber.shade50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _dbVersion >= 2 ? Icons.check_circle : Icons.warning_amber,
                            color: _dbVersion >= 2 ? Colors.teal : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Versión BD: v$_dbVersion ${_dbVersion >= 2 ? "(Migrada con ubicacion_nodo)" : "(Original)"}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _dbVersion >= 2 ? Colors.teal.shade900 : Colors.brown,
                            ),
                          ),
                        ],
                      ),
                      // BOTÓN DE MIGRACIÓN DE ESQUEMA
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _dbVersion >= 2 ? Colors.grey.shade400 : Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.upgrade),
                        label: const Text('Migrar a v2'),
                        onPressed: _dbVersion >= 2 ? null : _handleMigration,
                      ),
                    ],
                  ),
                ),

                // Panel de control Batch ACID
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

                // Lista de elementos
                Expanded(
                  child: _items.isEmpty
                      ? const Center(child: Text('No hay registros guardados.'))
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final hasNodo = item.containsKey('ubicacion_nodo') && item['ubicacion_nodo'] != null;

                            return ListTile(
                              leading: CircleAvatar(
                                child: Text('${item['id']}'),
                              ),
                              title: Text(item['name']),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('\$${(item['price'] as num).toStringAsFixed(2)}'),
                                  if (hasNodo)
                                    Text(
                                      'Ubicación: ${item['ubicacion_nodo']}',
                                      style: TextStyle(
                                        color: Colors.teal.shade700,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
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
                                      currentNodo: item['ubicacion_nodo'] as String?,
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
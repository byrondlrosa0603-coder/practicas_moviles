import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as native;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Store {
  final Database db;
  Store(this.db);
  static Future<void> createSchema(Database db, int version) async {
    await db.execute(
      'CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL COLLATE NOCASE UNIQUE, password TEXT NOT NULL, age INTEGER NOT NULL, fingerprint INTEGER UNIQUE, fingerprint_template BLOB)',
    );
    await db.execute(
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  static Future<void> migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE users ADD COLUMN fingerprint_template BLOB',
      );
    }
  }

  static Future<Store> open() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    } else {
      databaseFactory = native.databaseFactorySqflitePlugin;
    }
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return Store(
      await openDatabase(
        p.join(directory.path, 'usuarios.db'),
        version: 2,
        onCreate: createSchema,
        onUpgrade: migrate,
      ),
    );
  }

  Future<List<Map<String, Object?>>> users() =>
      db.query('users', orderBy: 'name COLLATE NOCASE');
  Future<String> address() async {
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['address'],
    );
    return rows.isEmpty
        ? 'http://192.168.1.100'
        : rows.first['value'] as String;
  }

  Future<void> setAddress(String value) async {
    await db.insert('settings', {
      'key': 'address',
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

class Reader {
  final String address;
  Reader(this.address);
  Future<Map<String, dynamic>> call(String route, {Uint8List? template}) async {
    final base = Uri.parse(address);
    final uri = base.replace(path: route);
    final response = route == '/status'
        ? await http.get(uri).timeout(const Duration(seconds: 5))
        : await http
              .post(
                uri,
                body: template == null
                    ? null
                    : {'template': encodeTemplate(template)},
              )
              .timeout(const Duration(seconds: 65));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['message'] ?? 'Error del lector');
    }
    if (route == '/status' && data['protocol'] != 2) {
      throw Exception(
        'Actualiza el firmware del ESP32 para usar plantillas en SQLite.',
      );
    }
    return data;
  }
}

String encodeTemplate(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
Uint8List decodeTemplate(Object? value) {
  if (value is! String ||
      value.length < 512 ||
      value.length > 4096 ||
      value.length % 64 != 0 ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
    throw const FormatException(
      'Plantilla AS608 invalida: entre 256 y 2048 bytes, en bloques de 32.',
    );
  }
  return Uint8List.fromList(
    List.generate(
      value.length ~/ 2,
      (i) => int.parse(value.substring(i * 2, i * 2 + 2), radix: 16),
    ),
  );
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final template = Uint8List.fromList(List.generate(768, (i) => i % 256));
  test('La plantilla completa persiste tras cerrar y reabrir SQLite', () async {
    final directory = await Directory.systemTemp.createTemp('lector_test_');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/test.db';
    var db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 2, onCreate: Store.createSchema),
    );
    final id = await db.insert('users', {
      'name': 'Ana',
      'password': '123',
      'age': 22,
      'fingerprint_template': template,
    });
    await expectLater(
      db.insert('users', {'name': 'ana', 'password': '456', 'age': 30}),
      throwsA(isA<DatabaseException>()),
    );
    await db.close();
    db = await databaseFactoryFfi.openDatabase(path);
    addTearDown(db.close);
    final store = Store(db);
    expect(
      (await store.users()).single['fingerprint_template'],
      orderedEquals(template),
    );
    await db.update('users', {'age': 23}, where: 'id = ?', whereArgs: [id]);
    expect(
      (await store.users()).single['fingerprint_template'],
      orderedEquals(template),
    );
    await store.setAddress('http://192.168.1.25');
    expect(await store.address(), 'http://192.168.1.25');
    await db.delete('users', where: 'id = ?', whereArgs: [id]);
    expect(await store.users(), isEmpty);
  });
  test('Migración conserva usuarios anteriores y permite recapturar', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute(
      'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, password TEXT, age INTEGER, fingerprint INTEGER UNIQUE)',
    );
    await db.insert('users', {
      'id': 1,
      'name': 'Anterior',
      'password': '123',
      'age': 25,
      'fingerprint': 7,
    });
    await Store.migrate(db, 1, 2);
    expect((await Store(db).users()).single['fingerprint_template'], isNull);
    await db.update('users', {
      'fingerprint_template': template,
      'fingerprint': null,
    }, where: 'id = 1');
    final row = (await Store(db).users()).single;
    expect(row['name'], 'Anterior');
    expect(row['fingerprint_template'], orderedEquals(template));
  });
  test('Transferencia hexadecimal conserva todos los bytes y rechaza datos inválidos', () {
    for (final length in [256, 512, 768, 1024, 1536, 2048]) {
      final bytes = Uint8List.fromList(List.generate(length, (i) => i % 256));
      expect(decodeTemplate(encodeTemplate(bytes)), orderedEquals(bytes));
    }
    for (final invalid in [
      null,
      1,
      '',
      '00',
      'z' * 1024,
      '0' * 511,
      '0' * 513,
      '0' * 1056,
      '0' * 4160,
    ]) {
      expect(() => decodeTemplate(invalid), throwsFormatException);
    }
  });
  test(
    'El cliente envía la plantilla SQLite y recibe el resultado de comparación',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final served = server.first.then((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/verify');
        final fields = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        expect(decodeTemplate(fields['template']), orderedEquals(template));
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ok":true,"match":true,"score":100}');
        await request.response.close();
      });
      final result = await Reader('http://127.0.0.1:${server.port}')
          .call('/verify', template: template);
      expect(result['match'], isTrue);
      await served;
    },
  );
}

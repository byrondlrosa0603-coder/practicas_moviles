import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Acceso biométrico',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b68)),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: const AccessPage(),
  );
}

class AccessPage extends StatefulWidget {
  const AccessPage({super.key});
  @override
  State<AccessPage> createState() => _AccessPageState();
}

class _AccessPageState extends State<AccessPage> {
  Store? store;
  String address = '', message = 'Preparando base de datos…';
  List<Map<String, Object?>> users = [];
  bool busy = false, fingerprintLogin = false;
  int? session;
  final name = TextEditingController(), password = TextEditingController();

  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void dispose() {
    name.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> initialize() async {
    try {
      final opened = await Store.open();
      final savedAddress = await opened.address();
      final rows = await opened.users();
      if (!mounted) return;
      setState(() {
        store = opened;
        address = savedAddress;
        users = rows;
        message = '';
      });
    } catch (e) {
      if (mounted) setState(() => message = 'No se pudo abrir SQLite: $e');
    }
  }

  Future<void> refresh() async {
    final rows = await store!.users();
    if (mounted) setState(() => users = rows);
  }

  Future<void> perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => message = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> login() => perform(() async {
    final matches = await store!.db.query(
      'users',
      where: 'name = ?',
      whereArgs: [name.text.trim()],
    );
    if (matches.isEmpty) throw Exception('Usuario no encontrado.');
    final user = matches.first;
    if (fingerprintLogin) {
      if (user['fingerprint_template'] == null) {
        throw Exception(
          'Ingresa con contrase?a y edita el usuario para capturar su huella en SQLite.',
        );
      }
      setState(() => message = 'Coloca tu dedo en el lector AS608…');
      final result = await Reader(address)
          .call('/verify', template: user['fingerprint_template'] as Uint8List);
      if (result['match'] != true) {
        throw Exception('La huella no corresponde al usuario.');
      }
    } else if (password.text != user['password']) {
      throw Exception('Contraseña incorrecta.');
    }
    await refresh();
    if (mounted) {
      setState(() {
        session = user['id'] as int;
        password.clear();
        message = '';
      });
    }
  });

  Future<void> settings() async {
    final input = TextEditingController(text: address);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conexión con ESP32'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Conecta ambos dispositivos a la misma red Wi-Fi. Escribe la dirección que aparece en el monitor serie.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: input,
                decoration: const InputDecoration(
                  labelText: 'Dirección',
                  hintText: 'http://192.168.1.100',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = input.text.trim();
              final uri = Uri.tryParse(value);
              if (uri != null &&
                  uri.scheme == 'http' &&
                  uri.host.isNotEmpty &&
                  !uri.hasQuery &&
                  !uri.hasFragment) {
                Navigator.pop(ctx, value);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    await perform(() async {
      await store!.setAddress(result);
      setState(() => address = result);
      await Reader(address).call('/status');
      setState(() => message = 'ESP32 y lector conectados.');
    });
  }

  Future<void> edit([Map<String, Object?>? user]) async {
    final form = GlobalKey<FormState>();
    final n = TextEditingController(text: user?['name'] as String? ?? '');
    final p = TextEditingController(text: user?['password'] as String? ?? '');
    final a = TextEditingController(text: user?['age']?.toString() ?? '');
    final save = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(user == null ? 'Crear usuario' : 'Editar usuario'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: n,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de usuario',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Escribe un nombre'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: p,
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    validator: (v) => v == null || v.isEmpty
                        ? 'Escribe una contraseña'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: a,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Edad'),
                    validator: (v) {
                      final age = int.tryParse(v ?? '');
                      return age == null || age < 1 || age > 120
                          ? 'Edad entre 1 y 120'
                          : null;
                    },
                  ),
                  if (user?['fingerprint_template'] == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'Al continuar: coloca el dedo, retíralo y vuelve a colocar el mismo dedo. La captura tarda hasta 60 segundos.',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: Text(
              user?['fingerprint_template'] == null
                  ? 'Continuar y capturar huella'
                  : 'Guardar',
            ),
          ),
        ],
      ),
    );
    if (save != true || !mounted) return;
    await perform(() async {
      final duplicate = await store!.db.query(
        'users',
        where: 'name = ?',
        whereArgs: [n.text.trim()],
      );
      if (duplicate.any((row) => row['id'] != user?['id'])) {
        throw Exception('Ya existe ese nombre de usuario.');
      }
      final values = <String, Object?>{
        'name': n.text.trim(),
        'password': p.text,
        'age': int.parse(a.text),
      };
      if (user?['fingerprint_template'] == null) {
        setState(
          () => message =
              'Capturando: coloca el dedo, ret?ralo y col?calo otra vez?',
        );
        final result = await Reader(address).call('/enroll');
        values['fingerprint_template'] = decodeTemplate(result['template']);
        values['fingerprint'] = null;
      }
      if (user == null) {
        await store!.db.insert('users', values);
      } else {
        await store!.db.update(
          'users',
          values,
          where: 'id = ?',
          whereArgs: [user['id']],
        );
      }
      await refresh();
      setState(() => message = 'Usuario guardado.');
    });
  }

  Future<void> remove(Map<String, Object?> user) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text('¿Eliminar a ${user['name']} y su huella de SQLite?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await perform(() async {
      await store!.db.delete('users', where: 'id = ?', whereArgs: [user['id']]);
      await refresh();
      setState(() {
        if (session == user['id']) session = null;
        message = 'Usuario eliminado.';
      });
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff1f5f5),
    appBar: AppBar(
      title: const Text('Acceso biométrico'),
      actions: [
        IconButton(
          tooltip: 'Configurar ESP32',
          onPressed: busy || store == null ? null : settings,
          icon: const Icon(Icons.settings),
        ),
        if (session != null)
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: busy
                ? null
                : () => setState(() {
                    session = null;
                    message = '';
                  }),
            icon: const Icon(Icons.logout),
          ),
      ],
    ),
    body: Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        if (message.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Text(message),
          ),
        Expanded(
          child: store == null
              ? Center(
                  child: message.isEmpty
                      ? const CircularProgressIndicator()
                      : FilledButton(
                          onPressed: initialize,
                          child: const Text('Reintentar'),
                        ),
                )
              : session == null
              ? loginView()
              : usersView(),
        ),
      ],
    ),
  );
  Widget loginView() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 430,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.fingerprint,
                  size: 64,
                  color: Color(0xff176b68),
                ),
                const SizedBox(height: 16),
                Text(
                  'Bienvenido',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ingresa para administrar tus usuarios',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Contraseña'),
                      icon: Icon(Icons.lock_outline),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Huella'),
                      icon: Icon(Icons.fingerprint),
                    ),
                  ],
                  selected: {fingerprintLogin},
                  onSelectionChanged: busy
                      ? null
                      : (v) => setState(() => fingerprintLogin = v.first),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: name,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de usuario',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                if (!fingerprintLogin)
                  TextField(
                    controller: password,
                    enabled: !busy,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    onSubmitted: (_) {
                      if (!busy) login();
                    },
                  ),
                if (fingerprintLogin)
                  const Text(
                    'Al ingresar, coloca tu dedo en el lector conectado al ESP32.',
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: busy ? null : login,
                  icon: Icon(
                    fingerprintLogin ? Icons.fingerprint : Icons.login,
                  ),
                  label: const Text('Ingresar'),
                ),
                if (users.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: OutlinedButton(
                      onPressed: busy ? null : () => edit(),
                      child: const Text('Registrar primer usuario'),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'SQLite local · Android / Windows',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget usersView() => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 16,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Usuarios',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text('${users.length} registros · Base de datos local'),
              ],
            ),
            FilledButton.icon(
              onPressed: busy ? null : () => edit(),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Crear usuario'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Nombre')),
                DataColumn(label: Text('Contraseña')),
                DataColumn(label: Text('Edad')),
                DataColumn(label: Text('Huella AS608')),
                DataColumn(label: Text('Acciones')),
              ],
              rows: users
                  .map(
                    (u) => DataRow(
                      cells: [
                        DataCell(Text('${u['name']}')),
                        DataCell(Text('${u['password']}')),
                        DataCell(Text('${u['age']}')),
                        DataCell(
                          Text(
                            u['fingerprint_template'] == null
                                ? 'Pendiente de captura'
                                : 'Guardada en SQLite',
                          ),
                        ),
                        DataCell(
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Editar',
                                onPressed: busy ? null : () => edit(u),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Eliminar',
                                onPressed: busy ? null : () => remove(u),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    ),
  );
}

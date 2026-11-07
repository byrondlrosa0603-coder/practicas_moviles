import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const AccessApp());

class AccessApp extends StatelessWidget {
  const AccessApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Acceso seguro',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B87)),
      scaffoldBackgroundColor: const Color(0xFFF5F8FA),
      useMaterial3: true,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD9E2EC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF176B87), width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF102A43),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ),
    home: const LoginPage(),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController(), _password = TextEditingController();
  final _auth = LocalAuthentication();
  bool _obscure = true, _hasBiometric = false;
  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _hasBiometric =
            (p.getBool('biometric_enabled') ?? false) &&
            (p.getString('username')?.isNotEmpty ?? false);
      });
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _login({bool biometric = false}) async {
    if (biometric) {
      try {
        final authenticated = await _auth.authenticate(
          localizedReason: 'Confirma tu identidad para entrar',
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        );
        if (!authenticated) {
          _message('No se pudo validar la biometría.');
          return;
        }
      } catch (_) {
        _message('La biometría no está disponible en este dispositivo.');
        return;
      }
    } else {
      final p = await SharedPreferences.getInstance();
      if (_user.text.trim().isEmpty || _password.text.isEmpty) {
        _message('Escribe tu usuario y contraseña.');
        return;
      }
      if (p.getString('username') != _user.text.trim() ||
          p.getString('password') != _password.text) {
        _message('Usuario o contraseña incorrectos.');
        return;
      }
    }
    final p = await SharedPreferences.getInstance();
    final username = biometric
        ? (p.getString('username') ?? '')
        : _user.text.trim();
    if (username.isEmpty) {
      _message('Primero crea un usuario y activa la biometría.');
      return;
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomePage(username: username)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 64,
                  color: Color(0xFF176B87),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Bienvenido',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF102A43),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Accede de forma rápida y segura',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF627D98)),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _user,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de usuario',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => _login(),
                  child: const Text(
                    'Iniciar sesión',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_hasBiometric) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _login(biometric: true),
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Entrar con biometría'),
                  ),
                ],
                const SizedBox(height: 18),
                TextButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegisterPage()),
                    );
                    _loadPreferences();
                  },
                  child: const Text('Crear usuario'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _user = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  final _auth = LocalAuthentication();
  bool _fingerprint = false;
  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _addBiometric() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported && _fingerprint) {
        _message(
          'Configura primero una huella en Ajustes > Seguridad del teléfono.',
        );
        return;
      }
      final authenticated = await _auth.authenticate(
        localizedReason: 'Registra tu huella para futuros accesos',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (!authenticated) {
        _message('La huella no fue validada.');
      } else if (mounted) {
        setState(() => _fingerprint = true);
      }
    } on LocalAuthException catch (error) {
      final message = switch (error.code) {
        LocalAuthExceptionCode.noBiometricsEnrolled =>
          'Android no reporta una huella registrada para esta app.',
        LocalAuthExceptionCode.noBiometricHardware =>
          'El teléfono no tiene hardware biométrico disponible.',
        LocalAuthExceptionCode.biometricLockout => 'La huella está bloqueada. Desbloquea el teléfono con PIN o patrón y vuelve a intentar.',
        LocalAuthExceptionCode.temporaryLockout => 'La huella está temporalmente bloqueada. Espera un momento y vuelve a intentar.',
        LocalAuthExceptionCode.uiUnavailable => 'No se pudo mostrar el diálogo de huella. Cierra otras ventanas e inténtalo de nuevo.',
        _ => 'Error biométrico: ${error.description ?? error.code.name}.',
      };
      _message(message);
    } catch (error) {
      _message('Error inesperado de biometría: $error');
    }
  }

  Future<void> _save() async {
    if (_user.text.trim().isEmpty || _password.text.length < 4) {
      _message('Usa un usuario y una contraseña de al menos 4 caracteres.');
      return;
    }
    if (_password.text != _confirm.text) {
      _message('Las contraseñas no coinciden.');
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setString('username', _user.text.trim());
    await p.setString('password', _password.text);
    await p.setBool('biometric_enabled', _fingerprint);
    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuario creado correctamente.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Crear usuario')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Configura tu acceso',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF102A43),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _user,
            decoration: const InputDecoration(
              labelText: 'Nombre de usuario',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirmar contraseña',
              prefixIcon: Icon(Icons.lock_reset_outlined),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.fingerprint,
                size: 34,
                color: Color(0xFF176B87),
              ),
              title: const Text(
                'Añadir huella',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                _fingerprint
                    ? 'Huella configurada'
                    : 'Usa biometría para entrar más rápido',
              ),
              trailing: _fingerprint
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : TextButton(
                      onPressed: _addBiometric,
                      child: const Text('Configurar'),
                    ),
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _save,
            child: const Text(
              'Guardar usuario',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.username});
  final String username;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription<UserAccelerometerEvent>? _subscription;
  double _x = 0, _y = 0, _z = 0, _total = 0;
  bool _active = false;
  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  double _removeSensorNoise(double value) => value.abs() < 0.15 ? 0 : value;

  void _toggleAccelerometer() {
    if (_active) {
      _subscription?.cancel();
      setState(() => _active = false);
      return;
    }
    // El acelerómetro de usuario elimina la gravedad y mide solo movimiento.
    _subscription = userAccelerometerEventStream().listen((e) {
      if (!mounted) return;
      setState(() {
        _x = _removeSensorNoise(e.x);
        _y = _removeSensorNoise(e.y);
        _z = _removeSensorNoise(e.z);
        _total = math.sqrt(_x * _x + _y * _y + _z * _z);
      });
    }, onError: (_) => _message('El acelerómetro no está disponible.'));
    setState(() => _active = true);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Panel principal'),
      actions: [
        IconButton(
          tooltip: 'Cerrar sesión',
          onPressed: () => Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (_) => false,
          ),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Hola, ${widget.username}',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFF102A43),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tu sesión está protegida.',
          style: TextStyle(color: Color(0xFF627D98)),
        ),
        const SizedBox(height: 28),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.speed, color: Color(0xFF176B87)),
                    SizedBox(width: 10),
                    Text(
                      'Acelerómetro',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _active
                      ? 'Moviendo el dispositivo...'
                      : 'Activa el sensor para ver los valores en tiempo real.',
                ),
                const SizedBox(height: 18),
                _SensorValue(label: 'Eje X', value: _x),
                _SensorValue(label: 'Eje Y', value: _y),
                _SensorValue(label: 'Eje Z', value: _z),
                const Divider(),
                _SensorValue(label: 'Magnitud', value: _total, accent: true),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _toggleAccelerometer,
                    icon: Icon(_active ? Icons.stop : Icons.play_arrow),
                    label: Text(
                      _active ? 'Detener sensor' : 'Activar acelerómetro',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _SensorValue extends StatelessWidget {
  const _SensorValue({
    required this.label,
    required this.value,
    this.accent = false,
  });
  final String label;
  final double value;
  final bool accent;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: accent ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          '${value.toStringAsFixed(2)} m/s²',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: accent ? const Color(0xFF176B87) : const Color(0xFF334E68),
          ),
        ),
      ],
    ),
  );
}

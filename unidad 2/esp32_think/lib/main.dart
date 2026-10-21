import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ThingsBoard ESP32',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
        home: const DashboardPage(),
      );
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _formKey = GlobalKey<FormState>();
  // Si cambian, edita aquí la URL, el correo y el Device ID.
  static const String _baseUrl = 'https://thingsboard.cloud';
  static const String _username = 'byrondlroasa06@gmail.com';
  static const String _deviceId = 'e4981050-c8b6-11f1-b97c-dd43a7f35a7a';
  final _passwordController = TextEditingController();
  Timer? _timer;
  String? _jwtToken;
  String? _error;
  bool _loading = false;
  bool _connected = false;
  final Map<String, String> _values = {
    'temperature': '--', 'humidity': '--', 'air_quality_ppm': '--', 'rssi': '--',
  };

  @override
  void dispose() {
    _timer?.cancel();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    _timer?.cancel();
    setState(() { _loading = true; _error = null; _connected = false; });
    try {
      final response = await http
          .post(Uri.parse('$_baseUrl/api/auth/login'),
              headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
              body: jsonEncode({'username': _username, 'password': _passwordController.text}))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception(_httpMessage('inicio de sesión', response));
      }
      final body = jsonDecode(response.body);
      final token = body is Map<String, dynamic> ? body['token'] : null;
      if (token is! String || token.isEmpty) throw Exception('ThingsBoard respondió sin token de acceso.');
      if (!mounted) return;
      setState(() { _jwtToken = token; _connected = true; _loading = false; _passwordController.clear(); });
      await _fetchTelemetry();
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchTelemetry());
    } on TimeoutException {
      _showError('Se agotó el tiempo de espera. Revisa la URL y tu conexión a Internet.');
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _httpMessage(String action, http.Response response) {
    final detail = response.body.trim();
    switch (response.statusCode) {
      case 401: return 'Credenciales incorrectas (HTTP 401). Usa el usuario y contraseña de ThingsBoard.';
      case 403: return 'Acceso denegado (HTTP 403). Verifica los permisos de tu cuenta sobre este dispositivo.';
      case 404: return 'No se encontró el recurso (HTTP 404). Revisa la URL de ThingsBoard.';
      default: return 'Error en $action (HTTP ${response.statusCode})${detail.isNotEmpty ? ': $detail' : '.'}';
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() { _loading = false; _connected = false; _jwtToken = null; _error = message; });
  }

  Future<void> _fetchTelemetry() async {
    final token = _jwtToken;
    if (token == null) return;
    try {
      final uri = Uri.parse('$_baseUrl/api/plugins/telemetry/DEVICE/$_deviceId/values/timeseries')
          .replace(queryParameters: {'keys': _values.keys.join(',')});
      final response = await http.get(uri, headers: {'Accept': 'application/json', 'X-Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        if (response.statusCode == 401) {
          _showError('La sesión expiró o el token no es válido (HTTP 401). Conéctate otra vez.');
        } else {
          _showError(_httpMessage('lectura de telemetría', response));
        }
        return;
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) throw const FormatException('Formato de telemetría no válido.');
      if (!mounted) return;
      setState(() {
        for (final key in _values.keys.toList()) {
          final readings = data[key];
          if (readings is List && readings.isNotEmpty && readings.first is Map) {
            _values[key] = readings.first['value']?.toString() ?? '--';
          }
        }
        _error = null;
      });
    } on TimeoutException {
      _showError('Tiempo de espera agotado al leer la telemetría.');
    } catch (e) {
      _showError('No se pudo leer la telemetría: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Widget _field(String label, TextEditingController controller, {bool obscure = false, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller, obscureText: obscure, keyboardType: label == 'URL de ThingsBoard' ? TextInputType.url : TextInputType.text,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
          validator: (value) => value == null || value.trim().isEmpty ? 'Este campo es obligatorio' : null,
        ),
      );

  Widget _reading(String key, String label, String unit, IconData icon, Color color) => Card(
        child: ListTile(
          leading: Icon(icon, color: color, size: 36), title: Text(label),
          trailing: Text('${_values[key]} $unit', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('ESP32 · ThingsBoard'),
          actions: [if (_connected) IconButton(onPressed: _fetchTelemetry, tooltip: 'Actualizar', icon: const Icon(Icons.refresh))],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _field('Contraseña', _passwordController, obscure: true),
            FilledButton(onPressed: _loading ? null : _connect, child: Text(_loading ? 'Conectando…' : 'Conectar')),
          ])),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_connected) ...[
            const SizedBox(height: 12),
            const ListTile(leading: Icon(Icons.cloud_done, color: Colors.green), title: Text('Conectado'), subtitle: Text('Actualización automática cada 5 segundos')),
            _reading('temperature', 'Temperatura', '°C', Icons.thermostat, Colors.orange),
            _reading('humidity', 'Humedad', '%', Icons.water_drop, Colors.blue),
            _reading('air_quality_ppm', 'Calidad del aire', 'PPM', Icons.air, Colors.green),
            _reading('rssi', 'Señal Wi-Fi (RSSI)', 'dBm', Icons.wifi, Colors.blueGrey),
          ],
        ]),
      );
}

// Librerías necesarias para conversión, E/S de archivos, criptografía y UI Flutter
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';

// Punto de entrada de la aplicación
void main() {
  runApp(const MyApp());
}

// Configuración inicial de la app
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Validación Log CSV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Integridad Log de Sensores'),
    );
  }
}

// Pantalla principal con estado para controlar la generación y validación
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // Estado de la verificación: null (sin verificar), true (válido), false (corrupto)
  bool? _isValid;
  String _statusMessage = 'Genera un archivo o valida el existente.';
  String _filePath = '';

  // Obtiene la ruta física del archivo CSV en los documentos de la app
  Future<File> _getLogFile() async {
    final dir = await getApplicationDocumentsDirectory();
    _filePath = '${dir.path}/sensor_log.csv';
    return File(_filePath);
  }

  // Genera 100 lecturas simuladas en formato CSV con firma SHA-256 en la cabecera
  Future<void> _generateSensorLog() async {
    final Random random = Random();
    final List<List<dynamic>> rows = [
      ['ID', 'Temperatura_C', 'Timestamp']
    ];

    final DateTime now = DateTime.now();

    // Genera 100 registros con temperaturas aleatorias entre 18.0°C y 38.0°C
    for (int i = 1; i <= 100; i++) {
      double temp = 18.0 + random.nextDouble() * 20.0;
      String timestamp = now.add(Duration(seconds: i)).toIso8601String();
      rows.add([i, double.parse(temp.toStringAsFixed(2)), timestamp]);
    }

    // Convierte las filas a formato CSV (sin usar const)
    String csvData = const ListToCsvConverter().convert(rows);

    // Genera el hash SHA-256 del contenido CSV
    var bytes = utf8.encode(csvData);
    var checksum = sha256.convert(bytes).toString();

    // Escribe la firma en la primera línea precedida del contenido
    final file = await _getLogFile();
    await file.writeAsString("# CHECKSUM:$checksum\n$csvData");

    setState(() {
      _isValid = null;
      _statusMessage = '¡Archivo CSV generado con 100 lecturas!';
    });
  }

  // Valida si el contenido actual del CSV coincide con la firma SHA-256 guardada
  Future<void> _validateLogIntegrity() async {
    final file = await _getLogFile();

    if (!await file.exists()) {
      setState(() {
        _isValid = false;
        _statusMessage = 'El archivo no existe. Genera uno primero.';
      });
      return;
    }

    String fullContent = await file.readAsString();

    // Comprueba formato básico de la cabecera
    if (!fullContent.startsWith("# CHECKSUM:")) {
      setState(() {
        _isValid = false;
        _statusMessage = 'Formato inválido o cabecera ausente.';
      });
      return;
    }

    int eolIndex = fullContent.indexOf('\n');
    if (eolIndex == -1) {
      setState(() {
        _isValid = false;
        _statusMessage = 'Estructura de archivo corrupta.';
      });
      return;
    }

    // Separa la firma original del cuerpo CSV
    String firstLine = fullContent.substring(0, eolIndex).trim();
    String originalChecksum = firstLine.replaceFirst("# CHECKSUM:", "").trim();
    String csvBody = fullContent.substring(eolIndex + 1);

    // Recalcula el checksum SHA-256 sobre el cuerpo actual
    var recalculatedChecksum = sha256.convert(utf8.encode(csvBody)).toString();

    // Compara ambos valores para determinar la integridad
    setState(() {
      if (originalChecksum == recalculatedChecksum) {
        _isValid = true;
        _statusMessage = 'Integridad verificada. El log es VÁLIDO.';
      } else {
        _isValid = false;
        _statusMessage = '¡ALERTA! El archivo fue modificado o está CORRUPTO.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Botón para generar las 100 lecturas y el hash
              ElevatedButton.icon(
                onPressed: _generateSensorLog,
                icon: const Icon(Icons.note_add),
                label: const Text('Generar Log de Sensores (CSV)'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
              const SizedBox(height: 16),

              // Botón para validar la firma SHA-256
              OutlinedButton.icon(
                onPressed: _validateLogIntegrity,
                icon: const Icon(Icons.verified_user),
                label: const Text('Validar Integridad Log'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
              const SizedBox(height: 40),

              // Indicador visual dinámico (Verde = Válido / Rojo = Corrupto)
              if (_isValid != null) ...[
                Icon(
                  _isValid! ? Icons.check_circle : Icons.cancel,
                  color: _isValid! ? Colors.green : Colors.red,
                  size: 80,
                ),
                const SizedBox(height: 16),
              ],

              // Estado de la operación
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _isValid == null
                      ? Colors.black87
                      : (_isValid! ? Colors.green.shade800 : Colors.red.shade800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
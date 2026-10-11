import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Estado inicial de las preferencias
  bool _isDarkMode = false;
  int _samplingInterval = 5;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  // Obtiene la ruta del archivo local dentro del directorio de documentos
  Future<File> _getLocalFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/user_preferences.json');
  }

  // Carga las preferencias guardadas al iniciar la aplicación
  Future<void> _loadPreferences() async {
    try {
      final file = await _getLocalFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        setState(() {
          _isDarkMode = data['isDarkMode'] ?? false;
          _samplingInterval = data['samplingInterval'] ?? 5;
        });
      }
    } catch (e) {
      debugPrint("Error al cargar las preferencias: $e");
    }
  }

  // Guarda las preferencias en segundo plano sin bloquear la UI
  Future<void> _savePreferences(bool isDark, int interval, BuildContext context) async {
    final Map<String, dynamic> preferencesData = {
      'isDarkMode': isDark,
      'samplingInterval': interval,
    };

    try {
      final file = await _getLocalFile();
      final jsonString = jsonEncode(preferencesData);

      // Operación asíncrona en segundo plano para no bloquear el Main Thread
      await file.writeAsString(jsonString, flush: true);

      // Notificación de éxito en la UI
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preferencias guardadas correctamente en JSON.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on FileSystemException catch (e) {
      // Captura específica para errores del sistema de archivos
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error del sistema de archivos: ${e.message}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      // Captura genérica de cualquier otra excepción
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error inesperado al guardar: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // Actualiza el estado local y dispara la persistencia en JSON
  void _updateSettings(bool isDark, int interval, BuildContext context) {
    setState(() {
      _isDarkMode = isDark;
      _samplingInterval = interval;
    });
    _savePreferences(isDark, interval, context);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ajustes IoT Persistentes',
      debugShowCheckedModeBanner: false,
      // Aplicación dinámica del tema según el estado cargado
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: MyHomePage(
        title: 'Preferencias IoT',
        isDarkMode: _isDarkMode,
        samplingInterval: _samplingInterval,
        onSettingsChanged: (isDark, interval, ctx) => _updateSettings(isDark, interval, ctx),
      ),
    );
  }
}

// Pantalla principal con controles para modificar la configuración
class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.isDarkMode,
    required this.samplingInterval,
    required this.onSettingsChanged,
  });

  final String title;
  final bool isDarkMode;
  final int samplingInterval;
  final Function(bool isDark, int interval, BuildContext context) onSettingsChanged;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late bool _currentDarkMode;
  late double _currentInterval;

  @override
  void initState() {
    super.initState();
    _currentDarkMode = widget.isDarkMode;
    _currentInterval = widget.samplingInterval.toDouble();
  }

  // Actualiza los controles locales cuando los datos cargan desde la BD o archivo
  @override
  void didUpdateWidget(covariant MyHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDarkMode != widget.isDarkMode) {
      _currentDarkMode = widget.isDarkMode;
    }
    if (oldWidget.samplingInterval != widget.samplingInterval) {
      _currentInterval = widget.samplingInterval.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configuración del Dispositivo',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            // Interruptor para cambio de tema
            SwitchListTile(
              title: const Text('Tema Oscuro'),
              subtitle: const Text('Cambia la apariencia global de la app'),
              value: _currentDarkMode,
              onChanged: (bool value) {
                setState(() {
                  _currentDarkMode = value;
                });
                widget.onSettingsChanged(_currentDarkMode, _currentInterval.toInt(), context);
              },
            ),
            const Divider(),
            
            // Deslizador para ajustar el intervalo de muestreo IoT
            ListTile(
              title: const Text('Intervalo de muestreo IoT'),
              subtitle: Text('${_currentInterval.toInt()} segundos'),
            ),
            Slider(
              value: _currentInterval,
              min: 1,
              max: 60,
              divisions: 59,
              label: '${_currentInterval.toInt()} seg',
              onChanged: (double value) {
                setState(() {
                  _currentInterval = value;
                });
              },
              onChangeEnd: (double value) {
                widget.onSettingsChanged(_currentDarkMode, value.toInt(), context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

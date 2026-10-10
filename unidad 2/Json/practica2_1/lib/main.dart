import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

void main() {
  runApp(const MyApp());
}

// Configuración general del tema y ruta inicial
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Registro Cifrado de Usuario'),
    );
  }
}

// Pantalla principal i
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // Controladores de texto para capturar los campos del formulario
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _edadController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();
  
  // Instancia para el manejo del almacenamiento cifrado
  final EncryptedJsonStorage _storage = EncryptedJsonStorage();
  String _resultado = 'Sin datos leídos aún';

  @override
  void dispose() {
    _nombreController.dispose();
    _edadController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  // Captura, valida y envía a cifrar los datos
  Future<void> _guardarDatos() async {
    final String nombre = _nombreController.text.trim();
    final String edad = _edadController.text.trim();
    final String telefono = _telefonoController.text.trim();

    // Validación de campos vacíos
    if (nombre.isEmpty || edad.isEmpty || telefono.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor completa todos los campos')),
      );
      return;
    }

    // Estructura de datos a guardar
    final Map<String, dynamic> datos = {
      'nombre': nombre,
      'edad': edad,
      'telefono': telefono,
      'fechaRegistro': DateTime.now().toIso8601String(),
    };

    // Guarda los datos en el archivo JSON cifrado
    await _storage.saveEncryptedJson('usuario_cifrado.json', datos);

    if (!mounted) return;

    // Actualiza la interfaz tras guardar
    setState(() {
      _resultado = '¡Datos guardados y cifrados con éxito!';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('¡Datos guardados correctamente!')),
    );
  }

  // Lee, descifra y muestra la información guardada
  Future<void> _leerDatos() async {
    final datos = await _storage.readEncryptedJson('usuario_cifrado.json');

    if (!mounted) return;

    // Actualiza el texto de resultado en la UI
    setState(() {
      if (datos != null) {
        _resultado =
            ' Datos Leídos:\n\n'
            ' Nombre: ${datos['nombre']}\n'
            ' Edad: ${datos['edad']} años\n'
            ' Teléfono: ${datos['telefono']}';
      } else {
        _resultado = 'No se encontró el archivo cifrado o ocurrió un error.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Campos de texto del formulario
              TextField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre Completo',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _edadController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Edad',
                  prefixIcon: Icon(Icons.cake),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _telefonoController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              
              // Botones para ejecutar guardar y leer
              ElevatedButton.icon(
                onPressed: _guardarDatos,
                icon: const Icon(Icons.lock),
                label: const Text('Guardar y Cifrar'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _leerDatos,
                icon: const Icon(Icons.lock_open),
                label: const Text('Leer y Descifrar'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 28),
              
              // Contenedor que muestra el resultado
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  _resultado,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Clase para manejar el cifrado AES y persistencia en JSON
class EncryptedJsonStorage {
  
  // Clave de 32 bytes
  final _key = encrypt.Key.fromUtf8('my32lengthsupersecretkey12345678');
  final _iv = encrypt.IV.fromUtf8('1234567890123456');

  // Obtiene la referencia del archivo en el directorio local del dispositivo
  Future<File> _getLocalFile(String filename) async {
    final Directory directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$filename');
  }

  Future<void> saveEncryptedJson(
    String filename,
    Map<String, dynamic> data,
  ) async {
    final file = await _getLocalFile(filename);
    final tempFile = File('${file.path}.tmp');
    final jsonString = jsonEncode(data);
    final encrypter = encrypt.Encrypter(encrypt.AES(_key));
    final encryptedData = encrypter.encrypt(jsonString, iv: _iv);

    // Escribe los datos en Base64 en el archivo temporal y luego reemplaza el original
    await tempFile.writeAsString(encryptedData.base64);
    await tempFile.rename(file.path);
  }

  // Lee el archivo en Base64, descifra el contenido y lo convierte de nuevo a Map
  Future<Map<String, dynamic>?> readEncryptedJson(String filename) async {
    try {
      final file = await _getLocalFile(filename);
      if (!await file.exists()) return null;

      final encryptedText = await file.readAsString();
      final encrypter = encrypt.Encrypter(encrypt.AES(_key));
      final decryptedText = encrypter.decrypt64(encryptedText, iv: _iv);
      return jsonDecode(decryptedText) as Map<String, dynamic>;
    } catch (e) {
      debugPrint("Error al leer el archivo cifrado: $e");
      return null;
    }
  }
}

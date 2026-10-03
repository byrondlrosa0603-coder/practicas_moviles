import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
       
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
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
  // Llave global para controlar y validar el formulario
  final _formKey = GlobalKey<FormState>();

  // Controladores para capturar el texto ingresado
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _edadController = TextEditingController();
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();

  // Variable para el campo de selección (Dropdown)
  String? _sexoSeleccionado;

  final List<String> _opcionesSexo = ['Masculino', 'Femenino', 'Otro'];

  @override
  void dispose() {
    // Liberar los controladores de memoria al destruir el widget
    _nombreController.dispose();
    _edadController.dispose();
    _correoController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  // ==========================================
  // FUNCIÓN PREPARADA PARA EL BOTÓN
  // ==========================================
  void _ingresarDatos() {
    // Valida todos los FormField dentro del Form
    if (_formKey.currentState!.validate()) {
      // Si la validación pasa, aquí tienes listos los datos recolectados:
      final String nombre = _nombreController.text.trim();
      final int? edad = int.tryParse(_edadController.text.trim());
      final String correo = _correoController.text.trim();
      final String telefono = _telefonoController.text.trim();
      final String sexo = _sexoSeleccionado ?? '';

      // Agrega aquí la lógica que necesites (llamar servicio, emitir estado, guardar, etc.)
      debugPrint('--- DATOS CAPTURADOS ---');
      debugPrint('Nombre: $nombre');
      debugPrint('Edad: $edad');
      debugPrint('Sexo: $sexo');
      debugPrint('Correo: $correo');
      debugPrint('Teléfono: $telefono');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Formulario validado con éxito'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ingreso de Datos'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- CAMPO: NOMBRE ---
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Por favor, ingresa tu nombre';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // --- CAMPO: EDAD ---
              TextFormField(
                controller: _edadController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Edad',
                  prefixIcon: Icon(Icons.cake_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Por favor, ingresa tu edad';
                  }
                  final n = int.tryParse(value);
                  if (n == null || n <= 0) {
                    return 'Ingresa una edad válida';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // --- CAMPO: SEXO ---
              DropdownButtonFormField<String>(
                initialValue: _sexoSeleccionado,
                decoration: const InputDecoration(
                  labelText: 'Sexo',
                  prefixIcon: Icon(Icons.people_outline),
                  border: OutlineInputBorder(),
                ),
                items: _opcionesSexo.map((sexo) {
                  return DropdownMenuItem<String>(
                    value: sexo,
                    child: Text(sexo),
                  );
                }).toList(),
                onChanged: (valor) {
                  setState(() {
                    _sexoSeleccionado = valor;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, selecciona una opción';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // --- CAMPO: CORREO ELECTRÓNICO ---
              TextFormField(
                controller: _correoController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Por favor, ingresa tu correo';
                  }
                  // Validación simple de formato de correo
                  final emailRegex = RegExp(r'^[^@]+@[^@]+\.[a-zA-Z]{2,}$');
                  if (!emailRegex.hasMatch(value.trim())) {
                    return 'Ingresa un correo electrónico válido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // --- CAMPO: TELÉFONO ---
              TextFormField(
                controller: _telefonoController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  prefixIcon: Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              // --- BOTÓN DE INGRESAR DATOS ---
              FilledButton.icon(
                onPressed: _ingresarDatos,
                icon: const Icon(Icons.save_outlined),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    'Ingresar Datos',
                    style: TextStyle(fontSize: 16),
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

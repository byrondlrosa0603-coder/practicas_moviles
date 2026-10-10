import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'producto.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CRUD MySQL Flutter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ProductoListScreen(),
    );
  }
}

// Widget principal que maneja la vista y el estado de los productos
class ProductoListScreen extends StatefulWidget {
  const ProductoListScreen({super.key});

  @override
  State<ProductoListScreen> createState() => _ProductoListScreenState();
}

class _ProductoListScreenState extends State<ProductoListScreen> {

  // URL del servidor
  final String baseUrl = "http://10.10.227.195/api_productos";

  // Controladores para capturar los datos de los campos de texto
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _precioController = TextEditingController();

  // Liberación de recursos de los controladores al cerrar el widget
  @override
  void dispose() {
    _nombreController.dispose();
    _precioController.dispose();
    super.dispose();
  }

  // READ
  Future<List<Producto>> _fetchProductos() async {
    final response = await http.get(Uri.parse('$baseUrl/obtener.php'));
    if (response.statusCode == 200) {
      final List<dynamic> jsonResponse = json.decode(response.body);
      return jsonResponse.map((item) => Producto.fromJson(item)).toList();
    } else {
      throw Exception('Error al cargar productos (${response.statusCode})');
    }
  }

  // CREATE / UPDATE
  Future<void> _saveProducto({String? id}) async {
    final isEditing = id != null;
    final url = isEditing ? '$baseUrl/actualizar.php' : '$baseUrl/crear.php';

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        if (isEditing) 'id': id,
        'nombre': _nombreController.text.trim(),
        'precio': _precioController.text.trim(),
      }),
    );

    // Limpia las entradas y redibuja la interfaz tras una respuesta exitosa
    if (response.statusCode == 200) {
      _nombreController.clear();
      _precioController.clear();
      setState(() {}); 
    }
  }

  // DELETE
  Future<void> _deleteProducto(String id) async {
    final response = await http.post(
      Uri.parse('$baseUrl/eliminar.php'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'id': id}),
    );

    // Redibuja la interfaz si la eliminación fue exitosa
    if (response.statusCode == 200) {
      setState(() {}); 
    }
  }

  void _showFormDialog({Producto? producto}) {
    // Carga los datos existentes si se pasa un producto para edición
    if (producto != null) {
      _nombreController.text = producto.nombre;
      _precioController.text = producto.precio;
    } else {
      _nombreController.clear();
      _precioController.clear();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(producto == null ? 'Nuevo Producto' : 'Editar Producto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nombreController,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: _precioController,
              decoration: const InputDecoration(labelText: 'Precio'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              _saveProducto(id: producto?.id);
              Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos (MySQL + Apache)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      // FutureBuilder para manejar estados asíncronos
      body: FutureBuilder<List<Producto>>(
        future: _fetchProductos(),
        builder: (context, snapshot) {
          // Estado de carga inicial
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            // Manejo y despliegue de errores HTTP o de conexión
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            // Muestra mensaje si la lista obtenida está vacía
            return const Center(child: Text('No hay productos registrados.'));
          }

          // Construcción de la lista desplegable de productos
          final productos = snapshot.data!;
          return ListView.builder(
            itemCount: productos.length,
            itemBuilder: (context, index) {
              final prod = productos[index];
              return ListTile(
                title: Text(prod.nombre),
                subtitle: Text('\$${prod.precio}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Botón para abrir diálogo de edición
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _showFormDialog(producto: prod),
                    ),
                    // Botón para eliminar el producto
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteProducto(prod.id),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      // Botón flotante para crear un nuevo registro
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
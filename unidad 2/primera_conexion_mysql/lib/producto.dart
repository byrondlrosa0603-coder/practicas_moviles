// Modelo de datos para representar un Producto
class Producto {
  final String id;
  final String nombre;
  final String precio;

  // Constructor con parámetros nombrados requeridos
  Producto({required this.id, required this.nombre, required this.precio});

  // Factory para instanciar el objeto a partir de un Map/JSON
  factory Producto.fromJson(Map<String, dynamic> json) {
    return Producto(
      id: json['id'].toString(),
      nombre: json['nombre'],
      precio: json['precio'].toString(),
    );
  }
}
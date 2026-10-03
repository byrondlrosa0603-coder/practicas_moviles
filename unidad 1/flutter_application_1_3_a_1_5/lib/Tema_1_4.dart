import 'package:flutter/material.dart';
class LayoutEjemplo extends StatelessWidget {
 const LayoutEjemplo({super.key});
 @override
 Widget build(BuildContext context) {
 return Scaffold(
 appBar: AppBar(title: const Text('Tema 1.4 - Panel de Control')),
 body: Padding(
 padding: const EdgeInsets.all(16.0),
 child: Column(
 children: [
 Row(
 children: const [
 Icon(Icons.thermostat, size: 30, color: Colors.red),
 SizedBox(width: 10),
 Expanded(
 child: Text(
 'Temperatura Actual: 24°C',
 style: TextStyle(fontSize: 18),
 ),
 ),
 ],
 ),
 const SizedBox(height: 20),
 Container(
 height: 120,
 width: double.infinity,
 color: Colors.blueAccent,
 child: const Center(
 child: Text(
 'Gráfica de Sensores',
 style: TextStyle(color: Colors.white, fontSize: 18),
 ),
 ),
 ),
 ],
 ),
 ),
 );
 }
}
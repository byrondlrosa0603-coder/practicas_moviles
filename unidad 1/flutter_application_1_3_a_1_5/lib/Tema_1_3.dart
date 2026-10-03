import 'package:flutter/material.dart';
class ControlEjemplo extends StatefulWidget {
 const ControlEjemplo({super.key});
 @override
 State<ControlEjemplo> createState() => _ControlEjemploState();
}
class _ControlEjemploState extends State<ControlEjemplo> {
 final TextEditingController _controller = TextEditingController();
 bool _switched = false;
 @override
 Widget build(BuildContext context) {
 return Scaffold(
 appBar: AppBar(title: const Text('Tema 1.3 - Controles Básicos')),
 body: Padding(
 padding: const EdgeInsets.all(16.0),
 child: Column(
 children: [
 TextField(
 controller: _controller,
 decoration: const InputDecoration(
 labelText: 'Ingrese un dato',
 border: OutlineInputBorder(),
 ),
 ),
 const SizedBox(height: 10),
 SwitchListTile(
 title: const Text('Activar sensor'),
 value: _switched,
 onChanged: (val) => setState(() => _switched = val),
 ),
 const SizedBox(height: 10),
 ElevatedButton(
 onPressed: () {
 print('Dato: ${_controller.text}, Estado: $_switched');
 },
 child: const Text('Guardar'),
 ),
 ],
 ),
 ),
 );
 }
}
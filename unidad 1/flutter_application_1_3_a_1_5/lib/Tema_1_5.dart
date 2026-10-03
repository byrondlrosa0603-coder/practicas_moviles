import 'package:flutter/material.dart';
class PantallaConMenus extends StatefulWidget {
 const PantallaConMenus({super.key});
 @override
 State<PantallaConMenus> createState() => _PantallaConMenusState();
}
class _PantallaConMenusState extends State<PantallaConMenus> {
 int _indexSeleccionado = 0;
 @override
 Widget build(BuildContext context) {
 return Scaffold(
 appBar: AppBar(
 title: const Text('Tema 1.5 - Menús'),
 actions: [
 PopupMenuButton<String>(
 onSelected: (value) => print('Opción seleccionada: $value'),
 itemBuilder: (context) => [
 const PopupMenuItem(value: 'config', child: Text('Configuración')),
 const PopupMenuItem(value: 'perfil', child: Text('Mi Perfil')),
 ],
 ),
 ],
 ),
 drawer: Drawer(
 child: ListView(
 padding: EdgeInsets.zero,
 children: [
 const DrawerHeader(
 decoration: BoxDecoration(color: Colors.blue),
 child: Text('Menú Principal', style: TextStyle(color: Colors.white, fontSize: 22)),
 ),
 ListTile(
 leading: const Icon(Icons.home),
 title: const Text('Inicio'),
 onTap: () => Navigator.pop(context),
 ),
 ],
 ),
 ),
 body: Center(
 child: Text('Pestaña activa: $_indexSeleccionado', style: const TextStyle(fontSize: 20)),
 ),
 bottomNavigationBar: BottomNavigationBar(
 currentIndex: _indexSeleccionado,
 onTap: (index) => setState(() => _indexSeleccionado = index),
 items: const [
 BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
 BottomNavigationBarItem(icon: Icon(Icons.sensors), label: 'Sensores'),
 ],
 ),
 );
 }
}
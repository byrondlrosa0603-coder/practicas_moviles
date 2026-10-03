import 'package:flutter/material.dart';
import 'Tema_1_3.dart';
void main() {
 runApp(const MyApp());
}
class MyApp extends StatelessWidget {
 const MyApp({super.key});
 @override
 Widget build(BuildContext context) {
 return MaterialApp(
 title: 'Práctica GUI Flutter',
 debugShowCheckedModeBanner: false,
 theme: ThemeData(
 primarySwatch: Colors.blue,
 ),
 // Aquí iremos cambiando la pantalla activa según cada tema
 home: const ControlEjemplo(),
 );
 }
}
// Pantalla provisional
class PantallaPrueba extends StatelessWidget {
 const PantallaPrueba({super.key});
 @override
 Widget build(BuildContext context) {
 return const Scaffold(
 body: Center(
 child: Text('Proyecto Configurado Correctamente'),
 ),
 );
 }
}
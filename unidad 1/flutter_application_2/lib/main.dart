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
      title: 'Práctica GUI Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
         primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

   Widget build(BuildContext context) { 
    return const Scaffold( 
      body: Center( 
        child: Text('Proyecto Configurado Correctamente'),
        
      ),
    );
  }

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  // ---> AGREGADO: Controlador para leer la caja de texto
  final TextEditingController _controlador = TextEditingController();
  // ---> AGREGADO: Variable donde se guarda el texto al hacer clic
  String _textoMostrado = '';
  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            // ---> AGREGADO: Caja de texto
            TextField(
              controller: _controlador,
            ),

            // ---> AGREGADO: Botón que toma el texto y actualiza la pantalla
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _textoMostrado = _controlador.text;
                });
              },
              child: const Text('Mostrar texto'),
            ),

            // ---> AGREGADO: Etiqueta con el texto resultante
            Text(_textoMostrado),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MaterialApp(
    home: CsvScreen(),
  ));
}

class CsvScreen extends StatefulWidget {
  const CsvScreen({super.key});

  @override
  State<CsvScreen> createState() => _CsvScreenState();
}

class _CsvScreenState extends State<CsvScreen> {
  final CsvNodeManager _csvManager = CsvNodeManager();
  
  String _savedFilePath = "";
  List<List<dynamic>>? _loadedData;
  
  // datos de prueba
  final List<List<dynamic>> _dummyNodes = [
    ["ID", "MacAddress", "Ubicacion", "Estado"],
    [1, "00:1B:44:11:3A:B7", "Puerta Principal", "Activo"],
    [2, "00:1B:44:11:3A:C8", "Servidores", "Inactivo"],
  ];

  // Genera y guarda el archivo CSV
  Future<void> _export() async {
    String path = await _csvManager.exportNodesToCsv(_dummyNodes);
    setState(() {
      _savedFilePath = path;
      _loadedData = null;
    });
  }
  
  // Verifica e importa el archivo CSV guardado
  Future<void> _import() async {
    if (_savedFilePath.isEmpty) return;
    
    try {
      List<List<dynamic>>? data = await _csvManager.verifyAndImportCsv(_savedFilePath);
      setState(() {
        _loadedData = data;
      });
    } catch (e) {
      // da error si el archivo fue alterado
      setState(() {
        _loadedData = null; 
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('FormatException: ', '')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CSV Test'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          ElevatedButton(
            onPressed: _export,
            child: const Text('Exportar a CSV'),
          ),
          ElevatedButton(
            onPressed: _import,
            child: const Text('Leer CSV'),
          ),
          Text('Ruta: $_savedFilePath'),
          
          if (_loadedData != null && _loadedData!.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: _loadedData![0].map((header) {
                  return DataColumn(label: Text(header.toString()));
                }).toList(),
                rows: _loadedData!.sublist(1).map((row) {
                  return DataRow(
                    cells: row.map((cell) => DataCell(Text(cell.toString()))).toList(),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
 // Clase para manejar la exportacion
class CsvNodeManager {
  Future<String> exportNodesToCsv(List<List<dynamic>> rows) async {
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/iot_nodes_config.csv';
    final file = File(filePath);
    
    // Convierte la lista a formato CSV
    String csvData = const ListToCsvConverter(eol: '\n').convert(rows);
    var bytes = utf8.encode(csvData);
    
    
    // Genera el checksum SHA-256
    var checksum = sha256.convert(bytes).toString();

    // Guarda la cabecera con el checksum y el contenido CSV
    await file.writeAsString("# CHECKSUM:$checksum\n$csvData");
    return filePath;
  }

  // Lee el archivo, valida la firma SHA-256
  Future<List<List<dynamic>>?> verifyAndImportCsv(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    
    String fullContent = await file.readAsString();
    // Revisa que contenga el formato correcto
    if (!fullContent.startsWith("# CHECKSUM:")) return null;
    
    int eolIndex = fullContent.indexOf('\n');
    if (eolIndex == -1) return null;
    
    // Extrae el hash
    String firstLine = fullContent.substring(0, eolIndex).trim();
    String originalChecksum = firstLine.replaceFirst("# CHECKSUM:", "").trim();
    
    // calcula hash SHA-256
    String csvBody = fullContent.substring(eolIndex + 1);
    var recalculatedChecksum = sha256.convert(utf8.encode(csvBody)).toString();
    
    // Compara los hashes
    if (originalChecksum == recalculatedChecksum) {
      return const CsvToListConverter(eol: '\n').convert(csvBody);
    } else {
      throw FormatException("ALERTA: El CSV fue alterado.");
    }
  }
}
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
  
  final List<List<dynamic>> _dummyNodes = [
    ["ID", "MacAddress", "Ubicacion", "Estado"],
    [1, "00:1B:44:11:3A:B7", "Puerta Principal", "Activo"],
    [2, "00:1B:44:11:3A:C8", "Servidores", "Inactivo"],
  ];

  Future<void> _export() async {
    String path = await _csvManager.exportNodesToCsv(_dummyNodes);
    setState(() {
      _savedFilePath = path;
      _loadedData = null;
    });
  }

  Future<void> _import() async {
    if (_savedFilePath.isEmpty) return;
    
    try {
      List<List<dynamic>>? data = await _csvManager.verifyAndImportCsv(_savedFilePath);
      setState(() {
        _loadedData = data;
      });
    } catch (e) {
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

class CsvNodeManager {
  Future<String> exportNodesToCsv(List<List<dynamic>> rows) async {
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/iot_nodes_config.csv';
    final file = File(filePath);
    
    String csvData = const ListToCsvConverter(eol: '\n').convert(rows);
    var bytes = utf8.encode(csvData);
    var checksum = sha256.convert(bytes).toString();
    
    await file.writeAsString("# CHECKSUM:$checksum\n$csvData");
    return filePath;
  }

  Future<List<List<dynamic>>?> verifyAndImportCsv(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    
    String fullContent = await file.readAsString();
    if (!fullContent.startsWith("# CHECKSUM:")) return null;
    
    int eolIndex = fullContent.indexOf('\n');
    if (eolIndex == -1) return null;
    
    String firstLine = fullContent.substring(0, eolIndex).trim();
    String originalChecksum = firstLine.replaceFirst("# CHECKSUM:", "").trim();
    
    String csvBody = fullContent.substring(eolIndex + 1);
    var recalculatedChecksum = sha256.convert(utf8.encode(csvBody)).toString();
    
    if (originalChecksum == recalculatedChecksum) {
      return const CsvToListConverter(eol: '\n').convert(csvBody);
    } else {
      throw FormatException("ALERTA: El CSV fue alterado.");
    }
  }
}
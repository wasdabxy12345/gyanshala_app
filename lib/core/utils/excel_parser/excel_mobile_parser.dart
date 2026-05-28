import 'dart:async';

import 'package:excel/excel.dart';

class ExcelWebParser {
  static Future<List<String>> parseFirstColumnFast(List<int> bytes) async {
    try {
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) return [];

      // Get the first sheet
      final firstSheetName = excel.tables.keys.first;
      final table = excel.tables[firstSheetName];
      if (table == null) return [];

      List<String> options = [];
      for (var row in table.rows) {
        if (row.isNotEmpty && row[0] != null) {
          final val = row[0]?.value.toString().trim() ?? '';
          if (val.isNotEmpty && val != "null") {
            options.add(val);
          }
        }
      }
      return options;
    } catch (e) {
      print("Mobile Excel Parser Error: $e");
      return [];
    }
  }
}

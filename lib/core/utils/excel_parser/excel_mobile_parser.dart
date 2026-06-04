import 'dart:async';

import 'package:excel/excel.dart';

class ExcelParser {
  static Future<List<String>> parseFirstColumnFast(List<int> bytes) async {
    try {
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) return [];
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

  static Future<List<Map<String, dynamic>>> parseLocationMatrix(List<int> bytes) async {
    try {
      final excel = Excel.decodeBytes(bytes);
      List<Map<String, dynamic>> rows = [];
      String? lastClusterName;
      String? lastVillageName;

      for (var table in excel.tables.keys) {
        var sheet = excel.tables[table];
        if (sheet == null) continue;
        for (int i = 0; i < sheet.maxRows; i++) {
          var row = sheet.rows[i];
          if (row.length < 3) continue;
          final rawCluster = row[0]?.value?.toString().trim();
          final rawVillage = row[1]?.value?.toString().trim();
          final schoolName = row[2]?.value?.toString().trim();
          final rawLat = row.length > 3 ? row[3]?.value?.toString().trim() : null;
          final rawLng = row.length > 4 ? row[4]?.value?.toString().trim() : null;

          if (rawCluster?.toLowerCase() == 'cluster' && schoolName?.toLowerCase() == 'school') {
            continue;
          }
          if (rawCluster != null && rawCluster.isNotEmpty) {
            lastClusterName = rawCluster;
          }
          if (rawVillage != null && rawVillage.isNotEmpty) {
            lastVillageName = rawVillage;
          }
          if (lastClusterName == null || lastClusterName.isEmpty) continue;
          if (schoolName == null || schoolName.isEmpty) continue;

          rows.add({'cluster': lastClusterName, 'village': lastVillageName, 'school': schoolName, 'lat': rawLat, 'lng': rawLng});
        }
      }
      return rows;
    } catch (e) {
      print("Mobile Location Parser Error: $e");
      return [];
    }
  }
}

import 'dart:async';

class ExcelParser {
  static Future<List<String>> parseFirstColumnFast(List<int> bytes) async {
    throw UnsupportedError('Cannot parse excel without platform implementation');
  }

  static Future<List<Map<String, dynamic>>> parseLocationMatrix(List<int> bytes) async {
    throw UnsupportedError('Cannot parse excel without platform implementation');
  }
}

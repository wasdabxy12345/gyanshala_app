// import 'dart:convert';
// import 'dart:io';
// import 'dart:math' as dev;

// import 'package:collection/collection.dart';
// import 'package:excel/excel.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';

// class ManageHolidays extends StatelessWidget {
//   final SupabaseClient _client;
//   ManageHolidays(this._client) : super(false);

//   Future<void> _handleExcelImport() async {}

//   Future<void> importHolidaysFromExcel() async {
//     FilePickerResult? result = await FilePicker.pickFiles(
//       type: FileType.custom,
//       allowedExtensions: ['xlsx', 'xls'],
//       withData: true,
//     );

//     if (result == null) return;

//     try {
//       final platformFile = result.files.first;
//       List<int> bytes;

//       if (platformFile.bytes != null) {
//         bytes = platformFile.bytes!;
//       } else if (platformFile.path != null) {
//         bytes = File(platformFile.path!).readAsBytesSync();
//       } else {
//         throw Exception("Could not read file data contents.");
//       }

//       final excel = Excel.decodeBytes(bytes);
//       final existingHolidays = await _client.from('holidays').select('holiday_date, description');

//       List<Map<String, dynamic>> newHolidays = [];
//       List<Map<String, dynamic>> conflictingHolidays = [];
//       List<String> errorMessages = [];

//       for (var table in excel.tables.keys) {
//         var sheet = excel.tables[table];

//         if (sheet == null) continue;

//         for (int i = 1; i < sheet.maxRows; i++) {
//           var row = sheet.rows[i];

//           if (row.isEmpty || row.every((cell) => cell == null)) continue;

//           String val(int index) => row[index]!.value.toString().trim();
//           DateFormat format = DateFormat("dd/MM/yyyy");
//           final DateTime date = format.parseStrict(val(0));
//           final desc = val(1);
//           List<String> rowErrors = [];

//           if (rowErrors.isNotEmpty) {
//             errorMessages.add("Row ${i + 1}: Missing ${rowErrors.join(', ')}");
//             continue;
//           }

//           final incomingData = {'holiday_date': date, 'description': desc};

//           final existingMatch = existingHolidays.firstWhereOrNull((h) => h['holiday_date'] == date);
//           if (existingMatch == null) {
//             newHolidays.add(incomingData);
//           } else {
//             bool isIdentical = existingMatch['holiday_date'] == date && existingMatch['description'] == desc;

//             if (!isIdentical) {
//               conflictingHolidays.add({'current': existingMatch, 'incoming': incomingData});
//             }
//           }
//         }
//       }

//       if (newHolidays.isNotEmpty) {
//         await _client.from('holidays').insert(newHolidays);
//       }

//       String partialSuffix = errorMessages.isNotEmpty ? "&&PARTIAL:${errorMessages.join('\n')}" : "";

//       if (conflictingHolidays.isNotEmpty) {
//         throw Exception(
//           "CONFLICT:${newHolidays.length}|${conflictingHolidays.length}|${jsonEncode(conflictingHolidays)}$partialSuffix",
//         );
//       }
//       if (errorMessages.isNotEmpty) {
//         throw Exception("PARTIAL:${errorMessages.join('\n')}");
//       }
//     } catch (e) {
//       dev.log("Excel Import Error", error: e);
//       rethrow;
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       floatingActionButton: FloatingActionButton.extended(
//         label: const Text("Import Excel"),
//         icon: const Icon(Icons.upload_file),
//         onPressed: _handleExcelImport,
//       ),
//     );
//   }
// }

// // In lib/features/employees/presentation/widgets/employee_attendance_table.dart

// /// Update exportExcel signature to accept filtered and sorted employees
// Future<void> exportExcel(List<Map<String, dynamic>> employees, Map<String, dynamic> attendanceMap) async {
//   final excel = Excel.createExcel();
//   final sheet = excel[excel.getDefaultSheet()!];

//   // Determine dates within range
//   List<DateTime> dateRange = [];
//   DateTime current = DateTime(widget.startDate.year, widget.startDate.month, widget.startDate.day);
//   final DateTime end = DateTime(widget.endDate.year, widget.endDate.month, widget.endDate.day);

//   while (!current.isAfter(end)) {
//     dateRange.add(current);
//     current = current.add(const Duration(days: 1));
//   }

//   // Header Row
//   List<CellValue> headerRow = [
//     TextCellValue("Employee Name"),
//     TextCellValue("Role"),
//     TextCellValue("Cluster"),
//     TextCellValue("Village"),
//     TextCellValue("School"),
//   ];

//   for (var date in dateRange) {
//     headerRow.add(TextCellValue(DateFormat('dd/MM').format(date)));
//   }
//   headerRow.add(TextCellValue("Total Present"));
//   headerRow.add(TextCellValue("Attendance %"));
//   sheet.appendRow(headerRow);

//   // Rows for Filtered/Sorted Employees
//   for (var emp in employees) {
//     final empId = emp['id'];
//     final empName = "${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}".trim();
//     final role = emp['role'] ?? '';
//     final cluster = emp['cluster'] ?? '';
//     final village = emp['village'] ?? '';
//     final school = emp['school'] ?? '';

//     List<CellValue> rowData = [
//       TextCellValue(empName),
//       TextCellValue(role),
//       TextCellValue(cluster),
//       TextCellValue(village),
//       TextCellValue(school),
//     ];

//     int presentCount = 0;
//     int totalWorkingDays = 0;

//     for (var date in dateRange) {
//       final dateKey = DateFormat('dd-MM-yyyy').format(date);
//       final record = attendanceMap[empId]?[dateKey];

//       if (date.weekday != DateTime.sunday) {
//         totalWorkingDays++;
//       }

//       if (record != null && record['status'] == 'present') {
//         presentCount++;
//         rowData.add(TextCellValue("P"));
//       } else if (record != null && record['status'] == 'late') {
//         presentCount++;
//         rowData.add(TextCellValue("L"));
//       } else if (date.weekday == DateTime.sunday) {
//         rowData.add(TextCellValue("-"));
//       } else {
//         rowData.add(TextCellValue("A"));
//       }
//     }

//     rowData.add(TextCellValue(presentCount.toString()));
//     final double percentage = totalWorkingDays > 0 ? (presentCount / totalWorkingDays) * 100 : 0.0;
//     rowData.add(TextCellValue("${percentage.toStringAsFixed(1)}%"));

//     sheet.appendRow(rowData);
//   }

//   final fileBytes = excel.save();
//   if (fileBytes == null) return;

//   final String fileName = "Employee_Attendance_${DateFormat('yyyyMMdd').format(widget.startDate)}_to_${DateFormat('yyyyMMdd').format(widget.endDate)}.xlsx";

//   if (kIsWeb) {
//     final blob = html.Blob([fileBytes]);
//     final url = html.Url.createObjectUrlFromBlob(blob);
//     final anchor = html.AnchorElement(href: url)
//       ..setAttribute("download", fileName)
//       ..click();
//     html.Url.revokeObjectUrl(url);
//   } else {
//     Directory downloadsDir;
//     if (Platform.isAndroid) {
//       downloadsDir = Directory('/storage/emulated/0/Download');
//     } else {
//       downloadsDir = await getApplicationDocumentsDirectory();
//     }
//     final file = File('${downloadsDir.path}/$fileName');
//     await file.writeAsBytes(fileBytes);

//     if (mounted) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Exported successfully to ${file.path}')),
//       );
//     }
//   }
// }

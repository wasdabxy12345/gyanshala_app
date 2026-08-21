// Future<void> exportExcel(List<Map<String, dynamic>> employees, Map<String, dynamic> attendanceMap) async {
//     try {
//       final data = await _loadDataPipeline();
//       final employeeMap = data['employees'] as Map<String, dynamic>;
//       final List<dynamic> rawRecords = data['records'];
//       final excel = Excel.createExcel();
//       final sheet = excel['Sheet1'];

//       final headers = [
//         "Name",
//         "Date",
//         "Check In Time",
//         "Check Out Time",
//         "Check In Location",
//         "Check Out Location",
//         "Check In Coordinates",
//         "Check Out Coordinates",
//       ];
//       sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());

//       Map<String, Map<String, dynamic>> structuredRows = {};
//       final sortedRecords = List.from(rawRecords)
//         ..sort((a, b) => DateTime.parse(a['recorded_at']).compareTo(DateTime.parse(b['recorded_at'])));

//       for (final record in sortedRecords) {
//         final userId = record['user_id'];
//         final employee = employeeMap[userId];
//         final String fullName = employee != null ? employee['full_name'] : 'Unknown Employee';
//         if (widget.searchQuery.isNotEmpty && !fullName.toLowerCase().contains(widget.searchQuery.toLowerCase())) {
//           continue;
//         }
//         if (_selectedEmployeeNameFilters != null && !_selectedEmployeeNameFilters!.contains(fullName)) {
//           continue;
//         }
//         final DateTime localTime = DateTime.parse(record['recorded_at']).toLocal();
//         final String dateKey = DateFormat('dd-MM-yyyy').format(localTime);
//         final String timeStr = DateFormat('HH:mm:ss').format(localTime);
//         final String status = record['status'] ?? '';

//         final schoolData = record['schools'];
//         final String schoolName = (schoolData != null && schoolData['name'] != null) ? schoolData['name'].toString() : "off-site";
//         final String variance = record['attendance_time_variance']?.toString() ?? "99:99:99";

//         final lat = record['latitude'];
//         final lon = record['longitude'];
//         final String coordinatesStr = (lat != null && lon != null) ? "$lat, $lon" : '';

//         final String rowCompositeKey = "${userId}_$dateKey";
//         if (!structuredRows.containsKey(rowCompositeKey)) {
//           structuredRows[rowCompositeKey] = {
//             'name': fullName,
//             'date': dateKey,
//             'check_in_time': '',
//             'check_in_variance': '99:99:99',
//             'check_in_loc': 'off-site',
//             'check_in_coords': '',
//             'check_out_time': '',
//             'check_out_variance': '99:99:99',
//             'check_out_loc': 'off-site',
//             'check_out_coords': '',
//           };
//         }

//         if (status == 'check_in') {
//           structuredRows[rowCompositeKey]!['check_in_time'] = timeStr;
//           structuredRows[rowCompositeKey]!['check_in_variance'] = variance;
//           structuredRows[rowCompositeKey]!['check_in_loc'] = schoolName;
//           structuredRows[rowCompositeKey]!['check_in_coords'] = coordinatesStr;
//         } else if (status == 'check_out') {
//           structuredRows[rowCompositeKey]!['check_out_time'] = timeStr;
//           structuredRows[rowCompositeKey]!['check_out_variance'] = variance;
//           structuredRows[rowCompositeKey]!['check_out_loc'] = schoolName;
//           structuredRows[rowCompositeKey]!['check_out_coords'] = coordinatesStr;
//         }
//       }

//       final CellStyle offSiteAlertStyle = CellStyle(backgroundColorHex: ExcelColor.redAccent);
//       final CellStyle varianceAlertStyle = CellStyle(backgroundColorHex: ExcelColor.redAccent);
//       int currentExcelRowIndex = 1;

//       for (final rowKey in structuredRows.keys) {
//         final r = structuredRows[rowKey]!;

//         sheet.appendRow([
//           TextCellValue(r['name']),
//           TextCellValue(r['date']),
//           TextCellValue(r['check_in_time']),
//           TextCellValue(r['check_out_time']),
//           TextCellValue(r['check_in_loc']),
//           TextCellValue(r['check_out_loc']),
//           TextCellValue(r['check_in_coords']),
//           TextCellValue(r['check_out_coords']),
//         ]);

//         final String checkInVar = r['check_in_variance'];
//         final String checkOutVar = r['check_out_variance'];
//         final String checkInLoc = r['check_in_loc'].toString().toLowerCase();
//         final String checkOutLoc = r['check_out_loc'].toString().toLowerCase();

//         bool isCheckInLate = checkInVar != "00:00:00" && checkInVar != "00:00:00.000";
//         bool isCheckOutEarly = checkOutVar != "00:00:00" && checkOutVar != "00:00:00.000";

//         if (isCheckInLate && r['check_in_time'].isNotEmpty) {
//           sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: currentExcelRowIndex)).cellStyle = varianceAlertStyle;
//         }
//         if (isCheckOutEarly && r['check_out_time'].isNotEmpty) {
//           sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: currentExcelRowIndex)).cellStyle = varianceAlertStyle;
//         }
//         if (checkInLoc == "off-site") {
//           sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: currentExcelRowIndex)).cellStyle = offSiteAlertStyle;
//         }
//         if (checkOutLoc == "off-site") {
//           sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentExcelRowIndex)).cellStyle = offSiteAlertStyle;
//         }

//         currentExcelRowIndex++;
//       }

//       final bytes = excel.encode();
//       if (bytes == null) throw Exception('Failed to generate excel file');

//       final startRange = DateFormat('dd-MM-yy').format(widget.startDate);
//       final endRange = DateFormat('dd-MM-yy').format(widget.endDate);
//       final fileName = 'Employee_Attendance_Summary_[$startRange to $endRange].xlsx';

//       if (kIsWeb) {
//         final blob = html.Blob([bytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
//         final url = html.Url.createObjectUrlFromBlob(blob);
//         final anchor = html.AnchorElement()
//           ..href = url
//           ..download = fileName
//           ..style.display = 'none';
//         html.document.body?.children.add(anchor);
//         anchor.click();
//         anchor.remove();
//         html.Url.revokeObjectUrl(url);
//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance exported successfully')));
//         }
//       } else {
//         var status = await Permission.manageExternalStorage.status;
//         if (!status.isGranted) {
//           status = await Permission.manageExternalStorage.request();
//         }
//         Directory? downloadsDir = Directory('/storage/emulated/0/Download');
//         if (!await downloadsDir.exists()) {
//           final List<Directory>? externalDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
//           downloadsDir = externalDirs != null && externalDirs.isNotEmpty
//               ? externalDirs.first
//               : await getApplicationDocumentsDirectory();
//         }
//         final file = File('${downloadsDir.path}/$fileName');
//         await file.writeAsBytes(bytes);
//         if (mounted) {
//           ScaffoldMessenger.of(context).hideCurrentSnackBar();
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Row(
//                 children: [
//                   IconButton(
//                     icon: const Icon(Icons.close, color: Colors.red),
//                     padding: EdgeInsets.zero,
//                     constraints: const BoxConstraints(),
//                     onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
//                   ),
//                   const SizedBox(width: 13),
//                   Expanded(child: Text("Saved to Downloads: $fileName", softWrap: true)),
//                 ],
//               ),
//               action: SnackBarAction(label: "OPEN", onPressed: () async => await OpenFilex.open(file.path)),
//             ),
//           );
//         }
//       }
//     } catch (e) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
//     }
//   }

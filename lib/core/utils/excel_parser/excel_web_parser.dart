import 'dart:js_interop';

@JS()
external JSObject get globalThis;
@JS('Reflect.get')
external JSAny? _jsGet(JSObject target, JSString key);
@JS('Reflect.set')
external bool _jsSet(JSObject target, JSString key, JSAny? value);

extension JSObjectLookupExtension on JSObject {
  JSAny? operator [](String key) => _jsGet(this, key.toJS);
  void operator []=(String key, JSAny? value) => _jsSet(this, key.toJS, value);
}

@JS('Uint8Array')
extension type JSUint8Array._(JSObject _) implements JSObject {
  @JS('from')
  external static JSObject from(JSArray array);
}
@JS('Object')
extension type JSObjectFactory._(JSObject _) implements JSObject {
  @JS('create')
  external static JSObject create(JSObject? prototype);
}
@JS('XLSX.read')
external JSObject _xlsxRead(JSObject data, JSObject options);
@JS('XLSX.utils.sheet_to_json')
external JSArray _sheetToJson(JSObject sheet, JSObject options);

class ExcelWebParser {
  static Future<List<String>> parseFirstColumnFast(List<int> bytes) async {
    try {
      final List<JSAny> jsAnyList = bytes.map((e) => e.toJS).toList();
      final jsArray = jsAnyList.toJS;
      final uint8Array = JSUint8Array.from(jsArray);
      final readOptions = JSObjectFactory.create(null);
      readOptions['type'] = 'array'.toJS;
      final workbook = _xlsxRead(uint8Array, readOptions);
      final sheetNames = workbook['SheetNames'] as JSArray;
      if (sheetNames.length == 0) return [];
      final firstSheetName = sheetNames.toDart[0] as JSString;
      final sheets = workbook['Sheets'] as JSObject;
      final firstSheet = sheets[firstSheetName.toDart] as JSObject;
      final jsonOptions = JSObjectFactory.create(null);
      jsonOptions['header'] = 1.toJS;
      jsonOptions['defval'] = ''.toJS;
      final rawRows = _sheetToJson(firstSheet, jsonOptions);
      List<String> options = [];
      final dartRows = rawRows.toDart;
      for (var row in dartRows) {
        if (row != null && row is JSArray) {
          final rowData = row.toDart;
          if (rowData.isNotEmpty && rowData[0] != null) {
            final val = rowData[0].toString().trim();
            if (val.isNotEmpty && val != "null") {
              options.add(val);
            }
          }
        }
      }
      return options;
    } catch (e) {
      print("JavaScript Excel Parser Error: $e");
      return [];
    }
  }
}

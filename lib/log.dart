import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String> readLogFile() async {
  try {
    final directory = await getExternalStorageDirectory();
    final file = File('${directory!.path}/app_logs.txt');
    return await file.readAsString();
  } catch (e) {
    return "Không thể đọc file log: $e";
  }
}
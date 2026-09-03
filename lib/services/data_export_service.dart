import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'database_service.dart';

/// Handles full user data export to Downloads as a JSON backup file,
/// and import from any JSON file picked by the user.
class DataExportService {
  static final DataExportService instance = DataExportService._internal();
  DataExportService._internal();

  /// Exports all data for [uid] to the device Downloads directory.
  /// Returns the path of the created file, or null on error.
  Future<String?> exportToDownloads(String uid) async {
    try {
      final data = await DatabaseService.instance.exportAllData(uid);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

      final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'grow_backup_$dateStr.json';

      Directory targetDir;
      if (Platform.isAndroid) {
        final extDirs = await getExternalStorageDirectories();
        if (extDirs != null && extDirs.isNotEmpty) {
          final base = extDirs.first.path.split('Android').first;
          targetDir = Directory('${base}Download');
        } else {
          targetDir = await getApplicationDocumentsDirectory();
        }
      } else {
        targetDir = await getApplicationDocumentsDirectory();
      }

      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final file = File('${targetDir.path}/$fileName');
      await file.writeAsString(jsonStr, encoding: utf8);

      debugPrint('[DataExport] Exported to: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('[DataExport] Export error: $e');
      return null;
    }
  }

  /// Opens a file picker, reads the JSON backup file, and restores all data.
  /// Returns true on success, false on failure/cancel.
  Future<bool> importFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return false;

      final filePath = result.files.single.path;
      if (filePath == null) return false;

      final file = File(filePath);
      final jsonStr = await file.readAsString(encoding: utf8);
      final data = json.decode(jsonStr) as Map<String, dynamic>;

      if (data['export_version'] == null) {
        debugPrint('[DataImport] Invalid backup file - missing export_version');
        return false;
      }

      await DatabaseService.instance.importAllData(data);
      debugPrint('[DataImport] Import successful from $filePath');
      return true;
    } catch (e) {
      debugPrint('[DataImport] Import error: $e');
      return false;
    }
  }
}
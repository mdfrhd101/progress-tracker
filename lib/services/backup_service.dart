import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database_helper.dart';

/// Result of merging a backup file.
class MergeResult {
  final int tasksAdded;
  final int sessionsAdded;
  const MergeResult(this.tasksAdded, this.sessionsAdded);
}

/// Offline backup: export all data to a JSON file and share it; import a JSON
/// file and union-merge it (by uid, never overwriting or deleting). No network.
class BackupService {
  static const MethodChannel _channel =
      MethodChannel('com.octagram.progress_tracker/platform');

  final DatabaseHelper _db;
  BackupService([DatabaseHelper? db]) : _db = db ?? DatabaseHelper.instance;

  /// Writes a backup file and opens the system share sheet. Returns the path.
  Future<String> exportAndShare() async {
    final data = await _db.exportData();
    final dir = await getApplicationCacheDirectory();
    final stamp =
        DateTime.now().toIso8601String().replaceAll(':', '').split('.').first;
    final file = File('${dir.path}/progress_tracker_backup_$stamp.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    try {
      await _channel.invokeMethod('shareFile', {
        'path': file.path,
        'mime': 'application/json',
      });
    } on PlatformException {
      // sharing failed; the file still exists at file.path
    } on MissingPluginException {
      // ignore
    }
    return file.path;
  }

  /// Writes a backup file to app storage without sharing (fallback / local copy).
  Future<String> exportToFile() async {
    final data = await _db.exportData();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/progress_tracker_backup.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file.path;
  }

  /// Lets the user pick a JSON backup and merges it. Returns null if cancelled.
  Future<MergeResult?> pickAndMerge() async {
    String? path;
    try {
      path = await _channel.invokeMethod<String>('pickJson');
    } on PlatformException {
      throw const FormatException('Could not open the file picker.');
    } on MissingPluginException {
      throw const FormatException('File picking is unavailable.');
    }
    if (path == null) return null; // cancelled

    final text = await File(path).readAsString();
    final data = jsonDecode(text);
    if (data is! Map || data['tasks'] is! List) {
      throw const FormatException(
          'That file is not a Progress Tracker backup.');
    }
    final (t, sAdded) = await _db.mergeData(data.cast<String, Object?>());
    return MergeResult(t, sAdded);
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';

/// A release found on GitHub.
class UpdateInfo {
  final String version; // e.g. "1.4.0" (tag without the leading v)
  final String tag; // e.g. "v1.4.0"
  final String apkUrl; // browser_download_url of the ABI-matched APK
  final int apkSize; // bytes
  final String notes; // release body

  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.apkUrl,
    required this.apkSize,
    required this.notes,
  });
}

/// Checks GitHub Releases, downloads the matching APK and launches the
/// installer. This is the ONLY part of the app that uses the network.
class UpdateService {
  static const MethodChannel _channel =
      MethodChannel('com.octagram.progress_tracker/platform');

  const UpdateService();

  /// Returns an [UpdateInfo] when a newer version exists, else null.
  /// Throws on network/parse errors so the UI can show a message.
  Future<UpdateInfo?> checkForUpdate() async {
    final abi = await _abi();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.getUrl(Uri.parse(AppInfo.latestReleaseApi));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'ProgressTracker-Updater');
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('GitHub returned ${resp.statusCode}');
      }
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, Object?>;

      final tag = (json['tag_name'] as String?) ?? '';
      final latest = tag.replaceFirst(RegExp('^v'), '');
      if (latest.isEmpty || !_isNewer(latest, AppInfo.version)) return null;

      final assets = (json['assets'] as List?) ?? const [];
      String? url;
      int size = 0;
      // Prefer the APK for this device's ABI; fall back to the universal one.
      for (final a in assets) {
        final m = a as Map<String, Object?>;
        final name = (m['name'] as String?) ?? '';
        if (name.endsWith('$abi-release.apk')) {
          url = m['browser_download_url'] as String?;
          size = (m['size'] as int?) ?? 0;
          break;
        }
      }
      if (url == null) {
        for (final a in assets) {
          final m = a as Map<String, Object?>;
          final name = (m['name'] as String?) ?? '';
          if (name.endsWith('.apk')) {
            url = m['browser_download_url'] as String?;
            size = (m['size'] as int?) ?? 0;
            break;
          }
        }
      }
      if (url == null) return null;

      return UpdateInfo(
        version: latest,
        tag: tag,
        apkUrl: url,
        apkSize: size,
        notes: (json['body'] as String?)?.trim() ?? '',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads [info] to the cache, reporting 0..1 progress, and returns the
  /// local file path.
  Future<String> download(
      UpdateInfo info, void Function(double) onProgress) async {
    final dir = await getApplicationCacheDirectory();
    final updates = Directory('${dir.path}/updates')
      ..createSync(recursive: true);
    final file = File('${updates.path}/progress_tracker_${info.version}.apk');

    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(info.apkUrl));
      req.headers.set(HttpHeaders.userAgentHeader, 'ProgressTracker-Updater');
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('Download failed (${resp.statusCode})');
      }
      final total = resp.contentLength > 0 ? resp.contentLength : info.apkSize;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in resp) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress(received / total);
      }
      await sink.close();
      return file.path;
    } finally {
      client.close(force: true);
    }
  }

  /// Hands the downloaded APK to the system installer.
  /// Returns 'ok', 'permission' (user must allow installs), or 'error'.
  Future<String> install(String path) async {
    try {
      return await _channel
              .invokeMethod<String>('installApk', {'path': path}) ??
          'error';
    } on PlatformException {
      return 'error';
    } on MissingPluginException {
      return 'error';
    }
  }

  Future<String> _abi() async {
    try {
      return await _channel.invokeMethod<String>('getAbi') ?? 'arm64-v8a';
    } catch (_) {
      return 'arm64-v8a';
    }
  }

  /// Semver-ish compare: true if [a] > [b] (numeric, dot-separated).
  static bool _isNewer(String a, String b) {
    final pa = a.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    final pb = b.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}

/// Test-only access to the private version comparator.
class UpdateServiceTestHook {
  const UpdateServiceTestHook._();
  static bool isNewer(String a, String b) => UpdateService._isNewer(a, b);
}

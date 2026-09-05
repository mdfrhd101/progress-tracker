import 'dart:convert';
import 'dart:io';

import '../data/database_helper.dart';

class CloudResult {
  final String gistId;
  final int tasksAdded;
  final int sessionsAdded;
  const CloudResult(this.gistId, this.tasksAdded, this.sessionsAdded);
}

class CloudException implements Exception {
  final String message;
  const CloudException(this.message);
  @override
  String toString() => message;
}

/// Cloud sync over a PRIVATE GitHub Gist. The gist holds the union of both
/// phones' data as one JSON file; syncing = pull → merge locally → push the
/// merged union back. Auth uses a user-supplied token stored only on-device
/// (never embedded in the APK, never included in backups).
///
/// Identity without a login: the gist id is the "sync code" both phones share.
class CloudSyncService {
  static const String _fileName = 'progress_tracker.json';
  static const String _prefToken = 'github_token';
  static const String _prefGist = 'cloud_gist_id';
  static const String _prefAuto = 'cloud_auto';
  static const String _prefLast = 'cloud_last_sync';

  final DatabaseHelper _db;
  CloudSyncService([DatabaseHelper? db]) : _db = db ?? DatabaseHelper.instance;

  // ------------------------------------------------------------- settings

  Future<String?> token() async {
    final t = await _db.getPref(_prefToken);
    return (t == null || t.isEmpty) ? null : t;
  }

  Future<void> setToken(String value) => _db.setPref(_prefToken, value.trim());

  Future<String?> gistId() async {
    final g = await _db.getPref(_prefGist);
    return (g == null || g.isEmpty) ? null : g;
  }

  Future<void> setGistId(String value) => _db.setPref(_prefGist, value.trim());

  Future<bool> autoEnabled() async => (await _db.getPref(_prefAuto)) == '1';

  Future<void> setAuto(bool value) => _db.setPref(_prefAuto, value ? '1' : '0');

  Future<int?> lastSyncMs() async {
    final v = await _db.getPref(_prefLast);
    return v == null ? null : int.tryParse(v);
  }

  Future<void> disconnect() async {
    await _db.setPref(_prefGist, '');
    await _db.setPref(_prefAuto, '0');
  }

  // --------------------------------------------------------------- actions

  /// Creates a new private gist seeded with this device's data. Returns its id.
  Future<String> createStore() async {
    final tok = await _requireToken();
    final data = await _db.exportData();
    final body = jsonEncode({
      'description': 'Progress Tracker sync (private)',
      'public': false,
      'files': {
        _fileName: {'content': jsonEncode(data)}
      },
    });
    final json = await _api('POST', 'https://api.github.com/gists', tok, body);
    final id = json['id'] as String?;
    if (id == null) {
      throw const CloudException('GitHub did not return a gist id.');
    }
    await setGistId(id);
    await _touch();
    return id;
  }

  /// Pull → merge → push. Uses the stored gist id (or [gistIdOverride]).
  Future<CloudResult> sync({String? gistIdOverride}) async {
    final tok = await _requireToken();
    final id = gistIdOverride ?? await gistId();
    if (id == null || id.isEmpty) {
      throw const CloudException('No sync code set.');
    }

    // Pull
    final remote = await _pull(tok, id);
    var t = 0, s = 0;
    if (remote != null) {
      final (rt, rs) = await _db.mergeData(remote);
      t = rt;
      s = rs;
    }
    // Push the merged union back.
    final merged = await _db.exportData();
    await _push(tok, id, merged);

    await setGistId(id);
    await _touch();
    return CloudResult(id, t, s);
  }

  // ----------------------------------------------------------------- http

  Future<Map<String, Object?>?> _pull(String tok, String id) async {
    final json =
        await _api('GET', 'https://api.github.com/gists/$id', tok, null);
    final files = json['files'] as Map<String, Object?>?;
    final file = files?[_fileName] as Map<String, Object?>?;
    if (file == null) return null; // empty store
    String? content = file['content'] as String?;
    if (file['truncated'] == true) {
      final rawUrl = file['raw_url'] as String?;
      if (rawUrl != null) content = await _getRaw(tok, rawUrl);
    }
    if (content == null || content.isEmpty) return null;
    final decoded = jsonDecode(content);
    if (decoded is! Map || decoded['tasks'] is! List) return null;
    return decoded.cast<String, Object?>();
  }

  Future<void> _push(String tok, String id, Map<String, Object?> data) async {
    final body = jsonEncode({
      'files': {
        _fileName: {'content': jsonEncode(data)}
      },
    });
    await _api('PATCH', 'https://api.github.com/gists/$id', tok, body);
  }

  Future<Map<String, Object?>> _api(
      String method, String url, String tok, String? body) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.openUrl(method, Uri.parse(url));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $tok');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'ProgressTracker-Sync');
      req.headers.set('X-GitHub-Api-Version', '2022-11-28');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(body));
      }
      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw const CloudException(
            'Token rejected. Check its Gist permission.');
      }
      if (resp.statusCode == 404) {
        throw const CloudException('Sync code not found for this token.');
      }
      if (resp.statusCode >= 300) {
        throw CloudException('GitHub error ${resp.statusCode}.');
      }
      return jsonDecode(text) as Map<String, Object?>;
    } on SocketException {
      throw const CloudException('No internet connection.');
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _getRaw(String tok, String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $tok');
      req.headers.set(HttpHeaders.userAgentHeader, 'ProgressTracker-Sync');
      final resp = await req.close();
      if (resp.statusCode >= 300) return null;
      return await resp.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _requireToken() async {
    final t = await token();
    if (t == null) throw const CloudException('No GitHub token saved.');
    return t;
  }

  Future<void> _touch() =>
      _db.setPref(_prefLast, '${DateTime.now().millisecondsSinceEpoch}');
}

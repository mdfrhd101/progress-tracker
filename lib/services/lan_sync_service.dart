import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../data/database_helper.dart';

typedef ExportFn = Future<Map<String, Object?>> Function();
typedef MergeFn = Future<(int, int)> Function(Map<String, Object?>);

class SyncResult {
  final int tasksAdded;
  final int sessionsAdded;
  const SyncResult(this.tasksAdded, this.sessionsAdded);
}

/// Same-Wi-Fi peer sync over raw TCP (no plugins, no HTTP → no cleartext
/// policy issues). One device hosts, the other joins with the host's IP + PIN;
/// a single connection merges data BOTH ways using the UUID union-merge.
class LanSyncService {
  static const int port = 43219;

  final ExportFn _export;
  final MergeFn _merge;
  ServerSocket? _server;

  LanSyncService({ExportFn? export, MergeFn? merge})
      : _export = export ?? DatabaseHelper.instance.exportData,
        _merge = merge ?? DatabaseHelper.instance.mergeData;

  bool get isHosting => _server != null;

  /// This device's private Wi-Fi IPv4 (e.g. 192.168.0.12), or null if offline.
  Future<String?> localIp() async {
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final ni in ifaces) {
      for (final a in ni.addresses) {
        final ip = a.address;
        if (a.isLoopback) continue;
        if (ip.startsWith('192.168.') ||
            ip.startsWith('10.') ||
            ip.startsWith('172.')) {
          return ip;
        }
      }
    }
    // Fallback: first non-loopback IPv4.
    for (final ni in ifaces) {
      for (final a in ni.addresses) {
        if (!a.isLoopback) return a.address;
      }
    }
    return null;
  }

  /// Starts the host. For each successful sync, [onSync] fires; [onError] fires
  /// on a rejected/failed attempt.
  Future<void> startHost({
    required String pin,
    required void Function(SyncResult) onSync,
    required void Function(Object) onError,
  }) async {
    await stopHost();
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen((socket) async {
      try {
        final msg = await _readFrame(socket);
        final data = jsonDecode(utf8.decode(msg)) as Map<String, Object?>;
        if (data['pin'] != pin) {
          await _writeFrame(
              socket, utf8.encode(jsonEncode({'ok': false, 'error': 'pin'})));
          await socket.flush();
          await socket.close();
          onError(const _PinError());
          return;
        }
        final (t, s) = await _merge(data);
        final export = await _export();
        await _writeFrame(
            socket, utf8.encode(jsonEncode({'ok': true, ...export})));
        await socket.flush();
        await socket.close();
        onSync(SyncResult(t, s));
      } catch (e) {
        onError(e);
        try {
          await socket.close();
        } catch (_) {}
      }
    }, onError: onError);
  }

  Future<void> stopHost() async {
    await _server?.close();
    _server = null;
  }

  /// Connects to a host and syncs both ways. Throws on wrong PIN / no host.
  Future<SyncResult> join({required String host, required String pin}) async {
    final socket =
        await Socket.connect(host, port, timeout: const Duration(seconds: 8));
    try {
      final export = await _export();
      await _writeFrame(
          socket, utf8.encode(jsonEncode({'pin': pin, ...export})));
      await socket.flush();
      final resp = await _readFrame(socket);
      final data = jsonDecode(utf8.decode(resp)) as Map<String, Object?>;
      if (data['ok'] != true) throw const _PinError();
      final (t, s) = await _merge(data);
      return SyncResult(t, s);
    } finally {
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  // --------------------------------------------------------- framing (len+json)

  Future<void> _writeFrame(Socket socket, List<int> bytes) async {
    final header = ByteData(4)..setUint32(0, bytes.length);
    socket.add(header.buffer.asUint8List());
    socket.add(bytes);
  }

  /// Reads one 4-byte-length-prefixed frame from [socket].
  Future<Uint8List> _readFrame(Socket socket) {
    final completer = Completer<Uint8List>();
    var buf = Uint8List(0);
    int? need;
    late StreamSubscription<Uint8List> sub;

    void tryParse() {
      if (need == null && buf.length >= 4) {
        need = ByteData.sublistView(buf, 0, 4).getUint32(0);
        buf = buf.sublist(4);
      }
      if (need != null && buf.length >= need!) {
        final frame = buf.sublist(0, need!);
        if (!completer.isCompleted) completer.complete(frame);
        sub.cancel();
      }
    }

    sub = socket.listen(
      (chunk) {
        final merged = Uint8List(buf.length + chunk.length);
        merged.setRange(0, buf.length, buf);
        merged.setRange(buf.length, merged.length, chunk);
        buf = merged;
        tryParse();
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(const SocketException('closed'));
        }
      },
      cancelOnError: true,
    );
    return completer.future;
  }
}

class _PinError implements Exception {
  const _PinError();
  @override
  String toString() => 'Wrong PIN or the host rejected the connection.';
}

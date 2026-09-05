import 'package:flutter_test/flutter_test.dart';
import 'package:progress_tracker/services/lan_sync_service.dart';

/// A tiny in-memory stand-in for a device's data, exposing the same
/// export/merge shape LanSyncService uses. Merges by task/session `uid`.
class FakeDevice {
  final Map<String, Map<String, Object?>> tasks = {};
  final Map<String, Map<String, Object?>> sessions = {};

  Future<Map<String, Object?>> export() async => {
        'tasks': tasks.values.toList(),
        'sessions': sessions.values.toList(),
      };

  Future<(int, int)> merge(Map<String, Object?> data) async {
    var t = 0, s = 0;
    for (final row in (data['tasks'] as List).cast<Map<String, Object?>>()) {
      final uid = row['uid'] as String;
      if (!tasks.containsKey(uid)) {
        tasks[uid] = row;
        t++;
      }
    }
    for (final row in (data['sessions'] as List).cast<Map<String, Object?>>()) {
      final uid = row['uid'] as String;
      if (!sessions.containsKey(uid)) {
        sessions[uid] = row;
        s++;
      }
    }
    return (t, s);
  }
}

void main() {
  test('host + join merge both directions over a real socket', () async {
    final a = FakeDevice()
      ..tasks['ta'] = {'uid': 'ta', 'name': 'A-task'}
      ..sessions['sa'] = {'uid': 'sa', 'task_uid': 'ta'};
    final b = FakeDevice()
      ..tasks['tb'] = {'uid': 'tb', 'name': 'B-task'}
      ..sessions['sb'] = {'uid': 'sb', 'task_uid': 'tb'};

    final host = LanSyncService(export: b.export, merge: b.merge);
    final client = LanSyncService(export: a.export, merge: a.merge);

    SyncResult? hostGot;
    await host.startHost(
      pin: '123456',
      onSync: (r) => hostGot = r,
      onError: (e) => fail('host error: $e'),
    );

    // A joins B: A sends its data (B gains A-task+sa), B replies with its data
    // (A gains B-task+sb).
    final clientGot = await client.join(host: '127.0.0.1', pin: '123456');

    expect(clientGot.tasksAdded, 1); // A gained B-task
    expect(clientGot.sessionsAdded, 1); // A gained sb
    // Give the host callback a tick to run.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(hostGot?.tasksAdded, 1); // B gained A-task
    expect(hostGot?.sessionsAdded, 1);

    // Both devices now hold both tasks.
    expect(a.tasks.keys.toSet(), {'ta', 'tb'});
    expect(b.tasks.keys.toSet(), {'ta', 'tb'});

    await host.stopHost();
  });

  test('wrong PIN is rejected and nothing merges', () async {
    final a = FakeDevice()..tasks['ta'] = {'uid': 'ta', 'name': 'A'};
    final b = FakeDevice()..tasks['tb'] = {'uid': 'tb', 'name': 'B'};
    final host = LanSyncService(export: b.export, merge: b.merge);
    final client = LanSyncService(export: a.export, merge: a.merge);

    await host.startHost(
      pin: '111111',
      onSync: (_) => fail('should not sync'),
      onError: (_) {},
    );

    await expectLater(
      client.join(host: '127.0.0.1', pin: '000000'),
      throwsA(isA<Exception>()),
    );
    expect(a.tasks.containsKey('tb'), isFalse); // no data leaked
    await host.stopHost();
  });
}

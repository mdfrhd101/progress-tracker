import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:progress_tracker/data/database_helper.dart';
import 'package:progress_tracker/data/models/session.dart';
import 'package:progress_tracker/data/models/task.dart';

/// Runs the whole SQLite layer on desktop via the FFI factory + an in-memory DB.
/// No device/emulator required:  flutter test
void main() {
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.databasePathOverride = inMemoryDatabasePath;
  });

  setUp(() async {
    // Fresh in-memory DB per test.
    await db.close();
  });

  test('seeds the 3 default tasks on first launch', () async {
    final tasks = await db.getAllTasks();
    expect(tasks.map((t) => t.name), containsAll(DatabaseHelper.defaultTasks));
    expect(await db.taskCount(), 3);
  });

  test('inserts a task and rejects a duplicate name (UNIQUE)', () async {
    final id = await db.insertTask(Task.create('Reading'));
    expect(id, greaterThan(0));
    expect(await db.taskCount(), 4);

    expect(
      () => db.insertTask(Task.create('Reading')),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('inserts a session and aggregates focus time', () async {
    final tasks = await db.getAllTasks();
    final taskId = tasks.first.id!;
    final today = Session.dateStringFrom(DateTime.now().millisecondsSinceEpoch);

    await db.insertSession(Session(
      taskId: taskId,
      startTime: DateTime.now().millisecondsSinceEpoch,
      endTime: DateTime.now().millisecondsSinceEpoch,
      activeDurationSeconds: 1800, // 30m
      breakDurationSeconds: 300, // 5m
      isDeepFocus: true,
      dateString: today,
    ));

    expect(await db.sessionCount(), 1);
    expect(await db.todayFocusSeconds(), 1800);
    expect(await db.weeklyFocusSeconds(), 1800);

    final views = await db.getAllSessionViews();
    expect(views.single.taskName, tasks.first.name);
    expect(views.single.session.isDeepFocus, isTrue);
  });

  test('task breakdown groups per task, biggest first', () async {
    final tasks = await db.getAllTasks();
    final today = Session.dateStringFrom(DateTime.now().millisecondsSinceEpoch);
    Session s(int taskId, int secs) => Session(
          taskId: taskId,
          startTime: 0,
          endTime: 0,
          activeDurationSeconds: secs,
          breakDurationSeconds: 0,
          isDeepFocus: false,
          dateString: today,
        );
    await db.insertSession(s(tasks[0].id!, 600));
    await db.insertSession(s(tasks[1].id!, 1200));

    final breakdown = await db.taskBreakdown(AnalyticsRange.today);
    expect(breakdown.first.taskName, tasks[1].name); // 1200 > 600
    expect(breakdown.first.totalActiveSeconds, 1200);
  });

  test('deleting a task cascades its sessions', () async {
    final tasks = await db.getAllTasks();
    final today = Session.dateStringFrom(DateTime.now().millisecondsSinceEpoch);
    await db.insertSession(Session(
      taskId: tasks.first.id!,
      startTime: 0,
      endTime: 0,
      activeDurationSeconds: 100,
      breakDurationSeconds: 0,
      isDeepFocus: false,
      dateString: today,
    ));
    expect(await db.sessionCount(), 1);

    await db.deleteTask(tasks.first.id!);
    expect(await db.sessionCount(), 0); // cascaded
  });

  test('7-day trend always returns 7 chronological buckets', () async {
    final trend = await db.dailyTotalsLast7Days();
    expect(trend.length, 7);
    // oldest -> newest
    final days = trend.map((d) => d.dateString).toList();
    final sorted = [...days]..sort();
    expect(days, sorted);
  });
  test('prefs: set/get/overwrite a key (v2 table)', () async {
    expect(await db.getPref('selected_task_id'), isNull);
    await db.setPref('selected_task_id', '2');
    expect(await db.getPref('selected_task_id'), '2');
    await db.setPref('selected_task_id', '3'); // REPLACE on conflict
    expect(await db.getPref('selected_task_id'), '3');
  });

  test('session count and average per range', () async {
    final tasks = await db.getAllTasks();
    final today = Session.dateStringFrom(DateTime.now().millisecondsSinceEpoch);
    Session s(int secs) => Session(
          taskId: tasks.first.id!,
          startTime: 0,
          endTime: 0,
          activeDurationSeconds: secs,
          breakDurationSeconds: 0,
          isDeepFocus: false,
          dateString: today,
        );
    expect(await db.todaySessionCount(), 0);
    expect(await db.averageSessionSeconds(AnalyticsRange.today), 0);

    await db.insertSession(s(600));
    await db.insertSession(s(1200));

    expect(await db.todaySessionCount(), 2);
    expect(await db.averageSessionSeconds(AnalyticsRange.today), 900);
    expect(await db.averageSessionSeconds(AnalyticsRange.week), 900);
    expect(await db.averageSessionSeconds(AnalyticsRange.allTime), 900);
  });

  test('re-inserting a deleted session with its id restores it (undo)',
      () async {
    final tasks = await db.getAllTasks();
    final today = Session.dateStringFrom(DateTime.now().millisecondsSinceEpoch);
    final id = await db.insertSession(Session(
      taskId: tasks.first.id!,
      startTime: 10,
      endTime: 20,
      activeDurationSeconds: 300,
      breakDurationSeconds: 0,
      isDeepFocus: true,
      dateString: today,
    ));
    final view = (await db.getAllSessionViews()).single;
    await db.deleteSession(id);
    expect(await db.sessionCount(), 0);

    await db.insertSession(view.session); // same id -> exact restore
    final restored = (await db.getAllSessionViews()).single.session;
    expect(restored.id, id);
    expect(restored.isDeepFocus, isTrue);
    expect(restored.activeDurationSeconds, 300);
  });
  test('sub-tasks: parent path in views/breakdown, own totals, cascade',
      () async {
    final today = Session.dateStringFrom(DateTime.now().millisecondsSinceEpoch);
    final cloudId =
        await db.insertTask(Task.create('Cloud', targetSeconds: 360000));
    final pyId = await db.insertTask(
        Task.create('Python', parentId: cloudId, targetSeconds: 36000));
    final tasks = await db.getAllTasks();
    final py = tasks.firstWhere((t) => t.id == pyId);
    expect(py.parentId, cloudId);
    expect(py.isSubtask, isTrue);
    expect(py.targetHours, 10);

    Session s(int taskId, int secs) => Session(
          taskId: taskId,
          startTime: 0,
          endTime: 0,
          activeDurationSeconds: secs,
          breakDurationSeconds: 0,
          isDeepFocus: false,
          dateString: today,
        );
    await db.insertSession(s(pyId, 600));
    await db.insertSession(s(cloudId, 300));

    // History shows the path, breakdown names use "Parent › Sub".
    final views = await db.getAllSessionViews();
    expect(views.map((v) => v.displayName),
        containsAll(['Cloud › Python', 'Cloud']));
    final bd = await db.taskBreakdown(AnalyticsRange.today);
    expect(bd.map((t) => t.taskName), containsAll(['Cloud › Python', 'Cloud']));

    // Own totals per task id (parent aggregation happens in Dart).
    final totals = await db.taskOwnTotals();
    expect(totals[pyId], 600);
    expect(totals[cloudId], 300);

    // Update target / rename.
    await db.updateTask(py.copyWith(name: 'Python 3', targetSeconds: 7200));
    final renamed = (await db.getTaskById(pyId))!;
    expect(renamed.name, 'Python 3');
    expect(renamed.targetSeconds, 7200);

    // Deleting the parent cascades the sub-task and every session.
    await db.deleteTask(cloudId);
    expect(await db.getTaskById(pyId), isNull);
    expect(await db.sessionCount(), 0);
  });

  test('migration v1 -> v4 keeps data and adds columns/tables', () async {
    // Build a v1 schema by hand, then let DatabaseHelper upgrade it.
    await db.close();
    final v1 = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, _) async {
            await d.execute(
                'CREATE TABLE tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL, created_at INTEGER NOT NULL)');
            await d.execute(
                'CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER NOT NULL, start_time INTEGER NOT NULL, end_time INTEGER NOT NULL, active_duration_seconds INTEGER NOT NULL, break_duration_seconds INTEGER NOT NULL, is_deep_focus INTEGER NOT NULL DEFAULT 0, date_string TEXT NOT NULL, FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE)');
            await d.execute(
                'CREATE TABLE active_session (id INTEGER PRIMARY KEY CHECK (id = 1), task_id INTEGER NOT NULL, start_time INTEGER NOT NULL, accumulated_break_ms INTEGER NOT NULL, current_break_start_ms INTEGER NOT NULL, is_deep_focus INTEGER NOT NULL, status TEXT NOT NULL)');
            await d.insert('tasks', {'name': 'Legacy', 'created_at': 1});
            await d.insert('sessions', {
              'task_id': 1,
              'start_time': 0,
              'end_time': 0,
              'active_duration_seconds': 42,
              'break_duration_seconds': 0,
              'is_deep_focus': 0,
              'date_string': '2026-01-01'
            });
          }),
    );
    // In-memory DBs are per-connection, so run the upgrade on THIS connection.
    expect(await v1.getVersion(), 1);
    await v1.close();
    // Real upgrade path: a file-backed DB that starts at v1, then reopened by the helper.
    final path =
        '${Directory.systemTemp.path}/pt_migr_${DateTime.now().microsecondsSinceEpoch}.db';
    final f1 = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 1,
            onCreate: (d, _) async {
              await d.execute(
                  'CREATE TABLE tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL, created_at INTEGER NOT NULL)');
              await d.execute(
                  'CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER NOT NULL, start_time INTEGER NOT NULL, end_time INTEGER NOT NULL, active_duration_seconds INTEGER NOT NULL, break_duration_seconds INTEGER NOT NULL, is_deep_focus INTEGER NOT NULL DEFAULT 0, date_string TEXT NOT NULL, FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE)');
              await d.execute(
                  'CREATE TABLE active_session (id INTEGER PRIMARY KEY CHECK (id = 1), task_id INTEGER NOT NULL, start_time INTEGER NOT NULL, accumulated_break_ms INTEGER NOT NULL, current_break_start_ms INTEGER NOT NULL, is_deep_focus INTEGER NOT NULL, status TEXT NOT NULL)');
              await d.insert('tasks', {'name': 'Legacy', 'created_at': 1});
              await d.insert('sessions', {
                'task_id': 1,
                'start_time': 0,
                'end_time': 0,
                'active_duration_seconds': 42,
                'break_duration_seconds': 0,
                'is_deep_focus': 0,
                'date_string': '2026-01-01'
              });
            }));
    await f1.close();

    DatabaseHelper.databasePathOverride = path;
    try {
      final tasks = await db.getAllTasks();
      expect(tasks.single.name, 'Legacy');
      expect(tasks.single.parentId, isNull); // new column readable
      expect(await db.sessionCount(), 1); // data preserved
      await db.setPref('k', 'v'); // v2 table exists
      final subId = await db.insertTask(
          Task.create('Sub', parentId: tasks.single.id, targetSeconds: 10));
      expect((await db.getTaskById(subId))!.parentId,
          tasks.single.id); // v3 columns work
      expect(await (await db.database).getVersion(), 4);
      // v4 multitasking table works.
      final mId = await db.insertMulti({
        'task_id': tasks.single.id,
        'start_time': 1,
        'accumulated_break_ms': 0,
        'current_break_start_ms': 0,
        'status': 'running',
      });
      expect((await db.getAllMulti()).length, 1);
      await db.deleteMulti(mId);
      expect((await db.getAllMulti()).isEmpty, isTrue);
    } finally {
      await db.close();
      DatabaseHelper.databasePathOverride = inMemoryDatabasePath;
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
  });
}

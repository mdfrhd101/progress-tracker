import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'models/session.dart';
import 'models/task.dart';

/// Date window used by the analytics queries.
enum AnalyticsRange { today, week, allTime }

/// Single source of truth for all local persistence.
///
/// Offline SQLite via `sqflite`. The DB file lives in the app's private
/// documents directory (resolved with `path_provider`). Foreign keys are
/// enabled so deleting a task cascades its sessions.
///
/// Access through the singleton: `DatabaseHelper.instance`.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const String _dbName = 'progress_tracker.db';
  static const int _dbVersion = 3;

  /// Default tasks seeded on first launch.
  static const List<String> defaultTasks = <String>[
    'Cloud Study',
    'Vocabulary App',
    'Job/Office Work',
  ];

  /// Tests set this (e.g. to `inMemoryDatabasePath`) to bypass `path_provider`.
  static String? databasePathOverride;

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final String path;
    if (databasePathOverride != null) {
      path = databasePathOverride!;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = p.join(dir.path, _dbName);
    }
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        // Must run on every open, not just onCreate.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tasks (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        name           TEXT    UNIQUE NOT NULL,
        created_at     INTEGER NOT NULL,
        parent_id      INTEGER REFERENCES tasks(id) ON DELETE CASCADE,
        target_seconds INTEGER
      )
    ''');
    await db.execute('CREATE INDEX idx_tasks_parent ON tasks(parent_id)');

    await db.execute('''
      CREATE TABLE sessions (
        id                      INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id                 INTEGER NOT NULL,
        start_time              INTEGER NOT NULL,
        end_time                INTEGER NOT NULL,
        active_duration_seconds INTEGER NOT NULL,
        break_duration_seconds  INTEGER NOT NULL,
        is_deep_focus           INTEGER NOT NULL DEFAULT 0,
        date_string             TEXT    NOT NULL,
        FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
      )
    ''');

    // Analytics filter heavily on the day key — index it.
    await db.execute(
      'CREATE INDEX idx_sessions_date_string ON sessions(date_string)',
    );

    // Single-row snapshot of an in-flight session, so a backgrounded OR
    // process-killed timer can be restored on next launch (CHECK pins id=1).
    await db.execute('''
      CREATE TABLE active_session (
        id                     INTEGER PRIMARY KEY CHECK (id = 1),
        task_id                INTEGER NOT NULL,
        start_time             INTEGER NOT NULL,
        accumulated_break_ms   INTEGER NOT NULL,
        current_break_start_ms INTEGER NOT NULL,
        is_deep_focus          INTEGER NOT NULL,
        status                 TEXT    NOT NULL
      )
    ''');

    await _createPrefsTable(db);

    // Seed default tasks in one transaction.
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final name in defaultTasks) {
      batch.insert('tasks', {'name': name, 'created_at': now});
    }
    await batch.commit(noResult: true);
  }

  /// Incremental migrations.
  ///   v2: key/value `prefs` table.
  ///   v3: sub-tasks (`parent_id`) and goals (`target_seconds`) on `tasks`.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createPrefsTable(db);
    }
    if (oldVersion < 3) {
      // Additive, data-preserving. SQLite allows a REFERENCES clause on
      // ADD COLUMN when the default is NULL.
      await db.execute(
          'ALTER TABLE tasks ADD COLUMN parent_id INTEGER REFERENCES tasks(id) ON DELETE CASCADE');
      await db.execute('ALTER TABLE tasks ADD COLUMN target_seconds INTEGER');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_tasks_parent ON tasks(parent_id)');
    }
  }

  Future<void> _createPrefsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS prefs (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // ------------------------------------------------------------------ Prefs

  Future<String?> getPref(String key) async {
    final db = await database;
    final rows =
        await db.query('prefs', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setPref(String key, String value) async {
    final db = await database;
    await db.insert('prefs', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ------------------------------------------------------------------ Tasks

  /// Inserts a task. Throws a [DatabaseException] if the name already exists
  /// (UNIQUE constraint) — callers surface a friendly message.
  Future<int> insertTask(Task task) async {
    final db = await database;
    return db.insert('tasks', task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<List<Task>> getAllTasks() async {
    final db = await database;
    final rows = await db.query('tasks', orderBy: 'created_at ASC, id ASC');
    return rows.map(Task.fromMap).toList();
  }

  /// Updates name / parent / target of an existing task (by id).
  Future<int> updateTask(Task task) async {
    final db = await database;
    return db
        .update('tasks', task.toMap(), where: 'id = ?', whereArgs: [task.id]);
  }

  /// All-time net focus seconds recorded DIRECTLY on each task
  /// (task_id -> seconds). Parent totals = own + children, summed in Dart.
  Future<Map<int, int>> taskOwnTotals() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT task_id, SUM(active_duration_seconds) AS total FROM sessions GROUP BY task_id',
    );
    return {
      for (final r in rows) (r['task_id'] as int): ((r['total'] as int?) ?? 0),
    };
  }

  Future<Task?> getTaskById(int id) async {
    final db = await database;
    final rows =
        await db.query('tasks', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Task.fromMap(rows.first);
  }

  /// Deletes a task and (via ON DELETE CASCADE) all of its sessions.
  Future<int> deleteTask(int id) async {
    final db = await database;
    return db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> taskCount() async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM tasks'),
        ) ??
        0;
  }

  // --------------------------------------------------------------- Sessions

  Future<int> insertSession(Session session) async {
    final db = await database;
    return db.insert('sessions', session.toMap());
  }

  /// History list data — every session joined with its task name,
  /// newest first.
  Future<List<SessionView>> getAllSessionViews() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT s.*, t.name AS task_name, p.name AS parent_name
      FROM sessions s
      JOIN tasks t ON t.id = s.task_id
      LEFT JOIN tasks p ON p.id = t.parent_id
      ORDER BY s.start_time DESC
    ''');
    return rows.map(SessionView.fromMap).toList();
  }

  Future<int> deleteSession(int id) async {
    final db = await database;
    return db.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> sessionCount() async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM sessions'),
        ) ??
        0;
  }

  // -------------------------------------------------- Active-session snapshot

  /// Upserts the single in-flight-session row (id is forced to 1).
  Future<void> saveActiveSession(Map<String, Object?> row) async {
    final db = await database;
    await db.insert(
      'active_session',
      {...row, 'id': 1},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Object?>?> getActiveSession() async {
    final db = await database;
    final rows = await db.query('active_session', where: 'id = 1', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> clearActiveSession() async {
    final db = await database;
    await db.delete('active_session', where: 'id = 1');
  }

  // -------------------------------------------------------------- Analytics

  /// Total active focus seconds for a single day ("YYYY-MM-DD").
  Future<int> focusSecondsForDate(String dateString) async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT SUM(active_duration_seconds) FROM sessions WHERE date_string = ?',
          [dateString],
        )) ??
        0;
  }

  /// Total active focus seconds on/after a day (inclusive). "YYYY-MM-DD"
  /// sorts lexicographically, so a string `>=` is a valid date range.
  Future<int> focusSecondsSince(String startDateString) async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT SUM(active_duration_seconds) FROM sessions WHERE date_string >= ?',
          [startDateString],
        )) ??
        0;
  }

  Future<int> todayFocusSeconds() => focusSecondsForDate(_todayString());

  /// Last 7 calendar days including today.
  Future<int> weeklyFocusSeconds() => focusSecondsSince(
      _dayString(_todayMidnight().subtract(const Duration(days: 6))));

  /// Number of sessions recorded on a given day.
  Future<int> sessionCountForDate(String dateString) async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM sessions WHERE date_string = ?',
          [dateString],
        )) ??
        0;
  }

  Future<int> todaySessionCount() => sessionCountForDate(_todayString());

  /// Average net active seconds per session in the range (0 if none).
  Future<int> averageSessionSeconds(AnalyticsRange range) async {
    final db = await database;
    final (String where, List<Object?> args) =
        _rangeClause(range, 'date_string');
    final rows = await db.rawQuery(
      'SELECT AVG(active_duration_seconds) AS avg FROM sessions $where',
      args,
    );
    final v = rows.first['avg'];
    if (v == null) return 0;
    return (v as num).round();
  }

  /// Per-task totals for the given range, biggest first, zero-totals excluded.
  Future<List<TaskTotal>> taskBreakdown(AnalyticsRange range) async {
    final db = await database;
    final (String where, List<Object?> args) =
        _rangeClause(range, 's.date_string');
    final rows = await db.rawQuery('''
      SELECT CASE WHEN p.name IS NULL THEN t.name
                  ELSE p.name || ' › ' || t.name END AS task_name,
             SUM(s.active_duration_seconds) AS total
      FROM sessions s
      JOIN tasks t ON t.id = s.task_id
      LEFT JOIN tasks p ON p.id = t.parent_id
      $where
      GROUP BY s.task_id
      HAVING total > 0
      ORDER BY total DESC
    ''', args);
    return rows
        .map((r) => TaskTotal(
              taskName: r['task_name'] as String,
              totalActiveSeconds: (r['total'] as int?) ?? 0,
            ))
        .toList();
  }

  /// Focus seconds per day for the last 7 calendar days, oldest → newest,
  /// with empty days filled as zero (so the chart always has 7 bars).
  Future<List<DailyTotal>> dailyTotalsLast7Days() async {
    final db = await database;
    final start = _todayMidnight().subtract(const Duration(days: 6));
    final rows = await db.rawQuery('''
      SELECT date_string, SUM(active_duration_seconds) AS total
      FROM sessions
      WHERE date_string >= ?
      GROUP BY date_string
    ''', [_dayString(start)]);

    final byDay = <String, int>{
      for (final r in rows)
        (r['date_string'] as String): ((r['total'] as int?) ?? 0),
    };

    return List<DailyTotal>.generate(7, (i) {
      final day = _dayString(start.add(Duration(days: i)));
      return DailyTotal(dateString: day, totalActiveSeconds: byDay[day] ?? 0);
    });
  }

  // ---------------------------------------------------------------- Helpers

  (String, List<Object?>) _rangeClause(AnalyticsRange range, String column) {
    switch (range) {
      case AnalyticsRange.today:
        return ('WHERE $column = ?', [_todayString()]);
      case AnalyticsRange.week:
        final start =
            _dayString(_todayMidnight().subtract(const Duration(days: 6)));
        return ('WHERE $column >= ?', [start]);
      case AnalyticsRange.allTime:
        return ('', const []);
    }
  }

  DateTime _todayMidnight() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String _todayString() => _dayString(DateTime.now());

  String _dayString(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// For tests / teardown.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

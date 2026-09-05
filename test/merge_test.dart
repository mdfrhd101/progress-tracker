import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:progress_tracker/data/database_helper.dart';
import 'package:progress_tracker/data/models/session.dart';
import 'package:progress_tracker/data/models/task.dart';

/// Verifies cross-device merge: exporting from one DB and merging into another
/// adds missing tasks/sessions by uid, never duplicates, and re-linking a
/// merge is idempotent.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.databasePathOverride = inMemoryDatabasePath;
  });

  test('export/merge unions by uid and is idempotent', () async {
    final db = DatabaseHelper.instance;
    await db.close();

    // --- Device A: add a task with a sub-task and two sessions ---
    final cloud = await db.insertTask(Task.create('CloudA'));
    final py = await db.insertTask(Task.create('PythonA', parentId: cloud));
    final today = Session.dateStringFrom(DateTime.now().millisecondsSinceEpoch);
    Session s(int taskId, int secs) => Session(
          taskId: taskId,
          startTime: 1,
          endTime: 2,
          activeDurationSeconds: secs,
          breakDurationSeconds: 0,
          isDeepFocus: false,
          dateString: today,
        );
    await db.insertSession(s(cloud, 600));
    await db.insertSession(s(py, 1200));

    final exportA = await db.exportData();
    expect((exportA['tasks'] as List).length, greaterThanOrEqualTo(2));

    // --- Device B: a fresh DB (its own seeded defaults) merges A's export ---
    await db.close();
    DatabaseHelper.databasePathOverride = inMemoryDatabasePath; // new memory
    final (tAdded, sAdded) = await db.mergeData(exportA);
    expect(tAdded, greaterThanOrEqualTo(2)); // CloudA + PythonA
    expect(sAdded, 2);

    // Sub-task parent link survived the merge (path shows "CloudA › PythonA").
    final views = await db.getAllSessionViews();
    expect(views.map((v) => v.displayName), contains('CloudA › PythonA'));

    // Merging the SAME export again adds nothing (idempotent).
    final (t2, s2) = await db.mergeData(exportA);
    expect(t2, 0);
    expect(s2, 0);
  });
}

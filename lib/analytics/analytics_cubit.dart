import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/database_helper.dart';
import '../data/models/session.dart';
import '../data/models/task.dart';
import 'analytics_state.dart';

/// Loads and refreshes all analytics/history data from SQLite.
class AnalyticsCubit extends Cubit<AnalyticsState> {
  final DatabaseHelper _db;

  AnalyticsCubit({DatabaseHelper? db})
      : _db = db ?? DatabaseHelper.instance,
        super(const AnalyticsState());

  /// Recomputes every metric. Called on tab focus and after deletes/undo.
  Future<void> load() async {
    emit(state.copyWith(loading: true));
    final results = await Future.wait([
      _db.todayFocusSeconds(),
      _db.weeklyFocusSeconds(),
      _db.todaySessionCount(),
      _db.averageSessionSeconds(AnalyticsRange.week),
      _db.taskBreakdown(state.filter),
      _db.dailyTotalsLast7Days(),
      _db.getAllSessionViews(),
      _db.getAllTasks(),
      _db.taskOwnTotals(),
    ]);
    if (isClosed) return;
    emit(AnalyticsState(
      loading: false,
      todaySeconds: results[0] as int,
      weekSeconds: results[1] as int,
      todaySessionCount: results[2] as int,
      avgSessionSecondsWeek: results[3] as int,
      filter: state.filter,
      breakdown: results[4] as List<TaskTotal>,
      trend: results[5] as List<DailyTotal>,
      history: results[6] as List<SessionView>,
      tasks: results[7] as List<Task>,
      totals: results[8] as Map<int, int>,
    ));
  }

  Future<void> setFilter(AnalyticsRange range) async {
    if (range == state.filter) return;
    final breakdown = await _db.taskBreakdown(range);
    if (isClosed) return;
    emit(state.copyWith(filter: range, breakdown: breakdown));
  }

  Future<void> deleteSession(int id) async {
    await _db.deleteSession(id);
    await load();
  }

  /// Undo for a swipe-delete: re-inserts the exact record (same id).
  Future<void> restoreSession(Session session) async {
    await _db.insertSession(session);
    await load();
  }
}

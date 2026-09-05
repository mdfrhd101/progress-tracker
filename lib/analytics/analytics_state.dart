import 'package:equatable/equatable.dart';

import '../data/database_helper.dart';
import '../data/models/session.dart';
import '../data/models/task.dart';

class AnalyticsState extends Equatable {
  final bool loading;
  final int todaySeconds;
  final int weekSeconds;
  final int todaySessionCount;
  final int avgSessionSecondsWeek; // average net focus per session, last 7 days
  final AnalyticsRange filter; // drives the task breakdown
  final List<TaskTotal> breakdown;
  final List<DailyTotal> trend; // last 7 days, oldest -> newest
  final List<SessionView> history; // newest first

  /// For the Targets card: every task + all-time seconds recorded directly
  /// on each task id (parent progress = own + children).
  final List<Task> tasks;
  final Map<int, int> totals;

  const AnalyticsState({
    this.loading = true,
    this.todaySeconds = 0,
    this.weekSeconds = 0,
    this.todaySessionCount = 0,
    this.avgSessionSecondsWeek = 0,
    this.filter = AnalyticsRange.today,
    this.breakdown = const [],
    this.trend = const [],
    this.history = const [],
    this.tasks = const [],
    this.totals = const {},
  });

  int get breakdownTotal =>
      breakdown.fold(0, (sum, t) => sum + t.totalActiveSeconds);

  /// Tasks that have a target, with (task, path, total, progress 0..1).
  List<TargetProgress> get targets {
    final out = <TargetProgress>[];
    for (final t in tasks) {
      if (!t.hasTarget) continue;
      var total = totals[t.id] ?? 0;
      String path = t.name;
      if (t.parentId == null) {
        for (final c in tasks) {
          if (c.parentId == t.id) total += totals[c.id] ?? 0;
        }
      } else {
        for (final p in tasks) {
          if (p.id == t.parentId) {
            path = '${p.name} › ${t.name}';
            break;
          }
        }
      }
      final f = total / t.targetSeconds!;
      out.add(TargetProgress(
        task: t,
        path: path,
        totalSeconds: total,
        fraction: f < 0 ? 0 : (f > 1 ? 1 : f),
      ));
    }
    out.sort((a, b) => b.fraction.compareTo(a.fraction));
    return out;
  }

  AnalyticsState copyWith({
    bool? loading,
    int? todaySeconds,
    int? weekSeconds,
    int? todaySessionCount,
    int? avgSessionSecondsWeek,
    AnalyticsRange? filter,
    List<TaskTotal>? breakdown,
    List<DailyTotal>? trend,
    List<SessionView>? history,
    List<Task>? tasks,
    Map<int, int>? totals,
  }) {
    return AnalyticsState(
      loading: loading ?? this.loading,
      todaySeconds: todaySeconds ?? this.todaySeconds,
      weekSeconds: weekSeconds ?? this.weekSeconds,
      todaySessionCount: todaySessionCount ?? this.todaySessionCount,
      avgSessionSecondsWeek:
          avgSessionSecondsWeek ?? this.avgSessionSecondsWeek,
      filter: filter ?? this.filter,
      breakdown: breakdown ?? this.breakdown,
      trend: trend ?? this.trend,
      history: history ?? this.history,
      tasks: tasks ?? this.tasks,
      totals: totals ?? this.totals,
    );
  }

  @override
  List<Object?> get props => [
        loading,
        todaySeconds,
        weekSeconds,
        todaySessionCount,
        avgSessionSecondsWeek,
        filter,
        breakdown,
        trend,
        history,
        tasks,
        totals,
      ];
}

class TargetProgress extends Equatable {
  final Task task;
  final String path;
  final int totalSeconds;
  final double fraction;

  const TargetProgress({
    required this.task,
    required this.path,
    required this.totalSeconds,
    required this.fraction,
  });

  @override
  List<Object?> get props => [task, path, totalSeconds, fraction];
}

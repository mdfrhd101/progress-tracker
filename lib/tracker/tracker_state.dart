import 'package:equatable/equatable.dart';

import '../data/models/task.dart';

enum TrackerStatus { idle, inProgress, onBreak }

/// Immutable snapshot of the tracker. All elapsed values are DERIVED from
/// epoch-ms timestamps against [nowMs], so the display can never drift while
/// backgrounded — it is recomputed from wall-clock time, not accumulated ticks.
class TrackerState extends Equatable {
  final TrackerStatus status;
  final List<Task> tasks; // full two-level tree, flat
  final Task? selectedTask;

  /// All-time focus seconds recorded directly on each task (id -> seconds).
  /// Used for target progress; parent totals include children (see
  /// [totalSecondsOf]).
  final Map<int, int> totals;

  final int startTimeMs; // session start (0 when idle)
  final int accumulatedBreakMs; // sum of completed breaks
  final int
      currentBreakStartMs; // start of the ongoing break (0 if not on break)
  final bool isDeepFocus; // DND engaged for this session

  final int nowMs; // ticks every second while running (drives the display)

  /// Context shown on the idle screen so the home tab is never "empty".
  final int todayFocusSeconds;
  final int todaySessionCount;

  final String? errorMessage; // transient (e.g. duplicate task name)

  const TrackerState({
    required this.status,
    required this.tasks,
    required this.selectedTask,
    this.totals = const {},
    required this.startTimeMs,
    required this.accumulatedBreakMs,
    required this.currentBreakStartMs,
    required this.isDeepFocus,
    required this.nowMs,
    this.todayFocusSeconds = 0,
    this.todaySessionCount = 0,
    this.errorMessage,
  });

  factory TrackerState.initial() => const TrackerState(
        status: TrackerStatus.idle,
        tasks: [],
        selectedTask: null,
        startTimeMs: 0,
        accumulatedBreakMs: 0,
        currentBreakStartMs: 0,
        isDeepFocus: false,
        nowMs: 0,
      );

  bool get isIdle => status == TrackerStatus.idle;
  bool get isRunning => status == TrackerStatus.inProgress;
  bool get isOnBreak => status == TrackerStatus.onBreak;

  // ------------------------------------------------------------ Task tree

  List<Task> get rootTasks => tasks.where((t) => t.parentId == null).toList();

  List<Task> childrenOf(int parentId) =>
      tasks.where((t) => t.parentId == parentId).toList();

  Task? parentOf(Task t) {
    if (t.parentId == null) return null;
    for (final p in tasks) {
      if (p.id == t.parentId) return p;
    }
    return null;
  }

  /// "Cloud › Python" for a sub-task, "Cloud" for a top-level task.
  String pathOf(Task t) {
    final p = parentOf(t);
    return p == null ? t.name : '${p.name} › ${t.name}';
  }

  /// All-time seconds for a task INCLUDING its sub-tasks (+ the live session
  /// if it belongs to this task or one of its children).
  int totalSecondsOf(Task t) {
    var sum = totals[t.id] ?? 0;
    if (t.id != null) {
      for (final c in childrenOf(t.id!)) {
        sum += totals[c.id] ?? 0;
      }
    }
    if (!isIdle && selectedTask != null) {
      final live = selectedTask!;
      if (live.id == t.id || live.parentId == t.id) sum += activeSeconds;
    }
    return sum;
  }

  /// 0..1 progress toward the task's target (null when no target).
  double? progressOf(Task t) {
    if (!t.hasTarget) return null;
    final f = totalSecondsOf(t) / t.targetSeconds!;
    return f < 0 ? 0 : (f > 1 ? 1 : f);
  }

  // ------------------------------------------------------------ Timer math

  /// Net active seconds: (now - start) - all break time (including the break
  /// currently in progress). Never negative.
  int get activeSeconds {
    if (isIdle || startTimeMs == 0) return 0;
    var breakMs = accumulatedBreakMs;
    if (isOnBreak && currentBreakStartMs != 0) {
      breakMs += nowMs - currentBreakStartMs;
    }
    final ms = (nowMs - startTimeMs) - breakMs;
    return ms <= 0 ? 0 : ms ~/ 1000;
  }

  /// Total break seconds so far (for the on-break display / persisted record).
  int get breakSeconds {
    var breakMs = accumulatedBreakMs;
    if (isOnBreak && currentBreakStartMs != 0) {
      breakMs += nowMs - currentBreakStartMs;
    }
    return breakMs <= 0 ? 0 : breakMs ~/ 1000;
  }

  TrackerState copyWith({
    TrackerStatus? status,
    List<Task>? tasks,
    Task? selectedTask,
    bool clearSelectedTask = false,
    Map<int, int>? totals,
    int? startTimeMs,
    int? accumulatedBreakMs,
    int? currentBreakStartMs,
    bool? isDeepFocus,
    int? nowMs,
    int? todayFocusSeconds,
    int? todaySessionCount,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TrackerState(
      status: status ?? this.status,
      tasks: tasks ?? this.tasks,
      selectedTask:
          clearSelectedTask ? null : (selectedTask ?? this.selectedTask),
      totals: totals ?? this.totals,
      startTimeMs: startTimeMs ?? this.startTimeMs,
      accumulatedBreakMs: accumulatedBreakMs ?? this.accumulatedBreakMs,
      currentBreakStartMs: currentBreakStartMs ?? this.currentBreakStartMs,
      isDeepFocus: isDeepFocus ?? this.isDeepFocus,
      nowMs: nowMs ?? this.nowMs,
      todayFocusSeconds: todayFocusSeconds ?? this.todayFocusSeconds,
      todaySessionCount: todaySessionCount ?? this.todaySessionCount,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        tasks,
        selectedTask,
        totals,
        startTimeMs,
        accumulatedBreakMs,
        currentBreakStartMs,
        isDeepFocus,
        nowMs,
        todayFocusSeconds,
        todaySessionCount,
        errorMessage,
      ];
}

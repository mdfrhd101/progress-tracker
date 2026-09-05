import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/database_helper.dart';
import '../data/models/session.dart';
import '../data/models/task.dart';

/// One concurrently-running timer in multitasking mode.
class RunningTimer extends Equatable {
  final int rowId; // active_multi.id
  final Task task;
  final int startTimeMs;
  final int accumulatedBreakMs;
  final int currentBreakStartMs; // 0 when running
  final bool onBreak;

  const RunningTimer({
    required this.rowId,
    required this.task,
    required this.startTimeMs,
    required this.accumulatedBreakMs,
    required this.currentBreakStartMs,
    required this.onBreak,
  });

  int activeSeconds(int nowMs) {
    var breakMs = accumulatedBreakMs;
    if (onBreak && currentBreakStartMs != 0) {
      breakMs += nowMs - currentBreakStartMs;
    }
    final ms = (nowMs - startTimeMs) - breakMs;
    return ms <= 0 ? 0 : ms ~/ 1000;
  }

  int breakSeconds(int nowMs) {
    var breakMs = accumulatedBreakMs;
    if (onBreak && currentBreakStartMs != 0) {
      breakMs += nowMs - currentBreakStartMs;
    }
    return breakMs <= 0 ? 0 : breakMs ~/ 1000;
  }

  RunningTimer copyWith({
    int? accumulatedBreakMs,
    int? currentBreakStartMs,
    bool? onBreak,
  }) =>
      RunningTimer(
        rowId: rowId,
        task: task,
        startTimeMs: startTimeMs,
        accumulatedBreakMs: accumulatedBreakMs ?? this.accumulatedBreakMs,
        currentBreakStartMs: currentBreakStartMs ?? this.currentBreakStartMs,
        onBreak: onBreak ?? this.onBreak,
      );

  @override
  List<Object?> get props => [
        rowId,
        task,
        startTimeMs,
        accumulatedBreakMs,
        currentBreakStartMs,
        onBreak
      ];
}

class MultitaskingState extends Equatable {
  final List<Task> tasks; // full task tree (for the picker)
  final List<RunningTimer> running; // concurrent timers
  final int nowMs;

  const MultitaskingState({
    this.tasks = const [],
    this.running = const [],
    this.nowMs = 0,
  });

  /// Tasks not already running here (so the picker can't double-start one).
  List<Task> get startableTasks {
    final busy = running.map((r) => r.task.id).toSet();
    return tasks.where((t) => !busy.contains(t.id)).toList();
  }

  MultitaskingState copyWith({
    List<Task>? tasks,
    List<RunningTimer>? running,
    int? nowMs,
  }) =>
      MultitaskingState(
        tasks: tasks ?? this.tasks,
        running: running ?? this.running,
        nowMs: nowMs ?? this.nowMs,
      );

  @override
  List<Object?> get props => [tasks, running, nowMs];
}

/// Runs any number of task timers at the same time. Each timer's active
/// duration is computed independently from epoch timestamps, so nothing drifts
/// and everything survives a background/kill (mirrored in `active_multi`).
/// Stopping a timer writes a normal `sessions` row, so history/analytics/targets
/// include multitasking time automatically.
class MultitaskingCubit extends Cubit<MultitaskingState> {
  final DatabaseHelper _db;
  Timer? _ticker;

  MultitaskingCubit({DatabaseHelper? db})
      : _db = db ?? DatabaseHelper.instance,
        super(const MultitaskingState());

  int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Reload tasks and restore any timers still running from a previous run.
  Future<void> refresh() async {
    final tasks = await _db.getAllTasks();
    final rows = await _db.getAllMulti();
    final running = <RunningTimer>[];
    for (final r in rows) {
      final taskId = r['task_id'] as int;
      Task? t;
      for (final x in tasks) {
        if (x.id == taskId) {
          t = x;
          break;
        }
      }
      if (t == null) continue; // task deleted → row cascaded away already
      running.add(RunningTimer(
        rowId: r['id'] as int,
        task: t,
        startTimeMs: r['start_time'] as int,
        accumulatedBreakMs: r['accumulated_break_ms'] as int,
        currentBreakStartMs: r['current_break_start_ms'] as int,
        onBreak: (r['status'] as String) == 'break',
      ));
    }
    if (isClosed) return;
    emit(state.copyWith(tasks: tasks, running: running, nowMs: _now));
    _syncTicker();
  }

  Future<void> startTask(Task task) async {
    if (task.id == null) return;
    if (state.running.any((r) => r.task.id == task.id)) return; // no duplicates
    final start = _now;
    final rowId = await _db.insertMulti({
      'task_id': task.id!,
      'start_time': start,
      'accumulated_break_ms': 0,
      'current_break_start_ms': 0,
      'status': 'running',
    });
    final timer = RunningTimer(
      rowId: rowId,
      task: task,
      startTimeMs: start,
      accumulatedBreakMs: 0,
      currentBreakStartMs: 0,
      onBreak: false,
    );
    emit(state.copyWith(running: [...state.running, timer], nowMs: start));
    _syncTicker();
  }

  Future<void> takeBreak(int rowId) => _mutate(rowId, (t) {
        if (t.onBreak) return t;
        return t.copyWith(onBreak: true, currentBreakStartMs: _now);
      });

  Future<void> resume(int rowId) => _mutate(rowId, (t) {
        if (!t.onBreak) return t;
        final added = _now - t.currentBreakStartMs;
        return t.copyWith(
          onBreak: false,
          accumulatedBreakMs: t.accumulatedBreakMs + added,
          currentBreakStartMs: 0,
        );
      });

  /// Stops one timer, saving a session row (unless [save] is false).
  Future<void> stop(int rowId, {bool save = true}) async {
    final t = state.running.where((r) => r.rowId == rowId).firstOrNull;
    if (t == null) return;
    final end = _now;
    var breakMs = t.accumulatedBreakMs;
    if (t.onBreak && t.currentBreakStartMs != 0) {
      breakMs += end - t.currentBreakStartMs;
    }
    final activeMs = (end - t.startTimeMs) - breakMs;
    final activeSeconds = activeMs <= 0 ? 0 : activeMs ~/ 1000;
    final breakSeconds = breakMs <= 0 ? 0 : breakMs ~/ 1000;

    if (save && t.task.id != null) {
      await _db.insertSession(Session(
        taskId: t.task.id!,
        startTime: t.startTimeMs,
        endTime: end,
        activeDurationSeconds: activeSeconds,
        breakDurationSeconds: breakSeconds,
        isDeepFocus: false, // multitasking has no per-task DND
        dateString: Session.dateStringFrom(t.startTimeMs),
      ));
    }
    await _db.deleteMulti(rowId);
    emit(state.copyWith(
      running: state.running.where((r) => r.rowId != rowId).toList(),
    ));
    _syncTicker();
  }

  Future<void> stopAll() async {
    for (final r in [...state.running]) {
      await stop(r.rowId, save: true);
    }
  }

  // ------------------------------------------------------------------ helpers

  Future<void> _mutate(int rowId, RunningTimer Function(RunningTimer) f) async {
    final list = <RunningTimer>[];
    RunningTimer? changed;
    for (final r in state.running) {
      if (r.rowId == rowId) {
        changed = f(r);
        list.add(changed);
      } else {
        list.add(r);
      }
    }
    if (changed == null) return;
    emit(state.copyWith(running: list, nowMs: _now));
    await _db.updateMulti(rowId, {
      'task_id': changed.task.id,
      'start_time': changed.startTimeMs,
      'accumulated_break_ms': changed.accumulatedBreakMs,
      'current_break_start_ms': changed.currentBreakStartMs,
      'status': changed.onBreak ? 'break' : 'running',
    });
  }

  void _syncTicker() {
    final anyRunning = state.running.any((r) => !r.onBreak);
    if (anyRunning && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!isClosed) emit(state.copyWith(nowMs: _now));
      });
    } else if (!state.running.any((r) => true)) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Future<void> close() {
    _ticker?.cancel();
    return super.close();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

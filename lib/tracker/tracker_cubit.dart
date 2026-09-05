import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;

import '../data/database_helper.dart';
import '../data/models/session.dart';
import '../data/models/task.dart';
import '../services/dnd_service.dart';
import 'tracker_state.dart';

/// Owns the focus-session state machine, the task tree and the
/// timestamp-based timer.
///
/// Flow:  Idle -> (Start) -> In Progress <-> (Break/Resume) On Break -> (End) -> Idle
///
/// The displayed time is recomputed from epoch timestamps on every tick, so it
/// stays correct across screen-off/background. The in-flight session is mirrored
/// to SQLite so even a process kill can be restored on next launch.
class TrackerCubit extends Cubit<TrackerState> {
  static const String _prefSelectedTask = 'selected_task_id';

  final DatabaseHelper _db;
  final DndService _dnd;
  Timer? _ticker;

  TrackerCubit({DatabaseHelper? db, DndService dnd = const DndService()})
      : _db = db ?? DatabaseHelper.instance,
        _dnd = dnd,
        super(TrackerState.initial());

  DndService get dnd => _dnd;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  // ------------------------------------------------------------------ Bootstrap

  /// Loads tasks, restores the last selected task, and restores any in-flight
  /// session left over from a previous run (e.g. killed mid-timer).
  Future<void> init() async {
    final tasks = await _db.getAllTasks();
    final active = await _db.getActiveSession();

    if (active == null) {
      final remembered = await _db.getPref(_prefSelectedTask);
      final rememberedId = remembered == null ? null : int.tryParse(remembered);
      Task? selected;
      for (final t in tasks) {
        if (t.id == rememberedId) {
          selected = t;
          break;
        }
      }
      selected ??= tasks.isNotEmpty ? tasks.first : null;
      emit(state.copyWith(tasks: tasks, selectedTask: selected));
      await _refreshStats();
      return;
    }

    // Restore the running/paused session.
    final restoredStatus = _statusFromString(active['status'] as String);
    Task? task;
    for (final t in tasks) {
      if (t.id == active['task_id'] as int) {
        task = t;
        break;
      }
    }

    emit(state.copyWith(
      tasks: tasks,
      selectedTask: task,
      status: restoredStatus,
      startTimeMs: active['start_time'] as int,
      accumulatedBreakMs: active['accumulated_break_ms'] as int,
      currentBreakStartMs: active['current_break_start_ms'] as int,
      isDeepFocus: (active['is_deep_focus'] as int) == 1,
      nowMs: _now,
    ));
    _startTicker();
    await _refreshStats();
  }

  // ---------------------------------------------------------------------- Tasks

  Future<void> selectTask(Task task) async {
    if (!state.isIdle) return; // can't switch mid-session
    emit(state.copyWith(selectedTask: task));
    if (task.id != null) await _db.setPref(_prefSelectedTask, '${task.id}');
  }

  /// Adds a task (top-level, or a sub-task when [parentId] is given) with an
  /// optional target in hours. Surfaces a friendly error on duplicate names.
  Future<bool> addTask(String rawName,
      {int? parentId, double? targetHours}) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      emit(state.copyWith(errorMessage: 'Task name cannot be empty'));
      return false;
    }
    try {
      await _db.insertTask(Task.create(
        name,
        parentId: parentId,
        targetSeconds: _hoursToSeconds(targetHours),
      ));
      final tasks = await _db.getAllTasks();
      final added = tasks.firstWhere((t) => t.name == name);
      emit(state.copyWith(
        tasks: tasks,
        selectedTask: state.isIdle ? added : null,
        clearError: true,
      ));
      if (state.isIdle && added.id != null) {
        await _db.setPref(_prefSelectedTask, '${added.id}');
      }
      return true;
    } on DatabaseException {
      emit(state.copyWith(errorMessage: 'A task named "$name" already exists'));
      return false;
    }
  }

  /// Renames a task and/or changes its target (hours; null/0 clears it).
  Future<bool> updateTask(Task task,
      {required String rawName, double? targetHours}) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      emit(state.copyWith(errorMessage: 'Task name cannot be empty'));
      return false;
    }
    final secs = _hoursToSeconds(targetHours);
    final updated = task.copyWith(
      name: name,
      targetSeconds: secs,
      clearTarget: secs == null,
    );
    try {
      await _db.updateTask(updated);
      final tasks = await _db.getAllTasks();
      Task? selected = state.selectedTask;
      if (selected?.id == task.id) selected = updated;
      emit(state.copyWith(
          tasks: tasks, selectedTask: selected, clearError: true));
      return true;
    } on DatabaseException {
      emit(state.copyWith(errorMessage: 'A task named "$name" already exists'));
      return false;
    }
  }

  /// Deletes a task, its sub-tasks and all their sessions (cascade). Idle only.
  Future<void> deleteTask(Task task) async {
    if (!state.isIdle || task.id == null) return;
    await _db.deleteTask(task.id!);
    final tasks = await _db.getAllTasks();
    Task? selected = state.selectedTask;
    final selectedGone = selected == null ||
        selected.id == task.id ||
        selected.parentId == task.id;
    if (selectedGone) {
      selected = tasks.isNotEmpty ? tasks.first : null;
    }
    emit(state.copyWith(
      tasks: tasks,
      selectedTask: selected,
      clearSelectedTask: selected == null,
    ));
    if (selected?.id != null) {
      await _db.setPref(_prefSelectedTask, '${selected!.id}');
    }
    await _refreshStats(); // cascaded sessions change totals
  }

  void clearError() => emit(state.copyWith(clearError: true));

  // ------------------------------------------------------------------ DND perms

  Future<bool> isDndPermissionGranted() => _dnd.isPermissionGranted();

  Future<void> openDndSettings() => _dnd.openSettings();

  // ------------------------------------------------------- Session transitions

  /// Starts a session for the selected task. If [deepFocus] is true, DND is
  /// engaged now (permission is assumed already granted — the UI checks first).
  Future<void> startSession({required bool deepFocus}) async {
    final task = state.selectedTask;
    if (task == null || !state.isIdle) return;

    final start = _now;
    emit(state.copyWith(
      status: TrackerStatus.inProgress,
      startTimeMs: start,
      accumulatedBreakMs: 0,
      currentBreakStartMs: 0,
      isDeepFocus: deepFocus,
      nowMs: start,
      clearError: true,
    ));

    if (deepFocus) {
      await _dnd.enable();
    }
    await _persistActive();
    _startTicker();
  }

  Future<void> takeBreak() async {
    if (!state.isRunning) return;
    emit(state.copyWith(
      status: TrackerStatus.onBreak,
      currentBreakStartMs: _now,
      nowMs: _now,
    ));
    await _persistActive();
  }

  Future<void> resumeSession() async {
    if (!state.isOnBreak) return;
    final addedBreak = _now - state.currentBreakStartMs;
    emit(state.copyWith(
      status: TrackerStatus.inProgress,
      accumulatedBreakMs: state.accumulatedBreakMs + addedBreak,
      currentBreakStartMs: 0,
      nowMs: _now,
    ));
    await _persistActive();
  }

  /// Ends the session. With [save] true the record is persisted; false
  /// discards it (accidental start). DND is restored either way.
  Future<void> endSession({bool save = true}) async {
    if (state.isIdle) return;
    final task = state.selectedTask;
    _stopTicker();

    final end = _now;
    // Fold any in-progress break into the total.
    var breakMs = state.accumulatedBreakMs;
    if (state.isOnBreak && state.currentBreakStartMs != 0) {
      breakMs += end - state.currentBreakStartMs;
    }
    final activeMs = (end - state.startTimeMs) - breakMs;
    final activeSeconds = activeMs <= 0 ? 0 : activeMs ~/ 1000;
    final breakSeconds = breakMs <= 0 ? 0 : breakMs ~/ 1000;

    if (save && task?.id != null) {
      await _db.insertSession(Session(
        taskId: task!.id!,
        startTime: state.startTimeMs,
        endTime: end,
        activeDurationSeconds: activeSeconds,
        breakDurationSeconds: breakSeconds,
        isDeepFocus: state.isDeepFocus,
        dateString: Session.dateStringFrom(state.startTimeMs),
      ));
    }

    if (state.isDeepFocus) {
      await _dnd.disable(); // restore normal ringer
    }
    await _db.clearActiveSession();

    emit(state.copyWith(
      status: TrackerStatus.idle,
      startTimeMs: 0,
      accumulatedBreakMs: 0,
      currentBreakStartMs: 0,
      isDeepFocus: false,
      nowMs: 0,
    ));
    await _refreshStats();
  }

  // -------------------------------------------------------------------- Helpers

  int? _hoursToSeconds(double? hours) {
    if (hours == null || hours <= 0) return null;
    return (hours * 3600).round();
  }

  /// Today's summary + per-task all-time totals (target progress).
  Future<void> _refreshStats() async {
    final secs = await _db.todayFocusSeconds();
    final count = await _db.todaySessionCount();
    final totals = await _db.taskOwnTotals();
    if (isClosed) return;
    emit(state.copyWith(
      todayFocusSeconds: secs,
      todaySessionCount: count,
      totals: totals,
    ));
  }

  Future<void> _persistActive() async {
    final task = state.selectedTask;
    if (task?.id == null) return;
    await _db.saveActiveSession({
      'task_id': task!.id!,
      'start_time': state.startTimeMs,
      'accumulated_break_ms': state.accumulatedBreakMs,
      'current_break_start_ms': state.currentBreakStartMs,
      'is_deep_focus': state.isDeepFocus ? 1 : 0,
      'status': state.status.name,
    });
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isClosed) emit(state.copyWith(nowMs: _now));
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  TrackerStatus _statusFromString(String s) => TrackerStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => TrackerStatus.inProgress,
      );

  @override
  Future<void> close() {
    _stopTicker();
    return super.close();
  }
}

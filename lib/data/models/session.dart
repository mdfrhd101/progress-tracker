import 'package:equatable/equatable.dart';

/// A completed focus session.
///
/// Maps 1:1 to the `sessions` table. Durations are stored in **seconds**;
/// timestamps in **epoch milliseconds**. `is_deep_focus` is 0/1 in SQLite,
/// exposed here as a bool.
///
///   Active Duration = (end_time - start_time) - total break duration
class Session extends Equatable {
  final int? id; // null until inserted
  final int taskId;
  final int startTime; // epoch ms
  final int endTime; // epoch ms
  final int activeDurationSeconds;
  final int breakDurationSeconds;
  final bool isDeepFocus; // true if DND was enabled for this session
  final String dateString; // "YYYY-MM-DD" (local day of start), indexed

  const Session({
    this.id,
    required this.taskId,
    required this.startTime,
    required this.endTime,
    required this.activeDurationSeconds,
    required this.breakDurationSeconds,
    required this.isDeepFocus,
    required this.dateString,
  });

  factory Session.fromMap(Map<String, Object?> map) => Session(
        id: map['id'] as int?,
        taskId: map['task_id'] as int,
        startTime: map['start_time'] as int,
        endTime: map['end_time'] as int,
        activeDurationSeconds: map['active_duration_seconds'] as int,
        breakDurationSeconds: map['break_duration_seconds'] as int,
        isDeepFocus: (map['is_deep_focus'] as int) == 1,
        dateString: map['date_string'] as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'task_id': taskId,
        'start_time': startTime,
        'end_time': endTime,
        'active_duration_seconds': activeDurationSeconds,
        'break_duration_seconds': breakDurationSeconds,
        'is_deep_focus': isDeepFocus ? 1 : 0,
        'date_string': dateString,
      };

  /// Builds the local "YYYY-MM-DD" key for a given epoch-ms timestamp.
  static String dateStringFrom(int epochMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  @override
  List<Object?> get props => [
        id,
        taskId,
        startTime,
        endTime,
        activeDurationSeconds,
        breakDurationSeconds,
        isDeepFocus,
        dateString,
      ];
}

/// A [Session] joined with its task (and parent task) name — the shape the
/// History list renders.
class SessionView extends Equatable {
  final Session session;
  final String taskName;
  final String? parentName; // set when the task is a sub-task

  const SessionView({
    required this.session,
    required this.taskName,
    this.parentName,
  });

  factory SessionView.fromMap(Map<String, Object?> map) => SessionView(
        session: Session.fromMap(map),
        taskName: map['task_name'] as String,
        parentName: map['parent_name'] as String?,
      );

  /// "Cloud › Python" for a sub-task, or just "Cloud".
  String get displayName =>
      parentName == null ? taskName : '$parentName › $taskName';

  @override
  List<Object?> get props => [session, taskName, parentName];
}

/// One row of the "task breakdown" analytics query.
class TaskTotal extends Equatable {
  final String taskName;
  final int totalActiveSeconds;

  const TaskTotal({required this.taskName, required this.totalActiveSeconds});

  @override
  List<Object?> get props => [taskName, totalActiveSeconds];
}

/// One bar of the 7-day trend chart: a calendar day and its focus seconds.
class DailyTotal extends Equatable {
  final String dateString; // "YYYY-MM-DD"
  final int totalActiveSeconds;

  const DailyTotal({required this.dateString, required this.totalActiveSeconds});

  @override
  List<Object?> get props => [dateString, totalActiveSeconds];
}

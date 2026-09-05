import 'package:equatable/equatable.dart';

/// A trackable activity. Two levels: a top-level task (parent_id NULL) may
/// own sub-tasks (parent_id = parent's id). Sessions can attach to either.
///
/// Maps 1:1 to the `tasks` table:
///   id             INTEGER PRIMARY KEY AUTOINCREMENT
///   name           TEXT UNIQUE NOT NULL
///   created_at     INTEGER NOT NULL   (epoch ms)
///   parent_id      INTEGER NULL       (FK tasks.id, cascade)
///   target_seconds INTEGER NULL       (goal; e.g. 100 h = 360000)
class Task extends Equatable {
  final int? id; // null until inserted (assigned by SQLite)
  final String name;
  final int createdAt; // epoch milliseconds
  final int? parentId; // null = top-level task
  final int? targetSeconds; // null = no target set

  const Task({
    this.id,
    required this.name,
    required this.createdAt,
    this.parentId,
    this.targetSeconds,
  });

  /// Convenience for creating a brand-new task stamped with "now".
  factory Task.create(String name, {int? parentId, int? targetSeconds}) => Task(
        name: name.trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
        parentId: parentId,
        targetSeconds: targetSeconds,
      );

  factory Task.fromMap(Map<String, Object?> map) => Task(
        id: map['id'] as int?,
        name: map['name'] as String,
        createdAt: map['created_at'] as int,
        parentId: map['parent_id'] as int?,
        targetSeconds: map['target_seconds'] as int?,
      );

  /// Row for INSERT/UPDATE. `id` is omitted when null so AUTOINCREMENT fires.
  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'created_at': createdAt,
        'parent_id': parentId,
        'target_seconds': targetSeconds,
      };

  bool get isSubtask => parentId != null;
  bool get hasTarget => targetSeconds != null && targetSeconds! > 0;

  /// Target expressed in hours (for display / editing).
  double? get targetHours => hasTarget ? targetSeconds! / 3600.0 : null;

  Task copyWith({
    int? id,
    String? name,
    int? createdAt,
    int? parentId,
    bool clearParent = false,
    int? targetSeconds,
    bool clearTarget = false,
  }) =>
      Task(
        id: id ?? this.id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
        parentId: clearParent ? null : (parentId ?? this.parentId),
        targetSeconds:
            clearTarget ? null : (targetSeconds ?? this.targetSeconds),
      );

  @override
  List<Object?> get props => [id, name, createdAt, parentId, targetSeconds];

  @override
  String toString() => 'Task(id: $id, name: $name, parent: $parentId)';
}

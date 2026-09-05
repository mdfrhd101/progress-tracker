import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/models/task.dart';
import '../theme/app_theme.dart';
import '../tracker/tracker_cubit.dart';
import '../tracker/tracker_state.dart';
import '../utils/formatters.dart';

/// Full task list: top-level tasks with their sub-tasks, all-time totals and
/// target progress. Tap a task to select it for tracking; use the ⋮ menu to
/// edit, add a sub-task or delete.
class TaskManagerScreen extends StatelessWidget {
  const TaskManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTaskEditor(context),
        backgroundColor: AppColors.focus,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Add Task'),
      ),
      body: BlocBuilder<TrackerCubit, TrackerState>(
        builder: (context, state) {
          final roots = state.rootTasks;
          if (roots.isEmpty) {
            return const Center(
              child: Text('No tasks yet — add one below.',
                  style: TextStyle(color: Colors.white38)),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (!state.isIdle)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'A session is running — finish it to switch or delete tasks.',
                    style: TextStyle(color: AppColors.breakAmber, fontSize: 12),
                  ),
                ),
              for (final root in roots) _TaskCard(root: root, state: state),
            ],
          );
        },
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Task root;
  final TrackerState state;
  const _TaskCard({required this.root, required this.state});

  @override
  Widget build(BuildContext context) {
    final children = state.childrenOf(root.id!);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TaskRow(task: root, state: state, isRoot: true),
          if (children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                children: [
                  const Divider(height: 8, color: Colors.white10),
                  for (final c in children)
                    _TaskRow(task: c, state: state, isRoot: false),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final Task task;
  final TrackerState state;
  final bool isRoot;
  const _TaskRow(
      {required this.task, required this.state, required this.isRoot});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TrackerCubit>();
    final selected = state.selectedTask?.id == task.id;
    final total = state.totalSecondsOf(task);
    final progress = state.progressOf(task);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: state.isIdle
          ? () {
              HapticFeedback.selectionClick();
              cubit.selectTask(task);
              Navigator.of(context).maybePop();
            }
          : null,
      child: Padding(
        padding: EdgeInsets.fromLTRB(isRoot ? 16 : 24, isRoot ? 14 : 10, 6,
            isRoot ? 12 : 10),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.focus : Colors.white24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          task.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isRoot ? 16 : 14,
                            fontWeight:
                                isRoot ? FontWeight.w700 : FontWeight.w600,
                            color: selected ? AppColors.focus : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        Formatters.human(total),
                        style: const TextStyle(
                            fontFamily: AppTheme.monoFont,
                            fontSize: 12,
                            color: Colors.white54),
                      ),
                    ],
                  ),
                  if (task.hasTarget) ...[
                    const SizedBox(height: 6),
                    _TargetBar(task: task, total: total, progress: progress!),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              onSelected: (v) => _onMenu(context, v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit / set target')),
                if (isRoot)
                  const PopupMenuItem(value: 'sub', child: Text('Add sub-task')),
                PopupMenuItem(
                  value: 'delete',
                  enabled: state.isIdle,
                  child: const Text('Delete',
                      style: TextStyle(color: AppColors.stopRed)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, String value) async {
    switch (value) {
      case 'edit':
        await showTaskEditor(context, existing: task);
        break;
      case 'sub':
        await showTaskEditor(context, parentId: task.id);
        break;
      case 'delete':
        await confirmDeleteTask(context, task, hasChildren: isRoot &&
            state.childrenOf(task.id!).isNotEmpty);
        break;
    }
  }
}

/// Thin progress bar with "12h / 100h · 12%".
class _TargetBar extends StatelessWidget {
  final Task task;
  final int total;
  final double progress;
  const _TargetBar(
      {required this.task, required this.total, required this.progress});

  @override
  Widget build(BuildContext context) {
    final done = progress >= 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: AppColors.surfaceHigh,
            valueColor: AlwaysStoppedAnimation<Color>(
                done ? AppColors.focus : AppColors.focus.withValues(alpha: 0.75)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${Formatters.human(total)} / ${_fmtHours(task.targetHours!)}'
          '  ·  ${(progress * 100).round()}%${done ? '  ✓' : ''}',
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }
}

String _fmtHours(double h) =>
    h == h.roundToDouble() ? '${h.round()}h' : '${h.toStringAsFixed(1)}h';

// ------------------------------------------------------------ Shared dialogs

/// Add (or edit) a task. When [existing] is null a new task is created —
/// as a sub-task if [parentId] is given, otherwise the dialog offers a parent
/// picker. Target is optional (hours).
Future<void> showTaskEditor(BuildContext context,
    {Task? existing, int? parentId}) async {
  final cubit = context.read<TrackerCubit>();
  final nameCtl = TextEditingController(text: existing?.name ?? '');
  final targetCtl = TextEditingController(
      text: existing?.targetHours == null
          ? ''
          : _fmtHours(existing!.targetHours!).replaceAll('h', ''));
  int? chosenParent = parentId ?? existing?.parentId;
  final roots = cubit.state.rootTasks
      .where((t) => t.id != existing?.id)
      .toList();
  final isEdit = existing != null;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(isEdit
            ? 'Edit Task'
            : (parentId != null ? 'Add Sub-task' : 'Add Task')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Python',
              ),
            ),
            const SizedBox(height: 12),
            if (!isEdit && parentId == null && roots.isNotEmpty)
              DropdownButtonFormField<int?>(
                initialValue: chosenParent,
                decoration: const InputDecoration(labelText: 'Under (optional)'),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('None — top-level task')),
                  for (final r in roots)
                    DropdownMenuItem<int?>(value: r.id, child: Text(r.name)),
                ],
                onChanged: (v) => setState(() => chosenParent = v),
              ),
            if (!isEdit && parentId == null && roots.isNotEmpty)
              const SizedBox(height: 12),
            TextField(
              controller: targetCtl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Target hours (optional)',
                hintText: 'e.g. 100',
                suffixText: 'h',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isEdit ? 'Save' : 'Add'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;

  final hours = double.tryParse(targetCtl.text.trim().replaceAll(',', '.'));
  if (isEdit) {
    await cubit.updateTask(existing, rawName: nameCtl.text, targetHours: hours);
  } else {
    await cubit.addTask(nameCtl.text,
        parentId: chosenParent, targetHours: hours);
  }
}

/// Confirms then deletes a task (and its sub-tasks / sessions).
Future<void> confirmDeleteTask(BuildContext context, Task task,
    {bool hasChildren = false}) async {
  final cubit = context.read<TrackerCubit>();
  HapticFeedback.mediumImpact();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "${task.name}"?'),
      content: Text(hasChildren
          ? 'Its sub-tasks and all their recorded sessions will be deleted too. '
              'This cannot be undone.'
          : 'All sessions recorded for this task will be deleted too. '
              'This cannot be undone.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.stopRed),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok == true) await cubit.deleteTask(task);
}

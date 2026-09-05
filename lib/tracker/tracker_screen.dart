import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../app_info.dart';
import '../data/models/task.dart';
import '../multitasking/multitasking_screen.dart';
import '../settings/settings_screen.dart';
import '../tasks/task_manager_screen.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'tracker_cubit.dart';
import 'tracker_state.dart';

/// Result returned by the start-confirmation sheet.
class _StartResult {
  final bool deepFocus;
  const _StartResult(this.deepFocus);
}

/// Result returned by the end-confirmation sheet.
enum _EndChoice { save, discard }

class TrackerScreen extends StatelessWidget {
  const TrackerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress Tracker',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      drawer: const _SideMenu(),
      body: BlocConsumer<TrackerCubit, TrackerState>(
        listenWhen: (a, b) => a.errorMessage != b.errorMessage,
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.errorMessage!)));
            context.read<TrackerCubit>().clearError();
          }
        },
        builder: (context, state) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SelectedTaskCard(state: state),
                  Expanded(child: _TimerDisplay(state: state)),
                  _ActionButtons(state: state),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ Sidebar

class _SideMenu extends StatelessWidget {
  const _SideMenu();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.timer, color: context.accent),
                  const SizedBox(width: 10),
                  const Text('Progress Tracker',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.checklist_rounded),
              title: const Text('Task List'),
              subtitle: const Text('Sub-tasks, targets, edit & delete',
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const TaskManagerScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Add Task'),
              onTap: () {
                Navigator.pop(context);
                showTaskEditor(context);
              },
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.dynamic_feed_rounded),
              title: const Text('Multitasking'),
              subtitle: const Text('Run several timers at once',
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const MultitaskingScreen()));
              },
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('Settings'),
              subtitle: const Text('Colour, font, text size, updates',
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('v${AppInfo.version}  ·  100% offline',
                  style: TextStyle(color: Colors.white30, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------ Selected-task card

class _SelectedTaskCard extends StatelessWidget {
  final TrackerState state;
  const _SelectedTaskCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final task = state.selectedTask;
    final enabled = state.isIdle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TASK',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(letterSpacing: 1.5, color: Colors.white54)),
        const SizedBox(height: 10),
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? () => _openPicker(context) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: task == null
                  ? Row(
                      children: [
                        Icon(Icons.add_circle_outline, color: context.accent),
                        const SizedBox(width: 10),
                        const Text('Tap to add your first task',
                            style: TextStyle(color: Colors.white70)),
                      ],
                    )
                  : _TaskSummary(task: task, state: state, enabled: enabled),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    HapticFeedback.selectionClick();
    final cubit = context.read<TrackerCubit>();
    if (cubit.state.tasks.isEmpty) {
      await showTaskEditor(context);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: const _TaskPickerSheet(),
      ),
    );
  }
}

class _TaskSummary extends StatelessWidget {
  final Task task;
  final TrackerState state;
  final bool enabled;
  const _TaskSummary(
      {required this.task, required this.state, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final parent = state.parentOf(task);
    final progress = state.progressOf(task);
    final total = state.totalSecondsOf(task);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (parent != null)
                Text(parent.name,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
              Text(task.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.accent)),
              if (task.hasTarget) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceHigh,
                    valueColor: AlwaysStoppedAnimation<Color>(context.accent),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Target  ${Formatters.human(total)} / '
                  '${_fmtHours(task.targetHours!)}  ·  '
                  '${((progress ?? 0) * 100).round()}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        Icon(enabled ? Icons.unfold_more : Icons.lock_outline,
            color: Colors.white38, size: 20),
      ],
    );
  }
}

String _fmtHours(double h) =>
    h == h.roundToDouble() ? '${h.round()}h' : '${h.toStringAsFixed(1)}h';

// ----------------------------------------------------------- Task picker

class _TaskPickerSheet extends StatelessWidget {
  const _TaskPickerSheet();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TrackerCubit>();
    final state = cubit.state;
    final roots = state.rootTasks;
    final maxH = MediaQuery.of(context).size.height * 0.7;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('Select a task',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in roots) ...[
                    _PickerTile(task: r, state: state, indent: false),
                    for (final c in state.childrenOf(r.id!))
                      _PickerTile(task: c, state: state, indent: true),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const TaskManagerScreen()));
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.checklist_rounded, size: 18),
                    label: const Text('Manage tasks'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      showTaskEditor(context);
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.surfaceHigh,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44)),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Task'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final Task task;
  final TrackerState state;
  final bool indent;
  const _PickerTile(
      {required this.task, required this.state, required this.indent});

  @override
  Widget build(BuildContext context) {
    final selected = state.selectedTask?.id == task.id;
    final total = state.totalSecondsOf(task);
    return ListTile(
      dense: !indent ? false : true,
      contentPadding: EdgeInsets.only(left: indent ? 36 : 12, right: 12),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? context.accent : Colors.white38,
        size: 20,
      ),
      title: Text(task.name,
          style: TextStyle(
              fontWeight: indent ? FontWeight.w500 : FontWeight.w700,
              color: selected ? context.accent : Colors.white)),
      trailing: Text(Formatters.human(total),
          style: const TextStyle(
              fontFamily: AppTheme.monoFont,
              fontSize: 12,
              color: Colors.white54)),
      onTap: () {
        HapticFeedback.selectionClick();
        context.read<TrackerCubit>().selectTask(task);
        Navigator.pop(context);
      },
    );
  }
}

// -------------------------------------------------------------- Timer display

class _TimerDisplay extends StatelessWidget {
  final TrackerState state;
  const _TimerDisplay({required this.state});

  @override
  Widget build(BuildContext context) {
    final task = state.selectedTask;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!state.isIdle && task != null) ...[
            Text(
              state.pathOf(task),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
          ],
          _StatusTag(state: state),
          const SizedBox(height: 24),
          Text(
            Formatters.hms(state.activeSeconds),
            style: const TextStyle(
              fontFamily: AppTheme.monoFont,
              fontSize: 64,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          if (state.isIdle)
            Text(
              'Today  ${Formatters.human(state.todayFocusSeconds)}'
              '  ·  ${state.todaySessionCount} '
              '${state.todaySessionCount == 1 ? 'session' : 'sessions'}',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            )
          else ...[
            Text(
              'Break  ${Formatters.hms(state.breakSeconds)}',
              style: const TextStyle(
                fontFamily: AppTheme.monoFont,
                color: AppColors.breakAmber,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Started ${Formatters.clock(state.startTimeMs)}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  final TrackerState state;
  const _StatusTag({required this.state});

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;
    switch (state.status) {
      case TrackerStatus.idle:
        color = Colors.white38;
        label = 'Idle';
        break;
      case TrackerStatus.inProgress:
        color = context.accent;
        label = 'In Progress';
        break;
      case TrackerStatus.onBreak:
        color = AppColors.breakAmber;
        label = 'On Break';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          if (state.isDeepFocus && !state.isIdle) ...[
            const SizedBox(width: 8),
            Icon(Icons.do_not_disturb_on, size: 16, color: context.accent),
            const SizedBox(width: 2),
            Text('DND',
                style: TextStyle(
                    color: context.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- Action buttons

class _ActionButtons extends StatelessWidget {
  final TrackerState state;
  const _ActionButtons({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TrackerCubit>();

    switch (state.status) {
      case TrackerStatus.idle:
        return FilledButton.icon(
          onPressed: state.selectedTask == null
              ? null
              : () => _openStartSheet(context),
          style: FilledButton.styleFrom(backgroundColor: context.accent),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Start Session'),
        );

      case TrackerStatus.inProgress:
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  cubit.takeBreak();
                },
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.breakAmber,
                    foregroundColor: Colors.black),
                icon: const Icon(Icons.pause_rounded),
                label: const Text('Take Break'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _EndButton(state: state)),
          ],
        );

      case TrackerStatus.onBreak:
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  cubit.resumeSession();
                },
                style: FilledButton.styleFrom(backgroundColor: context.accent),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Resume Session'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _EndButton(state: state)),
          ],
        );
    }
  }

  Future<void> _openStartSheet(BuildContext context) async {
    final cubit = context.read<TrackerCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final task = cubit.state.selectedTask;
    final taskName = task == null ? '' : cubit.state.pathOf(task);
    HapticFeedback.lightImpact();

    final result = await showModalBottomSheet<_StartResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _StartSessionSheet(taskName: taskName),
    );

    if (result == null) return; // cancelled

    // DND requested -> verify permission first (prompt once if missing).
    if (result.deepFocus) {
      final granted = await cubit.isDndPermissionGranted();
      if (!granted) {
        await cubit.openDndSettings();
        messenger.showSnackBar(const SnackBar(
          content: Text('Grant "Do Not Disturb access", then tap Start again.'),
        ));
        return;
      }
    }
    HapticFeedback.mediumImpact();
    await cubit.startSession(deepFocus: result.deepFocus);
  }
}

class _EndButton extends StatelessWidget {
  final TrackerState state;
  const _EndButton({required this.state});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => _confirmEnd(context),
      style: FilledButton.styleFrom(backgroundColor: AppColors.stopRed),
      icon: const Icon(Icons.stop_rounded),
      label: const Text('End Session'),
    );
  }

  Future<void> _confirmEnd(BuildContext context) async {
    final cubit = context.read<TrackerCubit>();
    final messenger = ScaffoldMessenger.of(context);
    HapticFeedback.lightImpact();

    final choice = await showModalBottomSheet<_EndChoice>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => BlocBuilder<TrackerCubit, TrackerState>(
        bloc: cubit,
        builder: (_, s) => _EndSessionSheet(state: s),
      ),
    );
    if (choice == null) return; // keep going

    final focus = Formatters.human(cubit.state.activeSeconds);
    if (choice == _EndChoice.save) {
      HapticFeedback.heavyImpact();
      await cubit.endSession(save: true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Saved  ·  $focus of focus')));
    } else {
      await cubit.endSession(save: false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Session discarded')));
    }
  }
}

// -------------------------------------------------- Start confirmation sheet

class _StartSessionSheet extends StatefulWidget {
  final String taskName;
  const _StartSessionSheet({required this.taskName});

  @override
  State<_StartSessionSheet> createState() => _StartSessionSheetState();
}

class _StartSessionSheetState extends State<_StartSessionSheet> {
  // STRICT RULE: DND toggle is OFF by default.
  bool _deepFocus = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 20),
          Text(
            'Start Session for "${widget.taskName}"?',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SwitchListTile(
              value: _deepFocus,
              activeThumbColor: context.accent,
              onChanged: (v) => setState(() => _deepFocus = v),
              secondary: const Icon(Icons.do_not_disturb_on_outlined),
              title: const Text('Enable Do Not Disturb',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Deep Focus — mutes calls & notifications'),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    side: const BorderSide(color: Colors.white24),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, _StartResult(_deepFocus)),
                  style:
                      FilledButton.styleFrom(backgroundColor: context.accent),
                  child: const Text('Start'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------- End confirmation sheet

class _EndSessionSheet extends StatelessWidget {
  final TrackerState state;
  const _EndSessionSheet({required this.state});

  @override
  Widget build(BuildContext context) {
    final task = state.selectedTask;
    final taskName = task == null ? '' : state.pathOf(task);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 20),
          Text(
            'End session for "$taskName"?',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'FOCUS',
                  value: Formatters.hms(state.activeSeconds),
                  color: context.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: 'BREAK',
                  value: Formatters.hms(state.breakSeconds),
                  color: AppColors.breakAmber,
                ),
              ),
            ],
          ),
          if (state.isDeepFocus) ...[
            const SizedBox(height: 12),
            const Text('Do Not Disturb will be turned off.',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, _EndChoice.discard),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    side: BorderSide(
                        color: AppColors.stopRed.withValues(alpha: 0.6)),
                    foregroundColor: AppColors.stopRed,
                  ),
                  child: const Text('Discard'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _EndChoice.save),
                  style:
                      FilledButton.styleFrom(backgroundColor: context.accent),
                  child: const Text('Save Session'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatTile(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontFamily: AppTheme.monoFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/models/task.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'multitasking_cubit.dart';

/// Run several task timers at once. Each is independent; stopping one saves a
/// normal session, so all analytics include multitasking time.
class MultitaskingScreen extends StatefulWidget {
  const MultitaskingScreen({super.key});

  @override
  State<MultitaskingScreen> createState() => _MultitaskingScreenState();
}

class _MultitaskingScreenState extends State<MultitaskingScreen> {
  @override
  void initState() {
    super.initState();
    context.read<MultitaskingCubit>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multitasking',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          BlocBuilder<MultitaskingCubit, MultitaskingState>(
            builder: (context, s) => s.running.isEmpty
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: () => _confirmStopAll(context),
                    child: const Text('Stop all',
                        style: TextStyle(color: AppColors.stopRed)),
                  ),
          ),
        ],
      ),
      body: BlocBuilder<MultitaskingCubit, MultitaskingState>(
        builder: (context, s) {
          return Column(
            children: [
              _StartBar(state: s),
              const Divider(height: 1, color: Colors.white10),
              Expanded(
                child: s.running.isEmpty
                    ? const _Empty()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        children: [
                          for (final r in s.running)
                            _RunningCard(timer: r, nowMs: s.nowMs),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmStopAll(BuildContext context) async {
    final cubit = context.read<MultitaskingCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop all timers?'),
        content: const Text('Every running timer is saved as a session.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop all'),
          ),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.mediumImpact();
      await cubit.stopAll();
    }
  }
}

class _StartBar extends StatelessWidget {
  final MultitaskingState state;
  const _StartBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final startable = state.startableTasks;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.playlist_add_rounded, color: Colors.white54),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              startable.isEmpty
                  ? (state.tasks.isEmpty
                      ? 'Add tasks first (Tracker → Task List)'
                      : 'All tasks are already running')
                  : 'Start another task in parallel',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          FilledButton(
            onPressed: startable.isEmpty
                ? null
                : () => _pickAndStart(context, startable),
            style: FilledButton.styleFrom(
                backgroundColor: context.accent,
                foregroundColor: Colors.black,
                minimumSize: const Size(96, 44)),
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndStart(BuildContext context, List<Task> tasks) async {
    final cubit = context.read<MultitaskingCubit>();
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<Task>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PickSheet(tasks: tasks, all: cubit.state.tasks),
    );
    if (picked != null) {
      HapticFeedback.mediumImpact();
      await cubit.startTask(picked);
    }
  }
}

class _PickSheet extends StatelessWidget {
  final List<Task> tasks; // startable
  final List<Task> all; // full tree, for path names
  const _PickSheet({required this.tasks, required this.all});

  String _path(Task t) {
    if (t.parentId == null) return t.name;
    for (final p in all) {
      if (p.id == t.parentId) return '${p.name} › ${t.name}';
    }
    return t.name;
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.6;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('Start a task',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final t in tasks)
                    ListTile(
                      leading: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white54),
                      title: Text(_path(t)),
                      onTap: () => Navigator.pop(context, t),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunningCard extends StatelessWidget {
  final RunningTimer timer;
  final int nowMs;
  const _RunningCard({required this.timer, required this.nowMs});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MultitaskingCubit>();
    final onBreak = timer.onBreak;
    final accent = context.accent;
    final statusColor = onBreak ? AppColors.breakAmber : accent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: statusColor.withValues(alpha: 0.35), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(timer.task.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              Text(onBreak ? 'On Break' : 'Running',
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            Formatters.hms(timer.activeSeconds(nowMs)),
            style: const TextStyle(
              fontFamily: AppTheme.monoFont,
              fontSize: 40,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          Text('Break  ${Formatters.hms(timer.breakSeconds(nowMs))}',
              style: const TextStyle(
                  fontFamily: AppTheme.monoFont,
                  color: AppColors.breakAmber,
                  fontSize: 12)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: onBreak
                    ? FilledButton.icon(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          cubit.resume(timer.rowId);
                        },
                        style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(44)),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Resume'),
                      )
                    : FilledButton.icon(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          cubit.takeBreak(timer.rowId);
                        },
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.breakAmber,
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(44)),
                        icon: const Icon(Icons.pause_rounded),
                        label: const Text('Break'),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    HapticFeedback.heavyImpact();
                    cubit.stop(timer.rowId);
                  },
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.stopRed,
                      minimumSize: const Size.fromHeight(44)),
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Stop'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dynamic_feed_rounded, size: 48, color: Colors.white24),
            SizedBox(height: 16),
            Text('No timers running',
                style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text(
              'Tap Start to run a task. Start more to track several tasks at '
              'the same time — each keeps its own time.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

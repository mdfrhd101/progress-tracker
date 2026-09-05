import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/database_helper.dart';
import '../data/models/session.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/bar_chart.dart';
import 'analytics_cubit.dart';
import 'analytics_state.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AnalyticsCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: BlocBuilder<AnalyticsCubit, AnalyticsState>(
        builder: (context, state) {
          if (state.loading && state.history.isEmpty && state.trend.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: () => context.read<AnalyticsCubit>().load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _SummaryRow(state: state),
                const SizedBox(height: 12),
                _MiniStatsRow(state: state),
                const SizedBox(height: 20),
                _TrendCard(state: state),
                const SizedBox(height: 20),
                if (state.targets.isNotEmpty) ...[
                  _TargetsCard(state: state),
                  const SizedBox(height: 20),
                ],
                _BreakdownCard(state: state),
                const SizedBox(height: 20),
                Text('SESSION HISTORY',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.5, color: Colors.white54)),
                const SizedBox(height: 8),
                if (state.history.isEmpty)
                  const _EmptyHint('No sessions yet — start a focus session.')
                else
                  ..._buildGroupedHistory(state.history),
              ],
            ),
          );
        },
      ),
    );
  }

  /// History list with a date header whenever the day changes
  /// (Today / Yesterday / "Sep 3, 2026").
  List<Widget> _buildGroupedHistory(List<SessionView> history) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final today = Session.dateStringFrom(nowMs);
    final yesterday = Session.dateStringFrom(
        nowMs - const Duration(days: 1).inMilliseconds);

    final widgets = <Widget>[];
    String? lastDate;
    for (final v in history) {
      final d = v.session.dateString;
      if (d != lastDate) {
        final label = d == today
            ? 'Today'
            : d == yesterday
                ? 'Yesterday'
                : Formatters.longDate(v.session.startTime);
        widgets.add(_DateHeader(label: label, first: lastDate == null));
        lastDate = d;
      }
      widgets.add(_HistoryTile(view: v));
    }
    return widgets;
  }
}

// -------------------------------------------------------------- Summary cards

class _SummaryRow extends StatelessWidget {
  final AnalyticsState state;
  const _SummaryRow({required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: "Today's Focus",
            value: Formatters.human(state.todaySeconds),
            accent: AppColors.focus,
            icon: Icons.today_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'This Week',
            value: Formatters.human(state.weekSeconds),
            accent: AppColors.breakAmber,
            icon: Icons.calendar_view_week_rounded,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final IconData icon;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.accent,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(height: 12),
          Text(value,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}

class _MiniStatsRow extends StatelessWidget {
  final AnalyticsState state;
  const _MiniStatsRow({required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MiniStat(
            label: 'Sessions today',
            value: '${state.todaySessionCount}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MiniStat(
            label: 'Avg session · 7d',
            value: Formatters.human(state.avgSessionSecondsWeek),
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Trend card

class _TrendCard extends StatelessWidget {
  final AnalyticsState state;
  const _TrendCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('7-Day Trend',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          SevenDayBarChart(data: state.trend),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- Targets card

class _TargetsCard extends StatelessWidget {
  final AnalyticsState state;
  const _TargetsCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Targets',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          for (final t in state.targets) _TargetRow(t: t),
        ],
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  final TargetProgress t;
  const _TargetRow({required this.t});

  @override
  Widget build(BuildContext context) {
    final done = t.fraction >= 1;
    final h = t.task.targetHours!;
    final target = h == h.roundToDouble()
        ? '${h.round()}h'
        : '${h.toStringAsFixed(1)}h';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t.path,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text(
                '${Formatters.human(t.totalSeconds)} / $target'
                '  ·  ${(t.fraction * 100).round()}%${done ? '  ✓' : ''}',
                style: TextStyle(
                    color: done ? AppColors.focus : Colors.white70,
                    fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: t.fraction,
              minHeight: 8,
              backgroundColor: AppColors.surfaceHigh,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.focus),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ Breakdown card

class _BreakdownCard extends StatelessWidget {
  final AnalyticsState state;
  const _BreakdownCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final total = state.breakdownTotal;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Task Breakdown',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          _FilterSelector(current: state.filter),
          const SizedBox(height: 16),
          if (state.breakdown.isEmpty)
            const _EmptyHint('No focus time in this range.')
          else
            ...state.breakdown.map((t) {
              final pct = total == 0 ? 0.0 : t.totalActiveSeconds / total;
              return _BreakdownRow(
                name: t.taskName,
                duration: Formatters.human(t.totalActiveSeconds),
                fraction: pct,
              );
            }),
        ],
      ),
    );
  }
}

class _FilterSelector extends StatelessWidget {
  final AnalyticsRange current;
  const _FilterSelector({required this.current});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<AnalyticsRange>(
      segments: const [
        ButtonSegment(value: AnalyticsRange.today, label: Text('Today')),
        ButtonSegment(value: AnalyticsRange.week, label: Text('This Week')),
        ButtonSegment(value: AnalyticsRange.allTime, label: Text('All Time')),
      ],
      selected: {current},
      showSelectedIcon: false,
      onSelectionChanged: (s) =>
          context.read<AnalyticsCubit>().setFilter(s.first),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String name;
  final String duration;
  final double fraction;
  const _BreakdownRow(
      {required this.name, required this.duration, required this.fraction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text('$duration  ·  ${(fraction * 100).round()}%',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.surfaceHigh,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.focus),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- History section

class _DateHeader extends StatelessWidget {
  final String label;
  final bool first;
  const _DateHeader({required this.label, required this.first});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 8, bottom: 8),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final SessionView view;
  const _HistoryTile({required this.view});

  @override
  Widget build(BuildContext context) {
    final s = view.session;
    return Dismissible(
      key: ValueKey('session-${s.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.stopRed.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) {
        if (s.id == null) return;
        final cubit = context.read<AnalyticsCubit>();
        HapticFeedback.mediumImpact();
        cubit.deleteSession(s.id!);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: const Text('Session deleted'),
            action: SnackBarAction(
              label: 'UNDO',
              textColor: AppColors.focus,
              onPressed: () => cubit.restoreSession(s),
            ),
          ));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(view.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                      if (s.isDeepFocus) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.focus.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('DND',
                              style: TextStyle(
                                  color: AppColors.focus,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Formatters.timeRange(s.startTime, s.endTime),
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Break ${Formatters.human(s.breakDurationSeconds)}',
                    style: const TextStyle(
                        color: AppColors.breakAmber, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              Formatters.human(s.activeDurationSeconds),
              style: const TextStyle(
                  fontFamily: AppTheme.monoFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.focus),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- Empty hint

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(text,
          style: const TextStyle(color: Colors.white38),
          textAlign: TextAlign.center),
    );
  }
}

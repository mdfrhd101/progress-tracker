import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../analytics/analytics_cubit.dart';
import '../services/backup_service.dart';
import '../sync/lan_sync_screen.dart';
import '../theme/app_theme.dart';
import '../tracker/tracker_cubit.dart';

/// Backup & merge card: export a backup file (share to your other phone), and
/// import one to merge it in. Fully offline; nothing is uploaded.
class BackupSection extends StatefulWidget {
  const BackupSection({super.key});

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  final _service = BackupService();
  bool _busy = false;
  String _message = '';
  Color _messageColor = Colors.white54;

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await _service.exportAndShare();
      _set('Backup created — share it to your other phone.',
          AppColors.defaultAccent);
    } catch (_) {
      _set('Could not create the backup.', AppColors.stopRed);
    }
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final r = await _service.pickAndMerge();
      if (r == null) {
        _set('', Colors.white54); // cancelled
        return;
      }
      if (!mounted) return;
      // Refresh the app's live data after a merge.
      context.read<TrackerCubit>().init();
      context.read<AnalyticsCubit>().load();
      _set(
        'Merged: +${r.tasksAdded} tasks, +${r.sessionsAdded} sessions.',
        AppColors.defaultAccent,
      );
    } on FormatException catch (e) {
      _set(e.message, AppColors.stopRed);
    } catch (_) {
      _set('Import failed.', AppColors.stopRed);
    }
  }

  void _set(String msg, Color color) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = msg;
      _messageColor = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Backup & transfer',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          const Text(
            'Move your data between phones with a backup file — no account, no '
            'internet. Export here, send the file to your other phone (Nearby '
            'Share, Bluetooth, cable…), then Import there. Import merges; it '
            'never deletes what is already on the device.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (_message.isNotEmpty) ...[
            Text(_message,
                style: TextStyle(color: _messageColor, fontSize: 12)),
            const SizedBox(height: 10),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Working…', style: TextStyle(color: Colors.white70)),
              ]),
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _export();
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: context.accent,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(46)),
                    icon: const Icon(Icons.upload_rounded),
                    label: const Text('Export'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _import();
                    },
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46)),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Import'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10),
          const SizedBox(height: 4),
          const Text('Same Wi-Fi? Sync directly, no file:',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LanSyncScreen())),
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46)),
            icon: const Icon(Icons.wifi_tethering_rounded),
            label: const Text('LAN sync (same Wi-Fi)'),
          ),
        ],
      ),
    );
  }
}

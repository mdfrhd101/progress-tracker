import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../analytics/analytics_cubit.dart';
import '../services/cloud_sync_service.dart';
import '../services/platform_service.dart';
import '../theme/app_theme.dart';
import '../tracker/tracker_cubit.dart';
import '../utils/formatters.dart';

/// Cloud sync via a private GitHub Gist. Paste a token once, create or join a
/// sync code (gist id), then Sync (pull → merge → push). Optional auto-sync
/// runs when the app is opened.
class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  final _service = CloudSyncService();
  final _tokenCtl = TextEditingController();
  final _codeCtl = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  bool _hasToken = false;
  String? _gistId;
  bool _auto = false;
  int? _lastMs;
  String _status = '';
  Color _statusColor = Colors.white54;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tokenCtl.dispose();
    _codeCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tok = await _service.token();
    final id = await _service.gistId();
    final auto = await _service.autoEnabled();
    final last = await _service.lastSyncMs();
    if (!mounted) return;
    setState(() {
      _hasToken = tok != null;
      _gistId = id;
      _auto = auto;
      _lastMs = last;
      _loading = false;
    });
  }

  void _set(String msg, Color color, {bool busy = false}) {
    if (!mounted) return;
    setState(() {
      _status = msg;
      _statusColor = color;
      _busy = busy;
    });
  }

  Future<void> _saveToken() async {
    final t = _tokenCtl.text.trim();
    if (t.isEmpty) return;
    await _service.setToken(t);
    _tokenCtl.clear();
    await _load();
    _set('Token saved on this phone.', AppColors.defaultAccent);
  }

  Future<void> _create() async {
    _set('Creating…', Colors.white54, busy: true);
    try {
      final id = await _service.createStore();
      await _load();
      _set('Sync created. Share the code with your other phone.',
          AppColors.defaultAccent);
      setState(() => _gistId = id);
    } on CloudException catch (e) {
      _set(e.message, AppColors.stopRed);
    }
  }

  Future<void> _join() async {
    final code = _codeCtl.text.trim();
    if (code.isEmpty) {
      _set('Paste the sync code from your other phone.', AppColors.stopRed);
      return;
    }
    _set('Joining…', Colors.white54, busy: true);
    try {
      final r = await _service.sync(gistIdOverride: code);
      _refreshApp();
      await _load();
      _set(
          'Joined & synced: +${r.tasksAdded} tasks, +${r.sessionsAdded} sessions.',
          AppColors.defaultAccent);
    } on CloudException catch (e) {
      _set(e.message, AppColors.stopRed);
    }
  }

  Future<void> _syncNow() async {
    _set('Syncing…', Colors.white54, busy: true);
    try {
      final r = await _service.sync();
      _refreshApp();
      await _load();
      _set('Synced: +${r.tasksAdded} tasks, +${r.sessionsAdded} sessions.',
          AppColors.defaultAccent);
    } on CloudException catch (e) {
      _set(e.message, AppColors.stopRed);
    }
  }

  void _refreshApp() {
    context.read<TrackerCubit>().init();
    context.read<AnalyticsCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Sync',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                const Text(
                  'Sync your two phones through your own private GitHub Gist. '
                  'The app talks only to GitHub — your tracking data goes '
                  'nowhere else. Your token is stored only on this phone.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (_status.isNotEmpty) ...[
                  Text(_status,
                      style: TextStyle(color: _statusColor, fontSize: 12)),
                  const SizedBox(height: 12),
                ],
                if (!_hasToken)
                  _tokenCard()
                else if (_gistId == null)
                  _connectCard()
                else
                  _connectedCard(),
              ],
            ),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _tokenCard() => _card('1 · GitHub token', [
        const Text(
          'Create a token with "Gists" access, paste it below. It stays on this '
          'phone only.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _tokenCtl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Paste token (ghp_… / github_pat_…)',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => const PlatformService()
                    .openUrl('https://github.com/settings/tokens?type=beta'),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46)),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Get token'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _saveToken,
                style: FilledButton.styleFrom(
                    backgroundColor: context.accent,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(46)),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ]);

  Widget _connectCard() => _card('2 · Create or join', [
        const Text(
          'On your FIRST phone tap Create. On the SECOND, paste the code the '
          'first phone shows and tap Join.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          style: FilledButton.styleFrom(
              backgroundColor: context.accent,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(46)),
          icon: const Icon(Icons.cloud_upload_rounded),
          label: const Text('Create new sync'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _codeCtl,
          decoration: const InputDecoration(labelText: 'Sync code'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _join,
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46)),
          icon: const Icon(Icons.cloud_download_rounded),
          label: const Text('Join with code'),
        ),
      ]);

  Widget _connectedCard() => _card('Connected', [
        const Text('Sync code (share with your other phone)',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(_gistId ?? '',
                    style: const TextStyle(
                        fontFamily: AppTheme.monoFont, fontSize: 13)),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                color: Colors.white54,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _gistId ?? ''));
                  HapticFeedback.selectionClick();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_lastMs != null)
          Text('Last synced ${Formatters.clock(_lastMs!)}',
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 10),
        SwitchListTile(
          value: _auto,
          activeThumbColor: context.accent,
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-sync when I open the app'),
          onChanged: (v) async {
            await _service.setAuto(v);
            setState(() => _auto = v);
          },
        ),
        const SizedBox(height: 6),
        _busy
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              )
            : FilledButton.icon(
                onPressed: _syncNow,
                style: FilledButton.styleFrom(
                    backgroundColor: context.accent,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Sync now'),
              ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () async {
            await _service.disconnect();
            await _load();
            _set('Disconnected from cloud sync.', Colors.white54);
          },
          child:
              const Text('Disconnect', style: TextStyle(color: Colors.white54)),
        ),
      ]);
}

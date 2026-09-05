import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../analytics/analytics_cubit.dart';
import '../services/lan_sync_service.dart';
import '../theme/app_theme.dart';
import '../tracker/tracker_cubit.dart';

/// Same-Wi-Fi device-to-device sync. One phone Hosts (shows IP + PIN), the
/// other Joins with them. A single exchange merges both phones.
class LanSyncScreen extends StatefulWidget {
  const LanSyncScreen({super.key});

  @override
  State<LanSyncScreen> createState() => _LanSyncScreenState();
}

class _LanSyncScreenState extends State<LanSyncScreen> {
  final _service = LanSyncService();

  // Host state
  bool _hosting = false;
  String _pin = '';
  String? _ip;
  String _hostStatus = '';

  // Join state
  final _ipCtl = TextEditingController();
  final _pinCtl = TextEditingController();
  bool _joining = false;
  String _joinStatus = '';
  Color _joinColor = Colors.white54;

  @override
  void dispose() {
    _service.stopHost();
    _ipCtl.dispose();
    _pinCtl.dispose();
    super.dispose();
  }

  void _refreshApp() {
    context.read<TrackerCubit>().init();
    context.read<AnalyticsCubit>().load();
  }

  Future<void> _startHost() async {
    final ip = await _service.localIp();
    if (ip == null) {
      setState(() => _hostStatus = 'Not connected to Wi-Fi.');
      return;
    }
    final pin = (Random().nextInt(900000) + 100000).toString();
    await _service.startHost(
      pin: pin,
      onSync: (r) {
        if (!mounted) return;
        _refreshApp();
        setState(() => _hostStatus =
            'Synced with a device: +${r.tasksAdded} tasks, +${r.sessionsAdded} sessions. Still hosting…');
      },
      onError: (_) {
        if (!mounted) return;
        setState(() =>
            _hostStatus = 'A device tried with a wrong PIN. Still hosting…');
      },
    );
    setState(() {
      _hosting = true;
      _ip = ip;
      _pin = pin;
      _hostStatus = 'Waiting for the other phone to join…';
    });
  }

  Future<void> _stopHost() async {
    await _service.stopHost();
    setState(() {
      _hosting = false;
      _hostStatus = '';
    });
  }

  Future<void> _join() async {
    final ip = _ipCtl.text.trim();
    final pin = _pinCtl.text.trim();
    if (ip.isEmpty || pin.length != 6) {
      setState(() {
        _joinStatus = 'Enter the host IP and its 6-digit PIN.';
        _joinColor = AppColors.stopRed;
      });
      return;
    }
    setState(() {
      _joining = true;
      _joinStatus = '';
    });
    try {
      final r = await _service.join(host: ip, pin: pin);
      if (!mounted) return;
      _refreshApp();
      setState(() {
        _joining = false;
        _joinColor = AppColors.defaultAccent;
        _joinStatus =
            'Synced: +${r.tasksAdded} tasks, +${r.sessionsAdded} sessions.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _joinColor = AppColors.stopRed;
        _joinStatus = 'Could not sync. Check same Wi-Fi, IP and PIN.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LAN Sync',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Text(
            'Both phones must be on the same Wi-Fi. On ONE phone tap Host, then '
            'on the OTHER enter that phone’s IP + PIN and tap Join. One sync '
            'merges both — no internet, no file.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _card(
            title: 'Host',
            children: [
              if (!_hosting)
                FilledButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _startHost();
                  },
                  style: FilledButton.styleFrom(
                      backgroundColor: context.accent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(46)),
                  icon: const Icon(Icons.wifi_tethering_rounded),
                  label: const Text('Host on this phone'),
                )
              else ...[
                _bigField('IP address', _ip ?? '—'),
                const SizedBox(height: 10),
                _bigField('PIN', _pin),
                const SizedBox(height: 10),
                Text(_hostStatus,
                    style: TextStyle(color: context.accent, fontSize: 12)),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _stopHost,
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(44)),
                  child: const Text('Stop hosting'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _card(
            title: 'Join',
            children: [
              TextField(
                controller: _ipCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Host phone's IP",
                  hintText: 'e.g. 192.168.0.12',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pinCtl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'PIN',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 6),
              if (_joinStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_joinStatus,
                      style: TextStyle(color: _joinColor, fontSize: 12)),
                ),
              _joining
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('Syncing…',
                            style: TextStyle(color: Colors.white70)),
                      ]),
                    )
                  : FilledButton.icon(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        _join();
                      },
                      style: FilledButton.styleFrom(
                          backgroundColor: context.accent,
                          foregroundColor: Colors.black,
                          minimumSize: const Size.fromHeight(46)),
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text('Join & sync'),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
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
  }

  Widget _bigField(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54)),
          Row(
            children: [
              SelectableText(
                value,
                style: const TextStyle(
                    fontFamily: AppTheme.monoFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                color: Colors.white54,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  HapticFeedback.selectionClick();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

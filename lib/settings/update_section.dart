import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
import '../services/platform_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';

enum _Phase { idle, checking, upToDate, available, downloading, ready, error }

/// The in-app updater card: Check → (if newer) Download → Install.
/// Networking lives entirely in [UpdateService]; this only drives the UI.
class UpdateSection extends StatefulWidget {
  const UpdateSection({super.key});

  @override
  State<UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<UpdateSection> {
  final _service = const UpdateService();

  _Phase _phase = _Phase.idle;
  UpdateInfo? _info;
  double _progress = 0;
  String _message = '';
  String? _apkPath;

  Future<void> _check() async {
    setState(() {
      _phase = _Phase.checking;
      _message = '';
    });
    try {
      final info = await _service.checkForUpdate();
      if (!mounted) return;
      setState(() {
        if (info == null) {
          _phase = _Phase.upToDate;
        } else {
          _phase = _Phase.available;
          _info = info;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _message = 'Could not check for updates. Check your connection.';
      });
    }
  }

  Future<void> _download() async {
    final info = _info;
    if (info == null) return;
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
    });
    try {
      final path = await _service.download(info, (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() {
        _phase = _Phase.ready;
        _apkPath = path;
      });
      await _install();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _message = 'Download failed. Try again.';
      });
    }
  }

  Future<void> _install() async {
    final path = _apkPath;
    if (path == null) return;
    final result = await _service.install(path);
    if (!mounted) return;
    if (result == 'permission') {
      setState(() {
        _message =
            'Allow "Install unknown apps" for Progress Tracker, then tap Install again.';
      });
    } else if (result == 'error') {
      setState(() {
        _phase = _Phase.error;
        _message = 'Could not open the installer. Use "Open releases page".';
      });
    }
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
          const Text('Update',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          const Text('Installed version  ${AppInfo.version}',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          ..._body(context),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () =>
                const PlatformService().openUrl(AppInfo.releasesUrl),
            child: const Text('Open releases page',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    switch (_phase) {
      case _Phase.idle:
      case _Phase.upToDate:
      case _Phase.error:
        return [
          if (_phase == _Phase.upToDate)
            const _Note('You are on the latest version.',
                color: AppColors.breakAmber),
          if (_phase == _Phase.error && _message.isNotEmpty)
            _Note(_message, color: AppColors.stopRed),
          FilledButton.icon(
            onPressed: _check,
            style: FilledButton.styleFrom(
                backgroundColor: context.accent,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(46)),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Check for updates'),
          ),
        ];

      case _Phase.checking:
        return const [
          Row(children: [
            SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Checking…', style: TextStyle(color: Colors.white70)),
          ]),
        ];

      case _Phase.available:
        final info = _info!;
        final mb = (info.apkSize / 1048576).toStringAsFixed(1);
        return [
          Text('Version ${info.version} is available  ·  $mb MB',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (info.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              info.notes.length > 240
                  ? '${info.notes.substring(0, 240)}…'
                  : info.notes,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              HapticFeedback.mediumImpact();
              _download();
            },
            style: FilledButton.styleFrom(
                backgroundColor: context.accent,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(46)),
            icon: const Icon(Icons.download_rounded),
            label: Text('Download & install ${info.version}'),
          ),
        ];

      case _Phase.downloading:
        return [
          Text('Downloading…  ${(_progress * 100).round()}%',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress == 0 ? null : _progress,
              minHeight: 6,
              backgroundColor: AppColors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation<Color>(context.accent),
            ),
          ),
        ];

      case _Phase.ready:
        return [
          if (_message.isNotEmpty) _Note(_message, color: AppColors.breakAmber),
          FilledButton.icon(
            onPressed: _install,
            style: FilledButton.styleFrom(
                backgroundColor: context.accent,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(46)),
            icon: const Icon(Icons.system_update_alt_rounded),
            label: const Text('Install'),
          ),
        ];
    }
  }
}

class _Note extends StatelessWidget {
  final String text;
  final Color color;
  const _Note(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

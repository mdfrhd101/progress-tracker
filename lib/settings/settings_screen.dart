import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../app_info.dart';
import '../services/platform_service.dart';
import '../theme/app_theme.dart';
import 'settings_cubit.dart';

/// Look & feel + update entry point. Everything is applied live and saved.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, s) {
          final cubit = context.read<SettingsCubit>();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _SectionCard(
                title: 'Accent colour',
                child: Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final a in AppColors.accents)
                      _Swatch(
                        option: a,
                        selected: a.color.toARGB32() == s.accent.toARGB32(),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          cubit.setAccent(a.color);
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Font',
                child: RadioGroup<String?>(
                  groupValue: s.fontFamily,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    cubit.setFont(v);
                  },
                  child: Column(
                    children: [
                      for (final f in AppFonts.options)
                        RadioListTile<String?>(
                          value: f.family,
                          activeColor: context.accent,
                          contentPadding: EdgeInsets.zero,
                          title: Text(f.name,
                              style: TextStyle(fontFamily: f.family)),
                          subtitle: Text('The quick brown fox 0123',
                              style: TextStyle(
                                  fontFamily: f.family,
                                  color: Colors.white54,
                                  fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Text size',
                child: SegmentedButton<double>(
                  segments: const [
                    ButtonSegment(value: 0.9, label: Text('Small')),
                    ButtonSegment(value: 1.0, label: Text('Normal')),
                    ButtonSegment(value: 1.15, label: Text('Large')),
                  ],
                  selected: {s.textScale},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) {
                    HapticFeedback.selectionClick();
                    cubit.setTextScale(v.first);
                  },
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Update',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Installed version  ${AppInfo.version}',
                        style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 4),
                    const Text(
                      'The app itself never touches the network. Updates are '
                      'published on GitHub; this opens the releases page in '
                      'your browser — install the newest APK over this one, '
                      'your data is kept.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () =>
                          const PlatformService().openUrl(AppInfo.releasesUrl),
                      style: FilledButton.styleFrom(
                          backgroundColor: context.accent,
                          foregroundColor: Colors.black,
                          minimumSize: const Size.fromHeight(46)),
                      icon: const Icon(Icons.system_update_alt_rounded),
                      label: const Text('Get latest version'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  cubit.reset();
                },
                child: const Text('Reset to defaults',
                    style: TextStyle(color: Colors.white54)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

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
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final AccentOption option;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch(
      {required this.option, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: option.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Colors.white : Colors.transparent,
                width: 3,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.black, size: 22)
                : null,
          ),
          const SizedBox(height: 6),
          Text(option.name,
              style: TextStyle(
                  fontSize: 11,
                  color: selected ? Colors.white : Colors.white54)),
        ],
      ),
    );
  }
}

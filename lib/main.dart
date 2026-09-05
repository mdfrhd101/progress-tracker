import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'analytics/analytics_cubit.dart';
import 'analytics/analytics_screen.dart';
import 'multitasking/multitasking_cubit.dart';
import 'services/cloud_sync_service.dart';
import 'settings/settings_cubit.dart';
import 'theme/app_theme.dart';
import 'tracker/tracker_cubit.dart';
import 'tracker/tracker_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Blend the Android status / navigation bars into the dark UI.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const ProgressTrackerApp());
}

class ProgressTrackerApp extends StatelessWidget {
  const ProgressTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => SettingsCubit()..load()),
        // init() loads tasks and restores any in-flight session.
        BlocProvider(create: (_) => TrackerCubit()..init()),
        BlocProvider(create: (_) => AnalyticsCubit()),
        BlocProvider(create: (_) => MultitaskingCubit()),
      ],
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, settings) {
          final theme = AppTheme.build(
            accent: settings.accent,
            fontFamily: settings.fontFamily,
          );
          return MaterialApp(
            title: 'Progress Tracker',
            debugShowCheckedModeBanner: false,
            theme: theme,
            darkTheme: theme,
            themeMode: ThemeMode.dark, // native dark-mode app
            // User-chosen text size (Settings), applied app-wide.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(settings.textScale),
              ),
              child: child ?? const SizedBox.shrink(),
            ),
            home: const RootNav(),
          );
        },
      ),
    );
  }
}

/// Bottom-tab shell hosting the Tracker and Analytics screens.
class RootNav extends StatefulWidget {
  const RootNav({super.key});

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> with WidgetsBindingObserver {
  final _cloud = CloudSyncService();
  int _index = 0;

  static const _screens = [TrackerScreen(), AnalyticsScreen()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _maybeAutoSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _maybeAutoSync();
  }

  /// Silent cloud sync when the app opens/resumes, if enabled and configured.
  Future<void> _maybeAutoSync() async {
    try {
      if (!await _cloud.autoEnabled()) return;
      if (await _cloud.token() == null || await _cloud.gistId() == null) return;
      final r = await _cloud.sync();
      if (!mounted) return;
      if (r.tasksAdded > 0 || r.sessionsAdded > 0) {
        context.read<TrackerCubit>().init();
        context.read<AnalyticsCubit>().load();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Cloud sync: +${r.tasksAdded} tasks, +${r.sessionsAdded} sessions'),
        ));
      }
    } catch (_) {
      // silent — manual Sync surfaces errors
    }
  }

  void _onTab(int i) {
    setState(() => _index = i);
    // Refresh analytics whenever the user lands on it (new sessions, deletes).
    if (i == 1) context.read<AnalyticsCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer),
            label: 'Tracker',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Analytics',
          ),
        ],
      ),
    );
  }
}

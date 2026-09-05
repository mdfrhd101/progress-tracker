# Progress Tracker

A 100% offline, single-user focus/productivity tracker for Android. Flutter +
`sqflite`, Material 3 dark, `flutter_bloc` state machine, resilient
timestamp-based timer, and an optional Do-Not-Disturb (Deep Focus) mode.

## Highlights
- **Sub-tasks & targets (v1.2)** — sidebar (☰) → **Task List / Add Task**; group work as
  `Cloud › Python`, `Cloud › AWS`; set an hours target per task or sub-task (e.g. Python 100 h)
  and watch a progress bar on the tracker, in the task list and on a **Targets** analytics card.
  Parent progress = its own time + all sub-tasks.
- **Polished UX (v1.1)** — remembers your last task, long-press to delete a task, an
  end-of-session summary sheet with **Save / Discard** (no accidental records), date-grouped
  history with **Undo** on swipe-delete, "sessions today" + "avg session" stats, haptic
  feedback, custom adaptive app icon, dark splash (no white flash), themed system bars.
- **Zero network** — no `INTERNET` permission is declared; the app cannot open a socket.
- **No login** — single local user.
- **Resilient timer** — elapsed time is recomputed from epoch timestamps every tick, so it
  never drifts while backgrounded/screen-off; the in-flight session is mirrored to SQLite,
  so even a process kill is restored on next launch.
- **Deep Focus (DND)** — opt-in per session, **OFF by default**; flips the phone to total
  silence and restores normal mode when the session ends.

## Project layout
```
lib/
  main.dart                    # app + bottom-nav shell
  theme/app_theme.dart         # M3 dark theme, palette
  utils/formatters.dart        # HH:MM:SS, "3h 45m", time ranges
  tasks/task_manager_screen.dart # task list, sub-tasks, targets, add/edit/delete dialogs
  data/
    database_helper.dart       # sqflite v3: schema+migrations, CRUD, analytics, active-session
    models/task.dart
    models/session.dart        # Session + SessionView/TaskTotal/DailyTotal
  services/dnd_service.dart     # MethodChannel wrapper (fail-safe)
  tracker/
    tracker_cubit.dart         # timer engine + DND + persistence
    tracker_state.dart
    tracker_screen.dart        # selector, timer, buttons, start-DND sheet
  analytics/
    analytics_cubit.dart
    analytics_state.dart
    analytics_screen.dart      # summary, filters, chart, swipe-to-delete history
  widgets/bar_chart.dart        # custom-painted 7-day bar chart
android/app/src/main/
  AndroidManifest.xml          # offline; ACCESS_NOTIFICATION_POLICY only
  kotlin/.../MainActivity.kt    # native DND MethodChannel
test/database_helper_test.dart # desktop DB tests (no emulator)
```

## First-time setup
Requires the Flutter SDK on PATH. Then, from the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup_project.ps1
```

This backs up the hand-written files, runs `flutter create` to generate the Android
platform scaffolding, restores the authored files, patches `minSdk` to **23** (needed for
the DND API), and runs `flutter pub get`.

> Doing it manually instead? Run `flutter create .`, then re-copy `AndroidManifest.xml`
> and `MainActivity.kt` over the generated defaults, and set `minSdk = 23`.

## Run
```powershell
flutter test          # DB layer, no device needed (11 tests, incl. v1->v3 migration)
flutter run           # on a connected Android device / emulator
```

## Release (offline, obfuscated)
```powershell
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
```
Install `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` on a modern phone
(~16 MB). The un-split `app-release.apk` (~46 MB) works on any ABI.
Confirm the release manifest still has **no** `INTERNET` permission.

## Download the latest APK (phone)
Releases are published automatically by CI on every version tag:

- Latest release page: https://github.com/mdfrhd101/progress-tracker/releases/latest
- Direct arm64 APK: https://github.com/mdfrhd101/progress-tracker/releases/latest/download/app-arm64-v8a-release.apk

The repo is private, so sign in to GitHub in the phone browser first. Install over the
previous version; data is kept. APKs are signed with the project release key
(cert `CN=Progress Tracker`), so they update in place.

## Shipping a new version (maintainer)
```bash
# 1. bump version in pubspec.yaml (e.g. 1.3.0+5), add a DB migration if the schema changed
# 2. commit, then tag and push — CI does analyze → test → signed build → GitHub Release
git tag -a v1.3.0 -m "v1.3.0" && git push origin main v1.3.0
```
Secrets used by CI: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`. The keystore lives outside the repo
(`D:\dev\keys\`); `android/key.properties` is gitignored.

## Updating the app (the "update pipeline")
The app has **no INTERNET permission**, so it cannot fetch updates itself — by design.
Updates are shipped as a new APK: bump `version:` in `pubspec.yaml`, add a DB migration in
`DatabaseHelper._onUpgrade` if the schema changed, `flutter build apk --release --split-per-abi`,
and install the new APK over the old one. Android treats it as an in-place update (same
signing key) and **all data is kept** — migrations upgrade the SQLite file on first launch.

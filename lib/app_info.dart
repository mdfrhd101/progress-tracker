/// Static app metadata (kept in sync with pubspec.yaml by the release step).
class AppInfo {
  AppInfo._();

  static const String version = '1.4.0';
  static const String repo = 'mdfrhd101/progress-tracker';

  /// Human page with all releases (browser fallback).
  static const String releasesUrl = 'https://github.com/$repo/releases/latest';

  /// Machine endpoint the in-app updater queries (public repo, no token).
  static const String latestReleaseApi =
      'https://api.github.com/repos/$repo/releases/latest';
}

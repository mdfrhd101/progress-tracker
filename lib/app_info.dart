/// Static app metadata (kept in sync with pubspec.yaml by the release step).
class AppInfo {
  AppInfo._();

  static const String version = '1.3.0';

  /// Where CI publishes signed APKs. Opened in the system browser — the app
  /// itself has no INTERNET permission.
  static const String releasesUrl =
      'https://github.com/mdfrhd101/progress-tracker/releases/latest';
}

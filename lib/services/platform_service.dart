import 'package:flutter/services.dart';

/// Small, fail-safe platform helpers that do not need any permission.
class PlatformService {
  static const MethodChannel _channel =
      MethodChannel('com.octagram.progress_tracker/platform');

  const PlatformService();

  /// Hands a URL to the system browser via ACTION_VIEW. The browser does the
  /// networking; this app stays offline. Returns false if nothing could open it.
  Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

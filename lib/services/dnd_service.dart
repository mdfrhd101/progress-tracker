import 'package:flutter/services.dart';

/// Thin, fail-safe wrapper over the native DND MethodChannel.
///
/// Every method swallows platform errors and returns a conservative value —
/// the timer must keep working even if DND is unavailable (older OS, denied
/// permission, non-Android platform in tests).
class DndService {
  static const MethodChannel _channel =
      MethodChannel('com.octagram.progress_tracker/dnd');

  const DndService();

  /// True if ACCESS_NOTIFICATION_POLICY has been granted by the user.
  Future<bool> isPermissionGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isDndPermissionGranted') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system settings screen to grant DND access. Fire-and-forget.
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openDndSettings');
    } on PlatformException {
      // ignored — nothing we can do
    } on MissingPluginException {
      // ignored
    }
  }

  /// Switches the phone into total-silence DND. Returns whether it took effect.
  Future<bool> enable() async {
    try {
      return await _channel.invokeMethod<bool>('enableDnd') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Restores normal ringer/notification mode. Returns whether it took effect.
  Future<bool> disable() async {
    try {
      return await _channel.invokeMethod<bool>('disableDnd') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

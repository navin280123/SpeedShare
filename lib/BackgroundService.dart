import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Manages the Android foreground service and CPU wakelock so that
/// transfers, sync, and streams survive backgrounding / screen-off.
///
/// Usage:
///   await BackgroundService.start(key: 'send', title: 'Sending files', body: '...');
///   await BackgroundService.update(title: '...', body: '50% complete');
///   await BackgroundService.stop(key: 'send');
class BackgroundService {
  BackgroundService._();

  static final Set<String> _activeKeys = {};

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Call when a long-running operation starts.
  /// [key]   — unique identifier ('send', 'receive', 'sync', 'stream')
  /// [title] — notification title shown in the status bar
  /// [body]  — notification body text
  static Future<void> start({
    required String key,
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) return;
    _activeKeys.add(key);
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    if (_activeKeys.length == 1) {
      await FlutterForegroundTask.startService(
        notificationTitle: title,
        notificationText: body,
        callback: _startCallback,
      );
    } else {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: body,
      );
    }
  }

  /// Update the foreground notification text mid-operation.
  static Future<void> update({
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) return;
    if (_activeKeys.isEmpty) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: body,
      );
    } catch (_) {}
  }

  /// Call when a long-running operation finishes.
  /// Foreground service is stopped only when ALL active operations are done.
  static Future<void> stop({required String key}) async {
    if (!Platform.isAndroid) return;
    _activeKeys.remove(key);
    if (_activeKeys.isEmpty) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (_) {}
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }

  // ─── Initialisation ────────────────────────────────────────────────────────

  /// Call once from main() before runApp() to register notification channel.
  static void initialize() {
    if (!Platform.isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'speedshare_background',
        channelName: 'SpeedShare Background',
        channelDescription:
            'Shown while SpeedShare is transferring files or streaming media.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Request battery optimization exemption (optional, called from settings).
  static Future<void> requestPermissions() async {
    if (!Platform.isAndroid) return;
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }
}

// Top-level callback — required by flutter_foreground_task.
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_SpeedShareTaskHandler());
}

class _SpeedShareTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

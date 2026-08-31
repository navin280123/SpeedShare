import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Manages the Android foreground service and CPU wakelock so that
/// transfers, sync, and streams survive backgrounding / screen-off.
///
/// Also handles notification Cancel/Stop action buttons by relaying button
/// press events from the task isolate back to the main isolate via
/// flutter_foreground_task's built-in messaging bus.
///
/// Usage:
///   await BackgroundService.start(key: 'send', title: '...', body: '...', buttons: [...]);
///   await BackgroundService.update(title: '...', body: '50%',  buttons: [...]);
///   await BackgroundService.stop(key: 'send');
///   if (BackgroundService.isCancelled('send')) { ... BackgroundService.clearCancel('send'); }
class BackgroundService {
  BackgroundService._();

  static final Set<String> _activeKeys = {};

  /// Keys that received a cancel/stop signal from a notification button.
  static final Set<String> _cancelledKeys = {};

  /// Optional callback invoked when a notification button is tapped.
  /// The argument is the operation key (e.g. 'send', 'sync').
  static void Function(String key)? onCancelRequested;

  // ─── Cancel / Stop API ─────────────────────────────────────────────────────

  /// True if the user tapped Cancel/Stop in the notification for [key].
  static bool isCancelled(String key) => _cancelledKeys.contains(key);

  /// Call after handling the cancellation to reset the flag.
  static void clearCancel(String key) => _cancelledKeys.remove(key);

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Call when a long-running operation starts.
  /// [key]     — unique identifier ('send', 'receive', 'sync', 'stream')
  /// [title]   — notification title
  /// [body]    — notification body text
  /// [buttons] — optional action buttons (e.g. Cancel / Stop)
  static Future<void> start({
    required String key,
    required String title,
    required String body,
    List<NotificationButton> buttons = const [],
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
        notificationButtons: buttons,
        callback: _startCallback,
      );
    } else {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: body,
        notificationButtons: buttons,
      );
    }
  }

  /// Update the foreground notification text and buttons mid-operation.
  static Future<void> update({
    required String title,
    required String body,
    List<NotificationButton> buttons = const [],
  }) async {
    if (!Platform.isAndroid) return;
    if (_activeKeys.isEmpty) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: body,
        notificationButtons: buttons,
      );
    } catch (_) {}
  }

  /// Call when a long-running operation finishes.
  /// Foreground service is stopped only when ALL active operations are done.
  static Future<void> stop({required String key}) async {
    if (!Platform.isAndroid) return;
    _activeKeys.remove(key);
    _cancelledKeys.remove(key);
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

  /// Call once from main() before runApp().
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

    // Listen for messages from the task isolate (button press events)
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  /// Called when the task isolate sends data to the main isolate.
  /// Button press events arrive as the string 'cancel_<key>' or 'stop_<key>'.
  static void _onTaskData(Object data) {
    if (data is! String) return;
    String key = '';
    if (data.startsWith('cancel_')) {
      key = data.replaceFirst('cancel_', '');
    } else if (data.startsWith('stop_')) {
      key = data.replaceFirst('stop_', '');
    } else if (data == 'cancel') {
      if (_activeKeys.contains('send')) {
        key = 'send';
      } else if (_activeKeys.contains('receive')) {
        key = 'receive';
      }
    } else if (data == 'stop') {
      if (_activeKeys.contains('stream')) {
        key = 'stream';
      } else if (_activeKeys.contains('sync')) {
        key = 'sync';
      }
    }
    if (key.isNotEmpty && _activeKeys.contains(key)) {
      _cancelledKeys.add(key);
      onCancelRequested?.call(key);
    }
  }

  /// Request battery optimization exemption.
  static Future<void> requestPermissions() async {
    if (!Platform.isAndroid) return;
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  // ─── Convenience button builders ──────────────────────────────────────────

  static const NotificationButton cancelButton = NotificationButton(
    id: 'cancel',
    text: 'Cancel',
  );

  static const NotificationButton stopButton = NotificationButton(
    id: 'stop',
    text: 'Stop',
  );

  static const NotificationButton cancelSendButton = NotificationButton(
    id: 'cancel_send',
    text: 'Cancel',
  );

  static const NotificationButton cancelReceiveButton = NotificationButton(
    id: 'cancel_receive',
    text: 'Cancel',
  );

  static const NotificationButton stopSyncButton = NotificationButton(
    id: 'stop_sync',
    text: 'Stop',
  );

  static const NotificationButton stopStreamButton = NotificationButton(
    id: 'stop_stream',
    text: 'Stop',
  );
}

// ─── Task isolate entry point ──────────────────────────────────────────────

// Top-level callback — required by flutter_foreground_task.
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_SpeedShareTaskHandler());
}

/// Runs in the background task isolate.
/// Relays notification button presses back to the main isolate.
class _SpeedShareTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(Object data) {}

  /// Fires when the user taps a notification button.
  /// Relays button ID to main isolate.
  @override
  void onNotificationButtonPressed(String id) {
    FlutterForegroundTask.sendDataToMain(id);
  }
}

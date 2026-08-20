import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import 'package:url_launcher/url_launcher.dart';

class NetworkSettingsHelper {
  /// Opens the Hotspot / Tethering settings on any of the 5 platforms.
  static Future<bool> openHotspotSettings({BuildContext? context}) async {
    try {
      if (kIsWeb) return false;

      if (Platform.isAndroid) {
        try {
          await AppSettings.openAppSettings(type: AppSettingsType.hotspot);
          return true;
        } catch (_) {
          try {
            await AppSettings.openAppSettings(type: AppSettingsType.wireless);
            return true;
          } catch (_) {
            await AppSettings.openAppSettings(type: AppSettingsType.settings);
            return true;
          }
        }
      } else if (Platform.isIOS) {
        try {
          final uri = Uri.parse('App-Prefs:root=INTERNET_TETHERING');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return true;
          }
        } catch (_) {}
        try {
          await AppSettings.openAppSettings(type: AppSettingsType.hotspot);
          return true;
        } catch (_) {
          await AppSettings.openAppSettings(type: AppSettingsType.settings);
          return true;
        }
      } else if (Platform.isWindows) {
        try {
          final uri = Uri.parse('ms-settings:network-mobilehotspot');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
            return true;
          }
          final res = await Process.run('explorer.exe', ['ms-settings:network-mobilehotspot']);
          return res.exitCode == 0;
        } catch (_) {
          await Process.run('explorer.exe', ['ms-settings:network']);
          return true;
        }
      } else if (Platform.isMacOS) {
        try {
          // macOS 13+ (Ventura, Sonoma, Sequoia)
          final res = await Process.run('open', ['x-apple.systempreferences:com.apple.Sharing-Settings.extension']);
          if (res.exitCode == 0) return true;
        } catch (_) {}
        try {
          // Legacy macOS
          final res = await Process.run('open', ['/System/Library/PreferencePanes/SharingPref.prefPane']);
          if (res.exitCode == 0) return true;
        } catch (_) {}
        try {
          final uri = Uri.parse('x-apple.systempreferences:com.apple.preference.sharing');
          return await launchUrl(uri);
        } catch (_) {}
      } else if (Platform.isLinux) {
        final commands = [
          ['gnome-control-center', ['wifi']],
          ['nm-connection-editor', <String>[]],
          ['gnome-control-center', ['network']],
          ['systemsettings5', ['kcm_networkmanagement']],
          ['kcmshell6', ['kcm_networkmanagement']],
        ];
        for (var cmd in commands) {
          try {
            final res = await Process.run(cmd[0] as String, cmd[1] as List<String>);
            if (res.exitCode == 0) return true;
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error opening Hotspot settings: $e');
    }

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please open your device settings to turn on Mobile Hotspot.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false;
  }

  /// Opens the Wi-Fi settings on any of the 5 platforms.
  static Future<bool> openWifiSettings({BuildContext? context}) async {
    try {
      if (kIsWeb) return false;

      if (Platform.isAndroid) {
        try {
          await AppSettings.openAppSettings(type: AppSettingsType.wifi);
          return true;
        } catch (_) {
          try {
            await AppSettings.openAppSettings(type: AppSettingsType.wireless);
            return true;
          } catch (_) {
            await AppSettings.openAppSettings(type: AppSettingsType.settings);
            return true;
          }
        }
      } else if (Platform.isIOS) {
        try {
          final uri = Uri.parse('App-Prefs:root=WIFI');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return true;
          }
        } catch (_) {}
        try {
          await AppSettings.openAppSettings(type: AppSettingsType.wifi);
          return true;
        } catch (_) {
          await AppSettings.openAppSettings(type: AppSettingsType.settings);
          return true;
        }
      } else if (Platform.isWindows) {
        try {
          final uri = Uri.parse('ms-settings:network-wifi');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
            return true;
          }
          final res = await Process.run('explorer.exe', ['ms-settings:network-wifi']);
          return res.exitCode == 0;
        } catch (_) {
          await Process.run('explorer.exe', ['ms-settings:network']);
          return true;
        }
      } else if (Platform.isMacOS) {
        try {
          // macOS 13+ (Ventura, Sonoma, Sequoia)
          final res = await Process.run('open', ['x-apple.systempreferences:com.apple.Network-Settings.extension']);
          if (res.exitCode == 0) return true;
        } catch (_) {}
        try {
          // Legacy macOS
          final res = await Process.run('open', ['x-apple.systempreferences:com.apple.preference.network?Wi-Fi']);
          if (res.exitCode == 0) return true;
        } catch (_) {}
        try {
          final uri = Uri.parse('x-apple.systempreferences:com.apple.preference.network');
          return await launchUrl(uri);
        } catch (_) {}
      } else if (Platform.isLinux) {
        final commands = [
          ['gnome-control-center', ['wifi']],
          ['nm-connection-editor', <String>[]],
          ['systemsettings5', ['kcm_networkmanagement']],
          ['kcmshell6', ['kcm_networkmanagement']],
        ];
        for (var cmd in commands) {
          try {
            final res = await Process.run(cmd[0] as String, cmd[1] as List<String>);
            if (res.exitCode == 0) return true;
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error opening Wi-Fi settings: $e');
    }

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please open your device settings to connect to Wi-Fi.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false;
  }
}

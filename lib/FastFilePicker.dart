import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

/// High-performance file picker that uses direct native path resolution on Android
/// to bypass the multi-gigabyte cache copying performed by standard picker plugins.
class FastFilePicker {
  static const MethodChannel _channel = MethodChannel('com.navnit.speedshare/fast_picker');

  /// Picks files using zero-copy native path resolution on Android,
  /// falling back to [FilePicker.platform.pickFiles] on desktop/iOS or on error.
  static Future<List<String>> pickFiles({
    bool allowMultiple = true,
    List<String>? allowedExtensions,
    String? mimeType,
    String? dialogTitle,
  }) async {
    if (Platform.isAndroid) {
      try {
        final List<dynamic>? paths = await _channel.invokeMethod<List<dynamic>>(
          'pickFiles',
          {
            'allowMultiple': allowMultiple,
            'allowedExtensions': allowedExtensions,
            'mimeType': mimeType ?? '*/*',
          },
        );
        if (paths != null) {
          final result = paths.whereType<String>().where((p) => p.isNotEmpty).toList();
          return result;
        }
      } catch (_) {
        // Fallback to standard file_picker if native channel is unavailable
      }
    }

    // Fallback for Desktop (macOS, Windows, Linux), iOS, or on native channel error
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: allowMultiple,
      type: (allowedExtensions != null && allowedExtensions.isNotEmpty)
          ? FileType.custom
          : FileType.any,
      allowedExtensions: allowedExtensions,
      dialogTitle: dialogTitle,
    );

    if (result == null || result.files.isEmpty) return [];
    return result.files
        .map((f) => f.path)
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toList();
  }
}

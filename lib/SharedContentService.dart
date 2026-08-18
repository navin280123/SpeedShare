import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Service responsible for receiving shared content across all platforms:
/// - Android & iOS (via receive_sharing_intent)
/// - Windows, macOS, Linux (via command-line arguments and drag-and-drop)
class SharedContentService {
  static final SharedContentService _instance =
      SharedContentService._internal();
  factory SharedContentService() => _instance;
  SharedContentService._internal();

  final _filesController = StreamController<List<String>>.broadcast();
  Stream<List<String>> get onFilesReceived => _filesController.stream;

  StreamSubscription? _mediaStreamSubscription;
  bool _initialized = false;

  /// Holds pending files if UI hasn't subscribed yet
  List<String> _pendingFiles = [];
  List<String> get pendingFiles => List.unmodifiable(_pendingFiles);

  void clearPendingFiles() {
    _pendingFiles = [];
  }

  /// Initialize listeners for shared intents and process initial launch arguments.
  Future<void> initialize({List<String>? initialArgs}) async {
    if (_initialized) {
      if (initialArgs != null && initialArgs.isNotEmpty) {
        _processCommandLineArgs(initialArgs);
      }
      return;
    }
    _initialized = true;

    // Process CLI arguments (Desktop platforms)
    if (initialArgs != null && initialArgs.isNotEmpty) {
      _processCommandLineArgs(initialArgs);
    }

    // Android & iOS sharing intents
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      _initMobileSharingIntents();
    }
  }

  void _initMobileSharingIntents() {
    try {
      // 1. Listen for incoming shares (files, images, videos, text, urls) while app is open / backgrounded
      _mediaStreamSubscription = ReceiveSharingIntent.instance
          .getMediaStream()
          .listen((List<SharedMediaFile> value) async {
        if (value.isNotEmpty) {
          final paths = await _processSharedMediaFiles(value);
          if (paths.isNotEmpty) {
            emitFiles(paths);
          }
        }
      }, onError: (err) {
        debugPrint('ReceiveSharingIntent getMediaStream error: $err');
      });

      // 2. Handle media shared when app was closed/terminated
      ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) async {
        if (value.isNotEmpty) {
          final paths = await _processSharedMediaFiles(value);
          if (paths.isNotEmpty) {
            emitFiles(paths);
          }
          ReceiveSharingIntent.instance.reset();
        }
      }).catchError((err) {
        debugPrint('ReceiveSharingIntent getInitialMedia error: $err');
      });
    } catch (e) {
      debugPrint('SharedContentService mobile init error: $e');
    }
  }

  Future<List<String>> _processSharedMediaFiles(List<SharedMediaFile> files) async {
    List<String> validPaths = [];
    for (final media in files) {
      if (media.path.isEmpty) continue;
      
      // If it's plain text or URL and not a valid file path on disk, save it as a text file
      if (media.type == SharedMediaType.text || media.type == SharedMediaType.url) {
        final file = File(media.path);
        if (file.existsSync()) {
          validPaths.add(file.path);
        } else {
          final savedPath = await _saveSharedTextToFile(media.path);
          if (savedPath != null) {
            validPaths.add(savedPath);
          }
        }
      } else {
        validPaths.add(media.path);
      }
    }
    return validPaths;
  }

  /// Convert shared text/link to a shareable text file so it flows through SpeedShare's file transfer
  Future<String?> _saveSharedTextToFile(String text) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tempDir.path}/shared_text_$timestamp.txt');
      await file.writeAsString(text);
      return file.path;
    } catch (e) {
      debugPrint('Error saving shared text: $e');
      return null;
    }
  }

  /// Process command-line arguments (file paths) on Desktop platforms
  void _processCommandLineArgs(List<String> args) {
    List<String> validFilePaths = [];
    for (final arg in args) {
      // Ignore flags like -d, --release, etc.
      if (arg.startsWith('-')) continue;
      
      String cleanPath = arg;
      if (cleanPath.startsWith('file://')) {
        cleanPath = Uri.parse(cleanPath).toFilePath();
      }
      final file = File(cleanPath);
      if (file.existsSync()) {
        validFilePaths.add(file.absolute.path);
      } else {
        final dir = Directory(cleanPath);
        if (dir.existsSync()) {
          // If a directory was shared/dropped, collect files inside or directory path
          validFilePaths.add(dir.absolute.path);
        }
      }
    }

    if (validFilePaths.isNotEmpty) {
      emitFiles(validFilePaths);
    }
  }

  /// Emit file paths to listeners or save to pending queue
  void emitFiles(List<String> paths) {
    if (paths.isEmpty) return;
    _pendingFiles = List.from(paths);
    _filesController.add(paths);
  }

  void dispose() {
    _mediaStreamSubscription?.cancel();
    _filesController.close();
  }
}

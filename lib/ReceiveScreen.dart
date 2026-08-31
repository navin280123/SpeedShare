import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speedsharemob/DeviceNameManager.dart';
import 'package:speedsharemob/NetworkStatusWidget.dart';
import 'package:speedsharemob/SpeedShareAppBar.dart';
import 'package:speedsharemob/NotificationService.dart';
import 'package:speedsharemob/BackgroundService.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => ReceiveScreenState();
}

class ReceiveScreenState extends State<ReceiveScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  ServerSocket? serverSocket;
  RawDatagramSocket? _discoverySocket;
  Timer? _announcementTimer;
  String receivedFileName = '';
  double progress = 0.0;
  String ipAddress = '';
  String computerName = '';
  int fileSize = 0;
  int bytesReceived = 0;
  File? receivedFile;
  bool isReceiving = false;
  List<Map<String, dynamic>> receivedFiles = [];
  String downloadDirectoryPath = '';
  bool isLoadingIp = true;
  bool isReceivingAnimation = false;
  bool _isFilesExpanded = false; // Default collapsed

  // Active in-progress download tracking for clean app termination
  IOSink? _activeSink;
  File? _activeTmpFile;
  String? _finalDestinationPath;
  int _activeWrittenBytes = 0;
  int _activeExpectedFileSize = 0;

  // Bug 3: multi-file batch tracking
  int _totalFilesInBatch = 0;
  int _currentFileInBatch = 0;
  Timer? _idleResetTimer; // Bug 4: auto-clear progress UI after completion

  // Animation controller
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _initializeAndAutoStart();
  }

  Future<void> _initializeAndAutoStart() async {
    await _getComputerName();
    _getDownloadsDirectory();
    await _getIpAddress();
    if (mounted && !isReceiving) {
      startReceiving(showNotification: false);
    }
  }

  Future<Directory> _getDefaultDownloadsDirectory() async {
    if (Platform.isAndroid) {
      return Directory('/storage/emulated/0/Download');
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final downloadsDir = await getDownloadsDirectory();
      return downloadsDir ?? await getApplicationDocumentsDirectory();
    } else {
      return await getApplicationDocumentsDirectory();
    }
  }

  void _getDownloadsDirectory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedPath = prefs.getString('downloadPath');

      Directory targetDirectory;
      String speedsharePath;

      if (savedPath != null && savedPath.trim().isNotEmpty) {
        targetDirectory = Directory(savedPath.trim());
        try {
          if (!await targetDirectory.exists()) {
            await targetDirectory.create(recursive: true);
          }
          speedsharePath = targetDirectory.path;
        } catch (e) {
          debugPrint('Custom download path inaccessible ($savedPath): $e');
          final defaultDir = await _getDefaultDownloadsDirectory();
          speedsharePath = '${defaultDir.path}/speedshare';
          targetDirectory = Directory(speedsharePath);
          if (!await targetDirectory.exists()) {
            await targetDirectory.create(recursive: true);
          }
        }
      } else {
        final defaultDir = await _getDefaultDownloadsDirectory();
        speedsharePath = '${defaultDir.path}/speedshare';
        targetDirectory = Directory(speedsharePath);
        if (!await targetDirectory.exists()) {
          await targetDirectory.create(recursive: true);
        }
      }

      if (mounted) {
        setState(() {
          downloadDirectoryPath = speedsharePath;
        });
      }
      _loadReceivedFiles(Directory(speedsharePath));
    } catch (e) {
      debugPrint('Error getting downloads directory: $e');
      // Fallback to app documents directory on any error
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final speedsharePath = '${appDir.path}/speedshare';
        final speedshareDirectory = Directory(speedsharePath);
        if (!await speedshareDirectory.exists()) {
          await speedshareDirectory.create(recursive: true);
        }
        if (mounted) {
          setState(() {
            downloadDirectoryPath = speedsharePath;
          });
        }
        _loadReceivedFiles(speedshareDirectory);
      } catch (_) {}
    }
  }

  void _loadReceivedFiles(Directory directory) async {
    try {
      List<FileSystemEntity> allEntities = await directory.list().toList();

      // Clean up orphaned .speedshare_tmp files from previous killed sessions
      for (var entity in allEntities) {
        if (entity is File && entity.path.endsWith('.speedshare_tmp')) {
          try {
            await entity.delete();
          } catch (e) {
            debugPrint('Error deleting orphaned temp file ${entity.path}: $e');
          }
        }
      }

      // Re-fetch files excluding any remaining temp files
      List<FileSystemEntity> files = (await directory.list().toList())
          .where((f) => f is File && !f.path.endsWith('.speedshare_tmp'))
          .toList();

      files.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
      List<Map<String, dynamic>> filesList = [];
      for (var file in files) {
        if (file is File) {
          filesList.add({
            'name': p.basename(file.path),
            'path': file.path,
            'size': file.lengthSync(),
            'date': file.statSync().modified.toString(),
          });
        }
      }
      if (mounted) {
        setState(() {
          receivedFiles = filesList;
        });
      }
    } catch (e) {
      debugPrint('Error loading received files: $e');
    }
  }

  Future<void> _getIpAddress() async {
    setState(() {
      isLoadingIp = true;
    });
    try {
      final interfaces = await NetworkInterface.list();
      // First pass: find physical Wi-Fi / Ethernet / Hotspot interfaces
      for (var interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (name.contains('wlan') ||
            name.contains('wi-fi') ||
            name.contains('eth') ||
            name.contains('en') ||
            name.contains('ap') ||
            name.contains('softap') ||
            name.contains('bridge') ||
            name.contains('rndis') ||
            name.contains('swlan') ||
            name.contains('local area connection')) {
          for (var addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4 &&
                !addr.address.startsWith('127.') &&
                !addr.address.startsWith('169.254.') &&
                !addr.address.startsWith('0.')) {
              if (mounted) {
                setState(() {
                  ipAddress = addr.address;
                  isLoadingIp = false;
                });
              }
              return;
            }
          }
        }
      }

      // Second pass: any valid non-loopback, non-cellular IPv4
      for (var interface in interfaces) {
        final name = interface.name.toLowerCase();
        final isCellular = name.startsWith('rmnet') ||
            name.startsWith('ccmni') ||
            name.startsWith('pdp') ||
            name.startsWith('dummy') ||
            name.startsWith('seth') ||
            name.startsWith('wwan') ||
            name.startsWith('cellular') ||
            name.startsWith('radio') ||
            name.startsWith('ipa') ||
            name.startsWith('v4-rmnet') ||
            name.startsWith('usb_rmnet');
        if (name.contains('lo') || isCellular) continue;
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.address.startsWith('127.') &&
              !addr.address.startsWith('169.254.') &&
              !addr.address.startsWith('0.')) {
            if (mounted) {
              setState(() {
                ipAddress = addr.address;
                isLoadingIp = false;
              });
            }
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting IP address: $e');
    }
    if (mounted) {
      setState(() {
        ipAddress = 'Not available';
        isLoadingIp = false;
      });
    }
  }

  Future<void> _getComputerName() async {
    try {
      final name = await DeviceNameManager.getDeviceName();
      if (mounted) {
        setState(() {
          computerName = name;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          computerName = 'SpeedShare Device';
        });
      }
    }
  }

  void startReceiving({bool showNotification = true}) async {
    if (isReceiving && serverSocket != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final listenPort = prefs.getInt('port') ?? 8080;

      try {
        serverSocket?.close();
      } catch (_) {}
      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, listenPort, shared: true);

      try {
        _discoverySocket?.close();
      } catch (_) {}

      try {
        _discoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          8081,
          reuseAddress: true,
        );
      } catch (_) {
        _discoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          8081,
        );
      }

      _discoverySocket?.broadcastEnabled = true;

      // Join UDP Multicast group for seamless discovery across Wi-Fi networks
      try {
        _discoverySocket?.joinMulticast(InternetAddress('239.255.255.250'));
      } catch (e) {
        debugPrint('Multicast join error: $e');
      }

      final interfaces = await NetworkInterface.list();
      final localIps = interfaces
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .toSet();
      localIps.addAll(['127.0.0.1', '::1']);

      _discoverySocket?.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _discoverySocket?.receive();
          if (datagram != null) {
            // Ignore self discovery packets
            if (localIps.contains(datagram.address.address)) {
              return;
            }

            final message = utf8.decode(datagram.data);
            if (message == 'SPEEDSHARE_DISCOVERY') {
              final responseMessage = utf8.encode(
                'SPEEDSHARE_RESPONSE:$computerName:READY',
              );
              // Send direct response
              try {
                _discoverySocket?.send(
                  responseMessage,
                  datagram.address,
                  datagram.port,
                );
              } catch (_) {}
              // Send to multicast group
              try {
                _discoverySocket?.send(
                  responseMessage,
                  InternetAddress('239.255.255.250'),
                  8081,
                );
              } catch (_) {}
            }
          }
        }
      }, onError: (e) {
        if (e is SocketException &&
            (e.osError?.errorCode == 65 || e.osError?.errorCode == 51)) {
          // Ignore expected "No route to host" / "Network unreachable" on inactive virtual interfaces
          return;
        }
        debugPrint('UDP discovery socket error: $e');
      });

      setState(() {
        isReceiving = true;
        isReceivingAnimation = true;
      });
      _animationController.repeat(reverse: true);
      _startAnnouncing();

      // Keep CPU awake and prevent Android from killing background networking
      BackgroundService.start(
        key: 'receive',
        title: 'SpeedShare — Receiving',
        body: 'Waiting for incoming files…',
        buttons: [BackgroundService.cancelReceiveButton],
      );

      if (showNotification && mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text('Ready to receive files'),
              ],
            ),
            backgroundColor: const Color(0xFF2AB673),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(20),
          ),
        );
      }

      serverSocket!.listen((client) {
        // Protocol state variables
        bool receivingMetadata = true;
        int metadataSize = 0;
        List<int> incomingBuffer = [];
        int expectedFileSize = 0;
        String expectedFileName = '';
        int writtenFileBytes = 0;
        DateTime lastProgressTime = DateTime.now();
        DateTime lastNotificationUpdateTime = DateTime.now();

        client.listen((data) async {
          // Check for TCP discovery probe
          if (data.length >= 15 &&
              String.fromCharCodes(data.sublist(0, 15))
                  .startsWith('SPEEDSHARE_PING')) {
            client.write('DEVICE_NAME:$computerName');
            await client.flush();
            client.destroy();
            return;
          }

          if (receivingMetadata) {
            incomingBuffer.addAll(data);

            if (metadataSize == 0 && incomingBuffer.length >= 4) {
              final byteData = ByteData.sublistView(
                Uint8List.fromList(incomingBuffer.sublist(0, 4)),
              );
              metadataSize = byteData.getInt32(0);
              if (metadataSize <= 0 || metadataSize > 65536) {
                debugPrint('Invalid metadata size: $metadataSize');
                client.destroy();
                return;
              }
            }

            if (metadataSize > 0 && incomingBuffer.length >= 4 + metadataSize) {
              final metadataJson = utf8.decode(
                incomingBuffer.sublist(4, 4 + metadataSize),
              );
              final metadata =
                  json.decode(metadataJson) as Map<String, dynamic>;
              expectedFileName = sanitizeFileName(
                p.basename(metadata['fileName']),
              );
              expectedFileSize = metadata['fileSize'];
              writtenFileBytes = 0;
              lastProgressTime = DateTime.now();
              lastNotificationUpdateTime = DateTime.now();
              _activeExpectedFileSize = expectedFileSize;
              _activeWrittenBytes = 0;

              // Bug 3: read batch info sent by FileSenderScreen
              final totalFiles = (metadata['totalFiles'] as int?) ?? 1;
              final fileIndex = (metadata['fileIndex'] as int?) ?? 0;
              if (mounted) {
                setState(() {
                  _totalFilesInBatch = totalFiles;
                  _currentFileInBatch = fileIndex + 1;
                });
              }

              // Update notification with newly starting file
              final batchInfo = _totalFilesInBatch > 1 ? ' ($_currentFileInBatch/$_totalFilesInBatch)' : '';
              BackgroundService.update(
                title: 'SpeedShare — Receiving$batchInfo',
                body: '$expectedFileName · 0% (0 B of ${_formatFileSize(expectedFileSize)})',
                buttons: [BackgroundService.cancelReceiveButton],
              );

              if (mounted) {
                setState(() {
                  receivedFileName = expectedFileName;
                  fileSize = expectedFileSize;
                  bytesReceived = 0;
                  progress = 0.0;
                });
              }

              // Compute target final path (with auto-renaming if file exists)
              String finalPath = '$downloadDirectoryPath/$expectedFileName';
              File targetFile = File(finalPath);
              if (await targetFile.exists()) {
                String nameWithoutExt = p.basenameWithoutExtension(expectedFileName);
                String ext = p.extension(expectedFileName);
                int count = 1;
                while (await targetFile.exists()) {
                  expectedFileName = '$nameWithoutExt ($count)$ext';
                  finalPath = '$downloadDirectoryPath/$expectedFileName';
                  targetFile = File(finalPath);
                  count++;
                }
              }

              _finalDestinationPath = finalPath;

              // Write to temporary file until download completion
              String tmpPath = '$finalPath.speedshare_tmp';
              _activeTmpFile = File(tmpPath);
              if (await _activeTmpFile!.exists()) {
                try {
                  await _activeTmpFile!.delete();
                } catch (_) {}
              }

              _activeSink = _activeTmpFile!.openWrite(mode: FileMode.write);
              receivingMetadata = false;
              client.write('READY_FOR_FILE_DATA');

              if (incomingBuffer.length > 4 + metadataSize) {
                final fileData = incomingBuffer.sublist(4 + metadataSize);
                _activeSink?.add(fileData);
                writtenFileBytes += fileData.length;
                _activeWrittenBytes = writtenFileBytes;
                if (mounted) {
                  setState(() {
                    bytesReceived = writtenFileBytes;
                    progress = expectedFileSize > 0
                        ? (writtenFileBytes / expectedFileSize).clamp(0.0, 0.999)
                        : 0.0;
                  });
                }
              }
              incomingBuffer.clear();
            }
          } else {
            // Check if user tapped Cancel in notification
            if (BackgroundService.isCancelled('receive')) {
              BackgroundService.clearCancel('receive');
              _cleanupActiveDownload(deleteTempFile: true);
              try { client.destroy(); } catch (_) {}
              stopReceiving();
              return;
            }

            // This is file data
            _activeSink?.add(data);
            writtenFileBytes += data.length;
            _activeWrittenBytes = writtenFileBytes;

            final now = DateTime.now();
            if (writtenFileBytes < expectedFileSize) {
              if (now.difference(lastProgressTime).inMilliseconds >= 30 &&
                  mounted) {
                setState(() {
                  bytesReceived = writtenFileBytes;
                  progress = expectedFileSize > 0
                      ? (writtenFileBytes / expectedFileSize).clamp(0.0, 0.999)
                      : 0.0;
                });
                lastProgressTime = now;
              }

              // Update notification progress every ~500ms
              if (now.difference(lastNotificationUpdateTime).inMilliseconds >= 500) {
                lastNotificationUpdateTime = now;
                final pct = expectedFileSize > 0
                    ? (writtenFileBytes / expectedFileSize * 100).clamp(0, 100).toStringAsFixed(0)
                    : '0';
                final batchInfo = _totalFilesInBatch > 1 ? ' ($_currentFileInBatch/$_totalFilesInBatch)' : '';
                BackgroundService.update(
                  title: 'SpeedShare — Receiving$batchInfo',
                  body: '$expectedFileName · $pct% (${_formatFileSize(writtenFileBytes)} of ${_formatFileSize(expectedFileSize)})',
                  buttons: [BackgroundService.cancelReceiveButton],
                );
              }
            }

            // File transfer complete
            if (writtenFileBytes >= expectedFileSize && expectedFileSize > 0) {
              await _activeSink?.flush();
              await _activeSink?.close();
              _activeSink = null;

              // Rename temporary file to final target filename
              String savedPath = _finalDestinationPath ?? '$downloadDirectoryPath/$expectedFileName';
              if (_activeTmpFile != null && await _activeTmpFile!.exists()) {
                await _activeTmpFile!.rename(savedPath);
              }

              receivedFiles.insert(0, {
                'name': expectedFileName,
                'size': expectedFileSize,
                'path': savedPath,
                'date': DateTime.now().toString(),
              });

              NotificationService().showTransferCompletedNotification(
                fileName: expectedFileName,
                isReceived: true,
              );

              if (mounted) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: LayoutBuilder(
                      builder: (context, constraints) {
                        bool isWide = constraints.maxWidth > 400;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.white),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'File received: $expectedFileName',
                                overflow: TextOverflow.ellipsis,
                                maxLines: isWide ? 2 : 1,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    backgroundColor: const Color(0xFF2AB673),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    margin: const EdgeInsets.all(20),
                    action: SnackBarAction(
                      label: 'Open',
                      textColor: Colors.white,
                      onPressed: () {
                        _openFile(savedPath);
                      },
                    ),
                    duration: const Duration(seconds: 2, milliseconds: 500),
                  ),
                );
              }

              client.write('TRANSFER_COMPLETE');
              receivedFile = null;
              receivingMetadata = true;
              metadataSize = 0;
              incomingBuffer.clear();
              _activeTmpFile = null;
              _finalDestinationPath = null;
              _activeWrittenBytes = 0;
              _activeExpectedFileSize = 0;

              // Bug 4: schedule auto-reset of progress UI after 3s
              _idleResetTimer?.cancel();
              _idleResetTimer = Timer(const Duration(seconds: 3), () {
                if (mounted) {
                  setState(() {
                    receivedFileName = '';
                    fileSize = 0;
                    bytesReceived = 0;
                    progress = 0.0;
                    _totalFilesInBatch = 0;
                    _currentFileInBatch = 0;
                  });
                }
              });

              if (mounted) {
                setState(() {
                  receivedFileName = '';
                  fileSize = 0;
                  bytesReceived = 0;
                  progress = 0.0;
                });
              }
            }
          }
        }, onError: (e) {
          debugPrint('TCP client socket error: $e');
          if (writtenFileBytes < expectedFileSize) {
            _cleanupActiveDownload(deleteTempFile: true);
          }
          client.close();
        }, onDone: () {
          if (writtenFileBytes < expectedFileSize) {
            _cleanupActiveDownload(deleteTempFile: true);
          }
          client.close();
        });
      }, onError: (e) {
        debugPrint('Server socket error: $e');
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Text('Error: $e'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(20),
        ),
      );
      setState(() {
        isReceiving = false;
        isReceivingAnimation = false;
      });
      _animationController.stop();
      _animationController.reset();
    }
  }

  Future<void> _cleanupActiveDownload({bool deleteTempFile = true}) async {
    try {
      if (_activeSink != null) {
        await _activeSink?.close();
        _activeSink = null;
      }
      if (deleteTempFile && _activeTmpFile != null) {
        if (await _activeTmpFile!.exists()) {
          await _activeTmpFile!.delete();
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up active download: $e');
    } finally {
      _activeSink = null;
      _activeTmpFile = null;
      _finalDestinationPath = null;
      _activeWrittenBytes = 0;
      _activeExpectedFileSize = 0;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only abort incomplete downloads when the app is truly killed (detached),
    // NOT when it is merely paused (screen off / Home pressed).
    // This lets receive operations survive backgrounding.
    if (state == AppLifecycleState.detached) {
      if (_activeWrittenBytes < _activeExpectedFileSize) {
        _cleanupActiveDownload(deleteTempFile: true);
      }
      BackgroundService.stop(key: 'receive');
    }
  }

  void stopReceiving() {
    _cleanupActiveDownload(deleteTempFile: true);
    _stopAnnouncing();
    serverSocket?.close();
    _discoverySocket?.close();
    _animationController.stop();
    _animationController.reset();
    BackgroundService.stop(key: 'receive');
    setState(() {
      isReceiving = false;
      isReceivingAnimation = false;
      progress = 0.0;
      receivedFileName = '';
      fileSize = 0;
      bytesReceived = 0;
      receivedFile = null;
    });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.info_rounded, color: Colors.white),
            SizedBox(width: 10),
            Text('Stopped receiving files'),
          ],
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  void _openFile(String filePath) async {
    try {
      final result = await OpenFile.open(filePath);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text('Could not open file: ${result.message}'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Text('Error opening file: $e'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void _openDownloadsFolder() async {
    try {
      final dir = Directory(downloadDirectoryPath);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }

      if (Platform.isWindows) {
        await Process.run('explorer.exe', [downloadDirectoryPath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [downloadDirectoryPath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [downloadDirectoryPath]);
      } else {
        // Android & iOS
        final result = await OpenFile.open(downloadDirectoryPath);
        if (result.type != ResultType.done) {
          // If the system couldn't open directly with a registered folder app, copy to clipboard
          await Clipboard.setData(ClipboardData(text: downloadDirectoryPath));
          if (!mounted) return;
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.folder_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Folder path copied: $downloadDirectoryPath'),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF4E6AF3),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text('Could not open folder: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void _copyIpToClipboard() async {
    await Clipboard.setData(ClipboardData(text: ipAddress));
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 10),
            Text('IP address copied to clipboard'),
          ],
        ),
        backgroundColor: const Color(0xFF4E6AF3),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(String dateString) {
    DateTime date = DateTime.parse(dateString);
    return DateFormat('dd MMM yyyy, HH:mm').format(date);
  }

  void _startAnnouncing() {
    _announcementTimer?.cancel();
    _announcementTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_discoverySocket == null || !isReceiving) return;
      try {
        final message = utf8.encode('SPEEDSHARE_RESPONSE:$computerName:READY');
        
        // Broadcast globally
        try {
          _discoverySocket!.send(
            message,
            InternetAddress('255.255.255.255'),
            8081,
          );
        } catch (_) {}

        // Multicast
        try {
          _discoverySocket!.send(
            message,
            InternetAddress('239.255.255.250'),
            8081,
          );
        } catch (_) {}

        // Broadcast to subnets
        final interfaces = await NetworkInterface.list();
        for (var interface in interfaces) {
          if (interface.name.toLowerCase().contains('lo')) continue;
          for (var addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4) {
              final parts = addr.address.split('.');
              if (parts.length == 4) {
                final subnet = parts.sublist(0, 3).join('.');
                try {
                  _discoverySocket!.send(
                    message,
                    InternetAddress('$subnet.255'),
                    8081,
                  );
                } catch (_) {}
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Announcement error: $e');
      }
    });
  }

  void _stopAnnouncing() {
    _announcementTimer?.cancel();
    _announcementTimer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleResetTimer?.cancel();
    _cleanupActiveDownload(deleteTempFile: true);
    _stopAnnouncing();
    _animationController.dispose();
    serverSocket?.close();
    _discoverySocket?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SpeedShareAppBar(
        title: 'Receive Files',
        subtitle: 'Wait for incoming file transfers',
        icon: Icons.download_rounded,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NetworkStatusWidget(
                    mode: NetworkWidgetMode.receiver,
                    onRetry: _getIpAddress,
                  ),
                  // Status section with IP and controls
                  _buildStatusSection(),

              // Current transfer progress card
              if (receivedFileName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: _buildCurrentTransferCard(),
                ),

              // Files section (collapsible)
              if (_isFilesExpanded)
                Expanded(child: _buildFilesSection())
              else
                _buildFilesSection(),
            ],
          ),
        ),
        ),
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status indicator
            Row(
              children: [
                if (isReceivingAnimation)
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2AB673),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2AB673).withValues(alpha: 0.3),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color:
                          isReceiving ? const Color(0xFF2AB673) : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  isReceiving ? 'Listening for files' : 'Not receiving',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isReceiving ? const Color(0xFF2AB673) : null,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Device details
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    'Device Name',
                    computerName,
                    Icons.smartphone_rounded,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildInfoItem(
                    'IP Address',
                    isLoadingIp ? 'Loading...' : ipAddress,
                    Icons.wifi_rounded,
                    onTap: isLoadingIp ? null : _copyIpToClipboard,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Control buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isReceiving ? null : startReceiving,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Start Receiving'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF2AB673),
                      disabledBackgroundColor: Colors.grey[400],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: isReceiving ? stopReceiving : null,
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: const Text('Stop'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(
    String label,
    String value,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:
                Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[800]
                    : Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF2AB673)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[400]
                          : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              InkWell(
                onTap: onTap,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onTap != null)
                      Icon(
                        Icons.copy,
                        size: 14,
                        color: const Color(0xFF2AB673),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentTransferCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4E6AF3).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.downloading_rounded,
                    color: Color(0xFF4E6AF3),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Current Transfer',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                // Bug 3: show 'File X of Y' badge when batch > 1
                if (_totalFilesInBatch > 1) ...([
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4E6AF3).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'File $_currentFileInBatch of $_totalFilesInBatch',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4E6AF3),
                      ),
                    ),
                  ),
                ]),
              ],
            ),

            const SizedBox(height: 16),

            // File details
            Row(
              children: [
                _getFileTypeIcon(receivedFileName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        receivedFileName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${_formatFileSize(bytesReceived)} of ${_formatFileSize(fileSize)}',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).brightness == Brightness.dark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress.clamp(0.01, 1.0) : null,
                backgroundColor:
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[700]
                        : Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF4E6AF3),
                ),
                minHeight: 6,
              ),
            ),

            const SizedBox(height: 8),

            // Progress percentage
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF4E6AF3),
                  ),
                ),
                const Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF4E6AF3),
                        ),
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Receiving...',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF4E6AF3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilesSection() {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: _isFilesExpanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isFilesExpanded = !_isFilesExpanded;
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4E6AF3).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      size: 20,
                      color: Color(0xFF4E6AF3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Received Files',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[800]
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${receivedFiles.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[300]
                            : Colors.grey[700],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (receivedFiles.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.folder_open_rounded, size: 20),
                      tooltip: 'Open Folder',
                      onPressed: _openDownloadsFolder,
                      color: const Color(0xFF4E6AF3),
                    ),
                  Icon(
                    _isFilesExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
          if (_isFilesExpanded) ...[
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: _buildFilesList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilesList() {
    if (receivedFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.asset(
              'assets/receive.json',
              height: 120,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.folder_open,
                  size: 60,
                  color: Colors.grey[300],
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              'No files received yet',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color:
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[400]
                        : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Files you receive will appear here',
              style: TextStyle(
                fontSize: 14,
                color:
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[500]
                        : Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: receivedFiles.length,
      itemBuilder: (context, index) {
        final file = receivedFiles[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: _getFileTypeIcon(file['name']),
            title: Text(
              file['name'],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  _formatFileSize(file['size']),
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  _formatDate(file['date']),
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[500]
                            : Colors.grey[600],
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () => _openFile(file['path']),
              tooltip: 'Open',
              iconSize: 18,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF4E6AF3).withValues(alpha: 0.1),
                foregroundColor: const Color(0xFF4E6AF3),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _getFileTypeIcon(String fileName) {
    IconData iconData;
    Color iconColor;

    if (fileName.endsWith('.jpg') ||
        fileName.endsWith('.jpeg') ||
        fileName.endsWith('.png') ||
        fileName.endsWith('.gif')) {
      iconData = Icons.image_rounded;
      iconColor = Colors.blue;
    } else if (fileName.endsWith('.mp4') ||
        fileName.endsWith('.avi') ||
        fileName.endsWith('.mov')) {
      iconData = Icons.video_file_rounded;
      iconColor = Colors.red;
    } else if (fileName.endsWith('.mp3') ||
        fileName.endsWith('.wav') ||
        fileName.endsWith('.flac')) {
      iconData = Icons.audio_file_rounded;
      iconColor = Colors.purple;
    } else if (fileName.endsWith('.pdf')) {
      iconData = Icons.picture_as_pdf_rounded;
      iconColor = Colors.red;
    } else if (fileName.endsWith('.doc') ||
        fileName.endsWith('.docx') ||
        fileName.endsWith('.txt')) {
      iconData = Icons.description_rounded;
      iconColor = Colors.blue;
    } else if (fileName.endsWith('.xls') ||
        fileName.endsWith('.xlsx') ||
        fileName.endsWith('.csv')) {
      iconData = Icons.table_chart_rounded;
      iconColor = const Color(0xFF2AB673);
    } else if (fileName.endsWith('.ppt') || fileName.endsWith('.pptx')) {
      iconData = Icons.slideshow_rounded;
      iconColor = Colors.orange;
    } else if (fileName.endsWith('.zip') ||
        fileName.endsWith('.rar') ||
        fileName.endsWith('.7z')) {
      iconData = Icons.folder_zip_rounded;
      iconColor = Colors.amber;
    } else {
      iconData = Icons.insert_drive_file_rounded;
      iconColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(iconData, color: iconColor, size: 24),
    );
  }
}

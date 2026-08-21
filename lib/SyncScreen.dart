import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:mime/mime.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speedsharemob/PermissionManager.dart';
import 'package:speedsharemob/DeviceNameManager.dart';
import 'package:speedsharemob/NetworkStatusWidget.dart';
import 'package:speedsharemob/SpeedShareAppBar.dart';
import 'package:speedsharemob/NotificationService.dart';

enum SyncTabMode { connect, sync }

class ConnectedClient {
  final String ip;
  final String name;
  DateTime lastActive;
  String lastAction;
  int requestCount;

  ConnectedClient({
    required this.ip,
    required this.name,
    required this.lastActive,
    required this.lastAction,
    this.requestCount = 1,
  });
}

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => SyncScreenState();
}

class SyncScreenState extends State<SyncScreen> with TickerProviderStateMixin {
  // Mode selection: Connect vs Sync
  SyncTabMode _activeTab = SyncTabMode.connect;

  // Storage Server
  HttpServer? _storageServer;
  RawDatagramSocket? _syncDiscoverySocket;
  String? _accessCode;
  bool _isStorageSharing = false;
  List<String> _sharedPaths = [];
  DateTimeRange? _hostCameraDateRange;
  final Map<String, ConnectedClient> _connectedClients = {};
  
  // Storage Browser
  final List<SyncDevice> _availableDevices = [];
  bool _isDiscovering = false;
  Timer? _discoveryTimer;
  
  // UI State
  SyncDevice? _selectedDevice;
  List<RemoteFileInfo> _remoteFiles = [];
  bool _isBrowsingFiles = false;
  bool _isLoadingRemoteFiles = false;
  String _currentRemotePath = '/';
  DateTimeRange? _selectedDateRange;
  final List<DownloadTask> _downloadQueue = [];
  final Map<String, String> _devicePins = {};
  
  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeSync();
    _loadSettings();
    _startDiscovery();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _discoveryTimer?.cancel();
    _syncDiscoverySocket?.close();
    _storageServer?.close(force: true);
    super.dispose();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initializeSync() async {
    try {
      // Request permissions first
      bool hasPermissions = await PermissionManager().requestAppPermissions();
      if (!hasPermissions) {
        _showErrorSnackBar('Storage permissions required for sync feature');
        return;
      }

      // Initialize sync discovery socket
      try {
        _syncDiscoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          8083,
          reuseAddress: true,
        );
      } catch (_) {
        _syncDiscoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          8083,
        );
      }
      _syncDiscoverySocket!.broadcastEnabled = true;
      try {
        _syncDiscoverySocket!.joinMulticast(InternetAddress('239.255.255.250'));
      } catch (_) {}
      
      _syncDiscoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _syncDiscoverySocket!.receive();
          if (datagram != null) {
            _handleSyncDiscovery(datagram);
          }
        }
      }, onError: (e) {
        if (e is SocketException &&
            (e.osError?.errorCode == 65 || e.osError?.errorCode == 51)) {
          // Ignore expected "No route to host" / "Network unreachable" on inactive virtual interfaces
          return;
        }
        debugPrint('Sync discovery socket error: $e');
      });
    } catch (e) {
      debugPrint('Error initializing sync: $e');
    }
  }

  Future<bool> _isSelfDevice(String incomingIp, String? incomingName) async {
    if (incomingIp == '127.0.0.1' || incomingIp == '::1') return true;
    try {
      final myName = await DeviceNameManager.getDeviceName();
      if (incomingName != null && incomingName.trim().isNotEmpty && incomingName == myName) {
        return true;
      }
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.address == incomingIp) {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  void _handleSyncDiscovery(Datagram datagram) async {
    try {
      final message = utf8.decode(datagram.data);
      final data = json.decode(message) as Map<String, dynamic>;
      
      final senderIp = datagram.address.address;
      final senderName = data['deviceName'] as String?;

      // Ignore packets from self device
      if (await _isSelfDevice(senderIp, senderName)) {
        return;
      }

      if (data['type'] == 'SPEEDSHARE_SYNC_GOODBYE') {
        if (mounted) {
          setState(() {
            _availableDevices.removeWhere((d) => d.ip == senderIp);
          });
        }
        return;
      } else if (data['type'] == 'SPEEDSHARE_SYNC_PROBE') {
        // If this device is sharing storage, respond immediately to probe
        if (_isStorageSharing) {
          _sendSyncAnnouncement();
        }
      } else if (data['type'] == 'SPEEDSHARE_SYNC_ANNOUNCE') {
        final device = SyncDevice(
          name: data['deviceName'] ?? 'Unknown Device',
          ip: senderIp,
          port: data['storagePort'] ?? 8082,
          accessCode: data['accessCode'] ?? '',
          capabilities: List<String>.from(data['capabilities'] ?? []),
          lastSeen: DateTime.now(),
        );

        if (mounted) {
          setState(() {
            _availableDevices.removeWhere((d) => d.ip == device.ip);
            _availableDevices.add(device);
          });
        }
      }
    } catch (e) {
      debugPrint('Error handling sync discovery: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPaths = prefs.getStringList('sync_shared_paths') ?? [];
      
      // For mobile, add default shared directories
      if (savedPaths.isEmpty) {
        final List<String> defaultPaths = [];
        
        try {
          // Add platform-appropriate default directories
          if (Platform.isAndroid) {
            defaultPaths.add('/storage/emulated/0/Download');
            defaultPaths.add('/storage/emulated/0/DCIM/Camera');
            defaultPaths.add('/storage/emulated/0/Pictures');
          } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
            // Use system Downloads directory for desktop
            final downloadsDir = await getDownloadsDirectory();
            if (downloadsDir != null) {
              defaultPaths.add(downloadsDir.path);
            } else {
              final documentsDir = await getApplicationDocumentsDirectory();
              defaultPaths.add(documentsDir.path);
            }
          } else {
            // iOS — app documents directory (sandboxed)
            final documentsDir = await getApplicationDocumentsDirectory();
            defaultPaths.add(documentsDir.path);
          }
        } catch (e) {
          debugPrint('Error getting default directories: $e');
        }
        
        setState(() {
          _sharedPaths = defaultPaths;
        });
      } else {
        setState(() {
          _sharedPaths = savedPaths;
        });
      }
    } catch (e) {
      debugPrint('Error loading sync settings: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final startDateStr = prefs.getString('sync_camera_start_date');
      final endDateStr = prefs.getString('sync_camera_end_date');
      if (startDateStr != null && endDateStr != null) {
        final start = DateTime.tryParse(startDateStr);
        final end = DateTime.tryParse(endDateStr);
        if (start != null && end != null) {
          setState(() {
            _hostCameraDateRange = DateTimeRange(start: start, end: end);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('sync_shared_paths', _sharedPaths);
      if (_hostCameraDateRange != null) {
        await prefs.setString(
          'sync_camera_start_date',
          _hostCameraDateRange!.start.toIso8601String(),
        );
        await prefs.setString(
          'sync_camera_end_date',
          _hostCameraDateRange!.end.toIso8601String(),
        );
      } else {
        await prefs.remove('sync_camera_start_date');
        await prefs.remove('sync_camera_end_date');
      }
    } catch (e) {
      debugPrint('Error saving sync settings: $e');
    }
  }

  void _startDiscovery() {
    _discoveryTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_isStorageSharing) {
        _sendSyncAnnouncement();
      }
      _sendSyncProbe();
      _cleanupStaleDevices();
    });
    _refreshDevices();
  }

  void _sendSyncProbe() async {
    if (_syncDiscoverySocket == null) return;
    try {
      final deviceName = await DeviceNameManager.getDeviceName();
      final probe = json.encode({
        'type': 'SPEEDSHARE_SYNC_PROBE',
        'deviceName': deviceName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      final data = utf8.encode(probe);

      try {
        _syncDiscoverySocket!.send(data, InternetAddress('255.255.255.255'), 8083);
      } catch (_) {}

      try {
        _syncDiscoverySocket!.send(data, InternetAddress('239.255.255.250'), 8083);
      } catch (_) {}

      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        if (interface.name.contains('lo')) continue;
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final subnet = parts.sublist(0, 3).join('.');
              try {
                _syncDiscoverySocket!.send(data, InternetAddress('$subnet.255'), 8083);
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error sending sync probe: $e');
    }
  }

  Future<void> _refreshDevices() async {
    if (_isDiscovering) return;
    if (mounted) {
      setState(() {
        _isDiscovering = true;
      });
    }

    _cleanupStaleDevices();
    await _verifyAndCleanupDevices();

    _sendSyncProbe();

    if (_isStorageSharing) {
      _sendSyncAnnouncement();
    }

    // Parallel HTTP subnet probe for routers blocking UDP broadcast
    _scanSubnetHttp();

    await Future.delayed(const Duration(seconds: 2, milliseconds: 500));
    if (mounted) {
      setState(() {
        _isDiscovering = false;
      });
    }
  }

  Future<void> _verifyAndCleanupDevices() async {
    final List<SyncDevice> unreachable = [];
    for (final device in List<SyncDevice>.from(_availableDevices)) {
      try {
        final res = await http
            .get(Uri.parse('http://${device.ip}:${device.port}/api/info'))
            .timeout(const Duration(milliseconds: 400));
        if (res.statusCode != 200) {
          unreachable.add(device);
        }
      } catch (_) {
        unreachable.add(device);
      }
    }

    if (unreachable.isNotEmpty && mounted) {
      setState(() {
        _availableDevices.removeWhere((d) => unreachable.any((u) => u.ip == d.ip));
      });
    }
  }

  void _sendSyncGoodbye() async {
    if (_syncDiscoverySocket == null) return;
    try {
      final deviceName = await DeviceNameManager.getDeviceName();
      final goodbye = json.encode({
        'type': 'SPEEDSHARE_SYNC_GOODBYE',
        'deviceName': deviceName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      final data = utf8.encode(goodbye);

      try {
        _syncDiscoverySocket!.send(data, InternetAddress('255.255.255.255'), 8083);
      } catch (_) {}

      try {
        _syncDiscoverySocket!.send(data, InternetAddress('239.255.255.250'), 8083);
      } catch (_) {}

      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        if (interface.name.contains('lo')) continue;
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final subnet = parts.sublist(0, 3).join('.');
              try {
                _syncDiscoverySocket!.send(data, InternetAddress('$subnet.255'), 8083);
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error sending sync goodbye: $e');
    }
  }

  Future<void> _scanSubnetHttp() async {
    try {
      final interfaces = await NetworkInterface.list();
      final localIps = interfaces
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .toSet();
      localIps.addAll(['127.0.0.1', '::1']);

      final myName = await DeviceNameManager.getDeviceName();

      for (var interface in interfaces) {
        if (interface.name.contains('lo')) continue;
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final prefix = parts.sublist(0, 3).join('.');
              final ipsToScan = <String>[];
              for (int i = 1; i <= 254; i++) {
                final targetIp = '$prefix.$i';
                if (!localIps.contains(targetIp)) {
                  ipsToScan.add(targetIp);
                }
              }
              int chunkSize = 25;
              for (int j = 0; j < ipsToScan.length; j += chunkSize) {
                if (!mounted || !_isDiscovering) break;
                final end = (j + chunkSize < ipsToScan.length)
                    ? j + chunkSize
                    : ipsToScan.length;
                final chunk = ipsToScan.sublist(j, end);
                await Future.wait(chunk.map((ip) => _probeHttpHost(ip, myName)));
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('HTTP subnet scan error: $e');
    }
  }

  Future<void> _probeHttpHost(String ip, String myName) async {
    try {
      final response = await http
          .get(Uri.parse('http://$ip:8082/api/info'))
          .timeout(const Duration(milliseconds: 400));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final deviceName = data['deviceName'] as String? ?? 'Unknown Device';
        if (deviceName != myName && mounted) {
          final device = SyncDevice(
            name: deviceName,
            ip: ip,
            port: data['storagePort'] ?? 8082,
            accessCode: data['accessCode'] ?? '',
            capabilities: List<String>.from(data['capabilities'] ?? []),
            lastSeen: DateTime.now(),
          );
          setState(() {
            _availableDevices.removeWhere((d) => d.ip == device.ip);
            _availableDevices.add(device);
          });
        }
      }
    } catch (_) {}
  }

  void _sendSyncAnnouncement() async {
    if (_syncDiscoverySocket == null || !_isStorageSharing) return;
    
    try {
      final deviceName = await DeviceNameManager.getDeviceName();
      final announcement = json.encode({
        'type': 'SPEEDSHARE_SYNC_ANNOUNCE',
        'deviceName': deviceName,
        'storagePort': 8082,
        'accessCode': '', // PIN code is kept secret on host device
        'capabilities': ['storage_share', 'storage_browse'],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      
      final data = utf8.encode(announcement);
      
      // Try 255.255.255.255 and multicast first
      try {
        _syncDiscoverySocket!.send(data, InternetAddress('255.255.255.255'), 8083);
      } catch (_) {}
      try {
        _syncDiscoverySocket!.send(data, InternetAddress('239.255.255.250'), 8083);
      } catch (_) {}
      
      // Also broadcast to interfaces directly
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        if (interface.name.contains('lo')) continue;
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final subnet = parts.sublist(0, 3).join('.');
              try {
                _syncDiscoverySocket!.send(data, InternetAddress('$subnet.255'), 8083);
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error sending sync announcement: $e');
    }
  }

  void _cleanupStaleDevices() {
    final now = DateTime.now();
    setState(() {
      _availableDevices.removeWhere((device) =>
          now.difference(device.lastSeen).inMinutes > 5);
    });
  }

  Future<void> _startStorageSharing() async {
    // Check permissions first
    bool hasPermissions = await _checkStoragePermissions();
    if (!hasPermissions) {
      _showErrorSnackBar('Storage permissions required to share files');
      return;
    }

    if (_sharedPaths.isEmpty) {
      _showErrorSnackBar('Please select at least one directory to share');
      return;
    }

    try {
      _accessCode = _generateAccessCode();
      
      _storageServer = await HttpServer.bind(InternetAddress.anyIPv4, 8082);
      _storageServer!.listen(
        _handleStorageRequest,
        onError: (e) {
          debugPrint('Storage server error: $e');
        },
      );
      
      setState(() {
        _isStorageSharing = true;
      });
      
      _pulseController.repeat(reverse: true);
      _sendSyncAnnouncement();
      
      _showSuccessSnackBar('Storage sharing started with code: $_accessCode');
    } catch (e) {
      _showErrorSnackBar('Failed to start storage sharing: $e');
    }
  }

  Future<bool> _checkStoragePermissions() async {
    // Desktop platforms (Windows, macOS, Linux) do not need runtime storage permissions
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    if (Platform.isAndroid) {
      final permissions = [
        Permission.storage,
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ];

      // Request Android 11+ permissions if available
      if (await Permission.manageExternalStorage.status == PermissionStatus.denied) {
        permissions.add(Permission.manageExternalStorage);
      }

      final results = await permissions.request();
      return results.values.any((status) => status == PermissionStatus.granted);
    } else if (Platform.isIOS) {
      final results = await [
        Permission.photos,
        Permission.mediaLibrary,
      ].request();
      return results.values.any((status) => status == PermissionStatus.granted);
    }

    return true;
  }

  Future<void> _stopStorageSharing() async {
    try {
      _sendSyncGoodbye();
      await _storageServer?.close();
      _storageServer = null;
      _accessCode = null;
      
      setState(() {
        _isStorageSharing = false;
      });
      
      _pulseController.stop();
      _showSuccessSnackBar('Storage sharing stopped');
    } catch (e) {
      _showErrorSnackBar('Failed to stop storage sharing: $e');
    }
  }

  void _recordClientActivity(String clientIp, String action) {
    if (mounted) {
      setState(() {
        if (_connectedClients.containsKey(clientIp)) {
          final client = _connectedClients[clientIp]!;
          client.lastActive = DateTime.now();
          client.lastAction = action;
          client.requestCount++;
        } else {
          _connectedClients[clientIp] = ConnectedClient(
            ip: clientIp,
            name: 'Device ($clientIp)',
            lastActive: DateTime.now(),
            lastAction: action,
          );
        }
      });
    }
  }

  void _handleStorageRequest(HttpRequest request) async {
    try {
      final uri = request.uri;
      final clientIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';

      // Handle info/ping without access code requirement
      if (uri.path == '/api/info' || uri.path == '/api/ping') {
        final deviceName = await DeviceNameManager.getDeviceName();
        final info = json.encode({
          'type': 'SPEEDSHARE_SYNC_ANNOUNCE',
          'deviceName': deviceName,
          'storagePort': 8082,
          'accessCode': '',
          'capabilities': ['storage_share', 'storage_browse'],
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(info);
        await request.response.close();
        return;
      }

      final accessCode = uri.queryParameters['code']?.trim().toUpperCase();
      final expectedCode = _accessCode?.trim().toUpperCase();
      
      if (accessCode == null || accessCode != expectedCode) {
        request.response.statusCode = 403;
        request.response.write('Invalid access code');
        await request.response.close();
        return;
      }

      if (uri.path.startsWith('/api/files')) {
        await _handleFileListRequest(request, clientIp);
      } else if (uri.path.startsWith('/api/download')) {
        await _handleFileDownloadRequest(request, clientIp);
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    } catch (e) {
      debugPrint('Error handling storage request: $e');
      request.response.statusCode = 500;
      await request.response.close();
    }
  }

  Future<void> _handleFileListRequest(HttpRequest request, String clientIp) async {
    final requestedPath = request.uri.queryParameters['path'] ?? '/';
    final files = <Map<String, dynamic>>[];
    
    _recordClientActivity(
      clientIp,
      'Browsing ${requestedPath == "/" ? "Shared Folders" : p.basename(requestedPath)}',
    );

    final startDateStr = request.uri.queryParameters['startDate'];
    final endDateStr = request.uri.queryParameters['endDate'];
    DateTime? startDate = startDateStr != null ? DateTime.tryParse(startDateStr) : null;
    DateTime? endDate = endDateStr != null ? DateTime.tryParse(endDateStr) : null;

    if (startDate != null) {
      startDate = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    }
    if (endDate != null) {
      endDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    }

    final isCameraOrPhotos = requestedPath.toLowerCase().contains('camera') ||
        requestedPath.toLowerCase().contains('dcim') ||
        requestedPath.toLowerCase().contains('picture');

    DateTime? effectiveStart = startDate;
    DateTime? effectiveEnd = endDate;

    // Enforce host's date range restriction for Camera/photos to protect host privacy
    if (isCameraOrPhotos && _hostCameraDateRange != null) {
      final hostStart = DateTime(
        _hostCameraDateRange!.start.year,
        _hostCameraDateRange!.start.month,
        _hostCameraDateRange!.start.day,
        0,
        0,
        0,
      );
      final hostEnd = DateTime(
        _hostCameraDateRange!.end.year,
        _hostCameraDateRange!.end.month,
        _hostCameraDateRange!.end.day,
        23,
        59,
        59,
      );
      effectiveStart = effectiveStart != null
          ? (effectiveStart.isAfter(hostStart) ? effectiveStart : hostStart)
          : hostStart;
      effectiveEnd = effectiveEnd != null
          ? (effectiveEnd.isBefore(hostEnd) ? effectiveEnd : hostEnd)
          : hostEnd;
    }
    
    try {
      if (requestedPath == '/') {
        // Return shared root folders as directories so the user can choose which folder to enter
        for (final sharedPath in _sharedPaths) {
          final directory = Directory(sharedPath);
          if (await directory.exists()) {
            try {
              final stat = await directory.stat();
              var folderName = p.basename(sharedPath);
              if (folderName.isEmpty) folderName = sharedPath;
              files.add({
                'name': folderName,
                'path': sharedPath,
                'isDirectory': true,
                'size': 0,
                'modified': stat.modified.toIso8601String(),
                'type': 'directory',
              });
            } catch (_) {}
          }
        }
      } else {
        if (_isPathAllowed(requestedPath)) {
          final directory = Directory(requestedPath);
          if (await directory.exists()) {
            await for (final entity in directory.list()) {
              try {
                final stat = await entity.stat();
                if (entity is File && (effectiveStart != null || effectiveEnd != null)) {
                  if (effectiveStart != null && stat.modified.isBefore(effectiveStart)) continue;
                  if (effectiveEnd != null && stat.modified.isAfter(effectiveEnd)) continue;
                }
                files.add({
                  'name': p.basename(entity.path),
                  'path': entity.path,
                  'isDirectory': entity is Directory,
                  'size': entity is File ? stat.size : 0,
                  'modified': stat.modified.toIso8601String(),
                  'type': entity is File
                      ? lookupMimeType(entity.path) ?? 'application/octet-stream'
                      : 'directory',
                });
              } catch (e) {
                // Skip files that can't be accessed
              }
            }
          }
        } else {
          request.response.statusCode = 403;
          request.response.write('Access denied');
          await request.response.close();
          return;
        }
      }
      
      files.sort((a, b) {
        if (a['isDirectory'] && !b['isDirectory']) return -1;
        if (!a['isDirectory'] && b['isDirectory']) return 1;
        return (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
      });
      
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode(files));
    } catch (e) {
      request.response.statusCode = 500;
      request.response.write('Error listing files: $e');
    }
    
    await request.response.close();
  }

  Future<void> _handleFileDownloadRequest(HttpRequest request, [String clientIp = 'unknown']) async {
    final filePath = request.uri.queryParameters['file'];
    final isPreview = request.uri.queryParameters['preview'] == 'true';
    
    if (filePath == null || !_isPathAllowed(filePath)) {
      request.response.statusCode = 403;
      request.response.write('Access denied');
      await request.response.close();
      return;
    }

    _recordClientActivity(
      clientIp,
      isPreview ? 'Previewing ${p.basename(filePath)}' : 'Downloading ${p.basename(filePath)}',
    );
    
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final fileSize = await file.length();
        final mimeTypeStr = lookupMimeType(filePath) ?? 'application/octet-stream';
        ContentType contentType;
        try {
          final parts = mimeTypeStr.split('/');
          if (parts.length == 2) {
            contentType = ContentType(parts[0], parts[1]);
          } else {
            contentType = ContentType.binary;
          }
        } catch (_) {
          contentType = ContentType.binary;
        }

        request.response.headers.contentType = contentType;
        request.response.headers.add('Accept-Ranges', 'bytes');
        
        if (isPreview) {
          request.response.headers.add('Content-Disposition', 'inline; filename="${p.basename(filePath)}"');
        } else {
          request.response.headers.add('Content-Disposition', 'attachment; filename="${p.basename(filePath)}"');
        }

        // Support HTTP Range requests for media streaming and fast thumbnails
        final rangeHeader = request.headers.value('range');
        if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
          final match = RegExp(r'bytes=(\d+)-(\d+)?').firstMatch(rangeHeader);
          if (match != null) {
            final start = int.parse(match.group(1)!);
            final end = match.group(2) != null ? int.parse(match.group(2)!) : fileSize - 1;
            
            if (start < fileSize && end < fileSize && start <= end) {
              final length = end - start + 1;
              request.response.statusCode = HttpStatus.partialContent;
              request.response.headers.add('Content-Range', 'bytes $start-$end/$fileSize');
              request.response.headers.add('Content-Length', length.toString());
              await file.openRead(start, end + 1).pipe(request.response);
              return;
            }
          }
        }

        request.response.headers.add('Content-Length', fileSize.toString());
        await file.openRead().pipe(request.response);
      } else {
        request.response.statusCode = 404;
        request.response.write('File not found');
        await request.response.close();
      }
    } catch (e) {
      debugPrint('Error downloading file: $e');
      request.response.statusCode = 500;
      request.response.write('Error downloading file: $e');
      await request.response.close();
    }
  }

  bool _isPathAllowed(String filePath) {
    try {
      // Canonicalize the path to resolve '..' and symlinks, preventing traversal attacks
      final canonicalPath = p.canonicalize(filePath);
      final isAllowed = _sharedPaths.any(
        (sharedPath) => canonicalPath.startsWith(p.canonicalize(sharedPath)),
      );
      if (!isAllowed) return false;

      // Enforce host camera date range protection
      if (_hostCameraDateRange != null &&
          (canonicalPath.toLowerCase().contains('camera') ||
           canonicalPath.toLowerCase().contains('dcim') ||
           canonicalPath.toLowerCase().contains('picture'))) {
        final file = File(filePath);
        if (file.existsSync()) {
          final stat = file.statSync();
          final start = DateTime(
            _hostCameraDateRange!.start.year,
            _hostCameraDateRange!.start.month,
            _hostCameraDateRange!.start.day,
            0,
            0,
            0,
          );
          final end = DateTime(
            _hostCameraDateRange!.end.year,
            _hostCameraDateRange!.end.month,
            _hostCameraDateRange!.end.day,
            23,
            59,
            59,
          );
          if (stat.modified.isBefore(start) || stat.modified.isAfter(end)) {
            return false;
          }
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  String _generateAccessCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();
  }

  Future<String?> _showAccessCodeDialog(SyncDevice device) async {
    final codeController = TextEditingController();
    String? errorText;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, color: Color(0xFF4E6AF3)),
                  const SizedBox(width: 10),
                  const Text(
                    'Enter Access Code',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter the access code displayed on ${device.name}:',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.text,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Access Code',
                      errorText: errorText,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.key_rounded),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final code = codeController.text.trim();
                    if (code.isEmpty) {
                      setDialogState(() {
                        errorText = 'Code cannot be empty';
                      });
                      return;
                    }
                    Navigator.pop(context, code);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4E6AF3),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Connect'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _browseDevice(SyncDevice device) async {
    String? pin = _devicePins[device.ip];
    if (pin == null || pin.isEmpty) {
      pin = await _showAccessCodeDialog(device);
      if (pin == null || pin.isEmpty) return; // User cancelled
      _devicePins[device.ip] = pin;
    }

    setState(() {
      _selectedDevice = device;
      _isBrowsingFiles = true;
      _currentRemotePath = '/';
    });

    await _loadRemoteFiles('/');
  }

  void _navigateUp() {
    if (_currentRemotePath == '/' || _currentRemotePath.isEmpty) {
      setState(() {
        _isBrowsingFiles = false;
        _selectedDevice = null;
        _remoteFiles.clear();
      });
    } else {
      final parent = p.dirname(_currentRemotePath);
      if (parent == '.' || parent == _currentRemotePath) {
        _loadRemoteFiles('/');
      } else {
        _loadRemoteFiles(parent);
      }
    }
  }

  bool _isPhotoRelatedFolder(String folderPath) {
    final lower = folderPath.toLowerCase();
    return lower.contains('camera') ||
        lower.contains('dcim') ||
        lower.contains('picture') ||
        lower.contains('photo') ||
        lower.contains('image') ||
        lower.contains('gallery');
  }

  Future<void> _loadRemoteFiles(String path) async {
    if (_selectedDevice == null) return;
    final pin = _devicePins[_selectedDevice!.ip] ?? '';

    // Clear client date range filter if navigating into a non-photo folder
    if (!_isPhotoRelatedFolder(path)) {
      _selectedDateRange = null;
    }

    setState(() {
      _isLoadingRemoteFiles = true;
    });

    try {
      String url =
          'http://${_selectedDevice!.ip}:${_selectedDevice!.port}/api/files?path=${Uri.encodeComponent(path)}&code=$pin';
      if (_isPhotoRelatedFolder(path) && _selectedDateRange != null) {
        url +=
            '&startDate=${_selectedDateRange!.start.toIso8601String()}&endDate=${_selectedDateRange!.end.toIso8601String()}';
      }

      final response = await http
          .get(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _remoteFiles =
              data.map((item) => RemoteFileInfo.fromJson(item)).toList();
          _currentRemotePath = path;
        });
      } else if (response.statusCode == 403) {
        if (path != '/') {
          // If navigating to a parent directory outside allowed shared roots, smoothly return to root
          await _loadRemoteFiles('/');
          return;
        }
        _devicePins.remove(_selectedDevice!.ip);
        _showErrorSnackBar('Invalid Access Code for ${_selectedDevice!.name}');
        setState(() {
          _isBrowsingFiles = false;
          _selectedDevice = null;
        });
      } else {
        _showErrorSnackBar('Failed to load files: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackBar('Error loading files: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRemoteFiles = false;
        });
      }
    }
  }

  DownloadTask? _getDownloadTask(String filePath) {
    for (final task in _downloadQueue.reversed) {
      if (task.file.path == filePath) {
        return task;
      }
    }
    return null;
  }

  bool _isImageFile(RemoteFileInfo file) {
    final lowerName = file.name.toLowerCase();
    return file.type.startsWith('image/') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.webp') ||
        lowerName.endsWith('.gif') ||
        lowerName.endsWith('.bmp') ||
        lowerName.endsWith('.svg') ||
        lowerName.endsWith('.heic') ||
        lowerName.endsWith('.ico');
  }

  bool _isVideoFile(RemoteFileInfo file) {
    final lowerName = file.name.toLowerCase();
    return file.type.startsWith('video/') ||
        lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.mkv') ||
        lowerName.endsWith('.avi') ||
        lowerName.endsWith('.mov') ||
        lowerName.endsWith('.webm') ||
        lowerName.endsWith('.flv') ||
        lowerName.endsWith('.3gp') ||
        lowerName.endsWith('.m4v') ||
        lowerName.endsWith('.wmv');
  }

  bool _isAudioFile(RemoteFileInfo file) {
    final lowerName = file.name.toLowerCase();
    return file.type.startsWith('audio/') ||
        lowerName.endsWith('.mp3') ||
        lowerName.endsWith('.wav') ||
        lowerName.endsWith('.aac') ||
        lowerName.endsWith('.flac') ||
        lowerName.endsWith('.ogg') ||
        lowerName.endsWith('.m4a');
  }

  bool _isTextFile(RemoteFileInfo file) {
    final lowerName = file.name.toLowerCase();
    return file.type.startsWith('text/') ||
        lowerName.endsWith('.txt') ||
        lowerName.endsWith('.json') ||
        lowerName.endsWith('.dart') ||
        lowerName.endsWith('.js') ||
        lowerName.endsWith('.ts') ||
        lowerName.endsWith('.html') ||
        lowerName.endsWith('.css') ||
        lowerName.endsWith('.xml') ||
        lowerName.endsWith('.yaml') ||
        lowerName.endsWith('.yml') ||
        lowerName.endsWith('.md') ||
        lowerName.endsWith('.log') ||
        lowerName.endsWith('.csv');
  }

  bool _isPdfFile(RemoteFileInfo file) {
    final lowerName = file.name.toLowerCase();
    return file.type.contains('pdf') || lowerName.endsWith('.pdf');
  }

  String _getRemoteFileUrl(RemoteFileInfo file, {bool preview = false}) {
    if (_selectedDevice == null) return '';
    final pin = _devicePins[_selectedDevice!.ip] ?? '';
    final encodedPath = Uri.encodeComponent(file.path);
    return 'http://${_selectedDevice!.ip}:${_selectedDevice!.port}/api/download?file=$encodedPath&code=$pin${preview ? '&preview=true' : ''}';
  }

  Future<void> _downloadFile(
    RemoteFileInfo file, {
    bool autoOpenOnComplete = false,
    VoidCallback? onProgress,
  }) async {
    if (_selectedDevice == null) return;
    
    // Check if already completed and local file exists
    final existingTask = _getDownloadTask(file.path);
    if (existingTask != null && existingTask.status == 'Completed') {
      final localFile = File(existingTask.savePath);
      if (await localFile.exists()) {
        if (autoOpenOnComplete) {
          try {
            final result = await OpenFile.open(existingTask.savePath);
            if (result.type != ResultType.done && result.message.isNotEmpty) {
              _showErrorSnackBar('Could not open file: ${result.message}');
            }
          } catch (e) {
            _showErrorSnackBar('Error opening file: $e');
          }
        } else {
          _showSuccessSnackBar('Already downloaded: ${file.name}');
        }
        return;
      }
    }

    // Prevent duplicate concurrent downloads of the same file
    if (existingTask != null &&
        (existingTask.status == 'Starting' || existingTask.status == 'Receiving')) {
      _showSuccessSnackBar('Already downloading ${file.name}');
      return;
    }

    try {
      // Get Downloads directory for the active platform (respecting Settings downloadPath)
      Directory downloadDir;
      final prefs = await SharedPreferences.getInstance();
      final String? savedPath = prefs.getString('downloadPath');

      if (savedPath != null && savedPath.trim().isNotEmpty) {
        downloadDir = Directory(savedPath.trim());
        try {
          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
          }
        } catch (e) {
          debugPrint('Custom sync download path inaccessible ($savedPath): $e');
          downloadDir = await _getDefaultSyncDownloadDirectory();
        }
      } else {
        downloadDir = await _getDefaultSyncDownloadDirectory();
      }
      
      final savePath = p.join(downloadDir.path, file.name);
      
      final downloadTask = DownloadTask(
        file: file,
        savePath: savePath,
        progress: 0.0,
        status: 'Starting',
        receivedBytes: 0,
        totalBytes: file.size,
      );
      
      setState(() {
        _downloadQueue.removeWhere((t) => t.file.path == file.path);
        _downloadQueue.add(downloadTask);
      });
      onProgress?.call();
      
      final pin = _devicePins[_selectedDevice!.ip] ?? '';
      final request = http.Request(
        'GET',
        Uri.parse(
          'http://${_selectedDevice!.ip}:${_selectedDevice!.port}/api/download?file=${Uri.encodeComponent(file.path)}&code=$pin',
        ),
      );
      final response = await http.Client().send(request);
      
      if (response.statusCode == 200) {
        final totalBytes = response.contentLength ?? file.size;
        int receivedBytes = 0;
        downloadTask.totalBytes = totalBytes;
        downloadTask.status = 'Receiving';
        onProgress?.call();
        
        final ioFile = File(savePath);
        final sink = ioFile.openWrite();
        
        DateTime lastUiUpdate = DateTime.now();

        await response.stream.forEach((chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          final currentProgress = totalBytes > 0 ? (receivedBytes / totalBytes) : 0.0;
          
          downloadTask.receivedBytes = receivedBytes;
          downloadTask.progress = currentProgress.clamp(0.0, 1.0);
          
          final now = DateTime.now();
          if (now.difference(lastUiUpdate).inMilliseconds > 60 || downloadTask.progress >= 1.0) {
            lastUiUpdate = now;
            if (mounted) {
              setState(() {});
            }
            onProgress?.call();
          }
        });
        await sink.close();
        
        if (mounted) {
          setState(() {
            downloadTask.progress = 1.0;
            downloadTask.receivedBytes = totalBytes > 0 ? totalBytes : receivedBytes;
            downloadTask.status = 'Completed';
          });
        }
        onProgress?.call();

        try {
          NotificationService().showSyncCompletedNotification(
            fileName: file.name,
            sourceDevice: _selectedDevice?.name ?? 'Device',
          );
        } catch (_) {}
        
        _showSuccessSnackBar('Downloaded: ${file.name}');

        // Auto open/play if requested
        if (autoOpenOnComplete) {
          try {
            final result = await OpenFile.open(savePath);
            if (result.type != ResultType.done && result.message.isNotEmpty) {
              _showErrorSnackBar('Could not open file: ${result.message}');
            }
          } catch (e) {
            _showErrorSnackBar('Error opening file: $e');
          }
        }
      } else {
        if (mounted) {
          setState(() {
            downloadTask.status = 'Failed';
          });
        }
        onProgress?.call();
        _showErrorSnackBar('Download failed: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        final task = _getDownloadTask(file.path);
        if (task != null) {
          setState(() {
            task.status = 'Failed';
          });
        }
      }
      onProgress?.call();
      _showErrorSnackBar('Error downloading file: $e');
    }
  }

  Future<Directory> _getDefaultSyncDownloadDirectory() async {
    Directory base;
    if (Platform.isAndroid) {
      base = Directory('/storage/emulated/0/Download');
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final downloadsDir = await getDownloadsDirectory();
      base = downloadsDir ?? await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}/speedshare');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF2AB673),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }  @override
  Widget build(BuildContext context) {
    if (_isBrowsingFiles && _selectedDevice != null) {
      return _buildFileBrowser();
    }
    
    return Scaffold(
      appBar: const SpeedShareAppBar(
        title: 'Storage Sync',
        subtitle: 'Browse & share device storage',
        icon: Icons.sync_rounded,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const NetworkStatusWidget(
                    mode: NetworkWidgetMode.sync,
                  ),
                  _buildModeSelector(),
                  const SizedBox(height: 8),
                  if (_activeTab == SyncTabMode.connect)
                    Expanded(child: _buildAccessStorageCard())
                  else
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildShareStorageCard(),
                            const SizedBox(height: 16),
                            _buildConnectedDevicesCard(),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[850]
            : Colors.grey[200],
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                if (_activeTab != SyncTabMode.connect) {
                  setState(() {
                    _activeTab = SyncTabMode.connect;
                  });
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _activeTab == SyncTabMode.connect
                      ? const Color(0xFF4E6AF3)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _activeTab == SyncTabMode.connect
                      ? [
                          BoxShadow(
                            color: const Color(0xFF4E6AF3).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.devices_rounded,
                      size: 18,
                      color: _activeTab == SyncTabMode.connect
                          ? Colors.white
                          : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[400]
                              : Colors.grey[700]),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Connect',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _activeTab == SyncTabMode.connect
                            ? Colors.white
                            : (Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey[400]
                                : Colors.grey[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () {
                if (_activeTab != SyncTabMode.sync) {
                  setState(() {
                    _activeTab = SyncTabMode.sync;
                  });
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _activeTab == SyncTabMode.sync
                      ? const Color(0xFF4E6AF3)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _activeTab == SyncTabMode.sync
                      ? [
                          BoxShadow(
                            color: const Color(0xFF4E6AF3).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.sync_rounded,
                      size: 18,
                      color: _activeTab == SyncTabMode.sync
                          ? Colors.white
                          : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[400]
                              : Colors.grey[700]),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sync / Share',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _activeTab == SyncTabMode.sync
                            ? Colors.white
                            : (Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey[400]
                                : Colors.grey[700]),
                      ),
                    ),
                    if (_isStorageSharing) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2AB673),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedDevicesCard() {
    final activeClients = _connectedClients.values.toList();
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
                    Icons.people_alt_rounded,
                    color: Color(0xFF4E6AF3),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connected Devices',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Devices accessing this storage',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (activeClients.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2AB673).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${activeClients.length} active',
                      style: const TextStyle(
                        color: Color(0xFF2AB673),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (activeClients.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[850]!.withValues(alpha: 0.5)
                      : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _isStorageSharing
                          ? Icons.wifi_tethering_rounded
                          : Icons.cloud_off_rounded,
                      color: Colors.grey[400],
                      size: 36,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isStorageSharing
                          ? 'Waiting for devices to connect...'
                          : 'Start sharing storage to allow connections',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: activeClients.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final client = activeClients[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2AB673).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.devices_rounded,
                        color: Color(0xFF2AB673),
                        size: 18,
                      ),
                    ),
                    title: Text(
                      client.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${client.lastAction} • ${_getTimeAgo(client.lastActive)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${client.requestCount} requests',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareStorageCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ScaleTransition(
                  scale: _isStorageSharing ? _pulseAnimation : 
                         AlwaysStoppedAnimation(1.0),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _isStorageSharing 
                          ? const Color(0xFF2AB673).withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.smartphone_rounded,
                      color: _isStorageSharing 
                          ? const Color(0xFF2AB673)
                          : Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Share This Device',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _isStorageSharing 
                            ? 'Others can access your files'
                            : 'Allow others to browse your files',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isStorageSharing 
                        ? const Color(0xFF2AB673)
                        : Colors.grey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _isStorageSharing ? 'Active' : 'Inactive',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            
            if (_isStorageSharing) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF4E6AF3).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.security,
                      color: Color(0xFF4E6AF3),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Access Code: ',
                      style: TextStyle(fontSize: 12),
                    ),
                    Text(
                      _accessCode ?? '',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4E6AF3),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _accessCode ?? ''));
                        _showSuccessSnackBar('Access code copied');
                      },
                      child: const Icon(
                        Icons.copy,
                        color: Color(0xFF4E6AF3),
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isStorageSharing ? _stopStorageSharing : _startStorageSharing,
                    icon: Icon(_isStorageSharing ? Icons.stop : Icons.play_arrow),
                    label: Text(_isStorageSharing ? 'Stop Sharing' : 'Start Sharing'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: _isStorageSharing 
                          ? Colors.red 
                          : const Color(0xFF2AB673),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (!_isStorageSharing) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _showSharedPathsDialog(),
                    icon: const Icon(Icons.settings),
                    tooltip: 'Configure shared folders',
                  ),
                ],
              ],
            ),

            if (_sharedPaths.any((p) => _isPhotoRelatedFolder(p))) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Camera / Photo Privacy Date Range Setting (Non-overflowing layout)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _hostCameraDateRange != null
                      ? const Color(0xFF4E6AF3).withValues(alpha: 0.08)
                      : Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[850]!.withValues(alpha: 0.5)
                          : Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _hostCameraDateRange != null
                        ? const Color(0xFF4E6AF3).withValues(alpha: 0.3)
                        : Theme.of(context).dividerColor.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row: Icon + Title + Protected Badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _hostCameraDateRange != null
                                ? const Color(0xFF4E6AF3).withValues(alpha: 0.15)
                                : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            _hostCameraDateRange != null
                                ? Icons.shield_rounded
                                : Icons.photo_library_outlined,
                            color: _hostCameraDateRange != null
                                ? const Color(0xFF4E6AF3)
                                : Colors.grey[700],
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Camera Photos Privacy',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_hostCameraDateRange != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4E6AF3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Protected',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Subtitle description & Action Buttons
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            _hostCameraDateRange != null
                                ? 'Sharing only: ${_formatDateShort(_hostCameraDateRange!.start)} - ${_formatDateShort(_hostCameraDateRange!.end)}'
                                : 'All camera photos are accessible to connected devices',
                            style: TextStyle(
                              fontSize: 11,
                              color: _hostCameraDateRange != null
                                  ? const Color(0xFF4E6AF3)
                                  : Colors.grey[600],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_hostCameraDateRange != null) ...[
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            tooltip: 'Remove date restriction',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () async {
                              setState(() {
                                _hostCameraDateRange = null;
                              });
                              await _saveSettings();
                              _showSuccessSnackBar(
                                'Date restriction removed: all photos shared',
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                        ],
                        ElevatedButton(
                          onPressed: _showHostDateRangeDialog,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: const Color(0xFF4E6AF3),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            _hostCameraDateRange != null ? 'Change' : 'Set Range',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showHostDateRangeDialog() async {
    final now = DateTime.now();
    final result = await showDialog<dynamic>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, color: Color(0xFF4E6AF3)),
            SizedBox(width: 10),
            Text('Protect Camera Photos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select which date range of photos to share. Connected devices will ONLY be able to see and download photos taken within this range:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.all_inclusive_rounded),
              title: const Text('Share All Photos (No limit)'),
              onTap: () => Navigator.pop(context, 'clear'),
            ),
            ListTile(
              leading: const Icon(Icons.today_rounded),
              title: const Text('Today\'s Photos Only'),
              onTap: () => Navigator.pop(
                context,
                DateTimeRange(
                  start: DateTime(now.year, now.month, now.day),
                  end: DateTime(now.year, now.month, now.day, 23, 59, 59),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_view_week_rounded),
              title: const Text('Last 7 Days'),
              onTap: () => Navigator.pop(
                context,
                DateTimeRange(
                  start: now.subtract(const Duration(days: 7)),
                  end: now,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_rounded),
              title: const Text('Last 30 Days'),
              onTap: () => Navigator.pop(
                context,
                DateTimeRange(
                  start: now.subtract(const Duration(days: 30)),
                  end: now,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_calendar_rounded, color: Color(0xFF4E6AF3)),
              title: const Text(
                'Custom Date Range...',
                style: TextStyle(color: Color(0xFF4E6AF3), fontWeight: FontWeight.bold),
              ),
              onTap: () => Navigator.pop(context, 'custom'),
            ),
          ],
        ),
      ),
    );

    if (result == 'clear') {
      setState(() {
        _hostCameraDateRange = null;
      });
      await _saveSettings();
      _showSuccessSnackBar('Sharing all camera photos');
    } else if (result == 'custom') {
      if (!mounted) return;
      final customRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDateRange: _hostCameraDateRange ??
            DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
      );
      if (customRange != null) {
        setState(() {
          _hostCameraDateRange = customRange;
        });
        await _saveSettings();
        _showSuccessSnackBar(
          'Camera restricted to ${_formatDateShort(customRange.start)} - ${_formatDateShort(customRange.end)}',
        );
      }
    } else if (result is DateTimeRange) {
      setState(() {
        _hostCameraDateRange = result;
      });
      await _saveSettings();
      _showSuccessSnackBar(
        'Camera restricted to ${_formatDateShort(result.start)} - ${_formatDateShort(result.end)}',
      );
    }
  }

  Widget _buildAccessStorageCard() {
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
                    Icons.devices_rounded,
                    color: Color(0xFF4E6AF3),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Browse Other Devices',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Access files from other devices',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _isDiscovering ? null : _refreshDevices,
                  icon: _isDiscovering
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          color: Color(0xFF4E6AF3),
                        ),
                  tooltip: 'Refresh / Scan network',
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Device list
            Expanded(
              child: _availableDevices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Lottie.asset(
                            'assets/searchss.json',
                            height: 100,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.search_off,
                                size: 60,
                                color: Colors.grey[300],
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No devices found',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Make sure other devices are sharing storage',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          OutlinedButton.icon(
                            onPressed: _isDiscovering ? null : _refreshDevices,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Scan Again'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF4E6AF3),
                              side: const BorderSide(color: Color(0xFF4E6AF3)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _availableDevices.length,
                      itemBuilder: (context, index) {
                        final device = _availableDevices[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(12),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2AB673).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                device.name.toLowerCase().contains('mobile') || 
                                device.name.toLowerCase().contains('phone')
                                    ? Icons.phone_android
                                    : Icons.computer,
                                color: const Color(0xFF2AB673),
                                size: 24,
                              ),
                            ),
                            title: Text(
                              device.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'IP: ${device.ip}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Last seen: ${_getTimeAgo(device.lastSeen)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                            trailing: ElevatedButton(
                              onPressed: () => _browseDevice(device),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4E6AF3),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text(
                                'Browse',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            
            // Download queue
            if (_downloadQueue.isNotEmpty) ...[
              const Divider(),
              const Text(
                'Downloads',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  itemCount: _downloadQueue.length,
                  itemBuilder: (context, index) {
                    final task = _downloadQueue[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        _getFileIcon(task.file.type),
                        color: _getFileIconColor(task.file.type),
                        size: 20,
                      ),
                      title: Text(
                        task.file.name,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.status,
                            style: const TextStyle(fontSize: 10),
                          ),
                          if (task.progress > 0 && task.progress < 1)
                            LinearProgressIndicator(
                              value: task.progress,
                              minHeight: 2,
                            ),
                        ],
                      ),
                      trailing: task.status == 'Completed'
                          ? const Icon(
                              Icons.check_circle,
                              color: Color(0xFF2AB673),
                              size: 16,
                            )
                          : task.status == 'Failed'
                              ? const Icon(
                                  Icons.error,
                                  color: Colors.red,
                                  size: 16,
                                )
                              : const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFileBrowser() {
    final isPhotoFolder =
        _currentRemotePath != '/' && _isPhotoRelatedFolder(_currentRemotePath);

    final displayedFiles = _remoteFiles.where((file) {
      if (file.isDirectory) return true;
      if (!isPhotoFolder || _selectedDateRange == null) return true;
      final start = DateTime(
        _selectedDateRange!.start.year,
        _selectedDateRange!.start.month,
        _selectedDateRange!.start.day,
        0,
        0,
        0,
      );
      final end = DateTime(
        _selectedDateRange!.end.year,
        _selectedDateRange!.end.month,
        _selectedDateRange!.end.day,
        23,
        59,
        59,
      );
      return !file.modified.isBefore(start) && !file.modified.isAfter(end);
    }).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _navigateUp();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_selectedDevice?.name ?? 'Device'),
          elevation: 0,
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _navigateUp,
            tooltip: 'Go back',
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isLoadingRemoteFiles
                  ? null
                  : () => _loadRemoteFiles(_currentRemotePath),
              tooltip: 'Refresh files',
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Path indicator
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[850]
                    : Colors.grey[100],
                child: Row(
                  children: [
                    Icon(
                      _currentRemotePath == '/'
                          ? Icons.folder_shared_rounded
                          : Icons.folder_open_rounded,
                      size: 16,
                      color: const Color(0xFF4E6AF3),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentRemotePath == '/'
                            ? 'Shared Folders (Choose folder)'
                            : _currentRemotePath,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[300]
                              : Colors.grey[700],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Date Range Filter Bar (ONLY shown when inside a photo-related folder like Camera/DCIM)
              if (isPhotoFolder)
                _buildDateRangeFilterBar(),

              // File list / Loading / Empty State
              Expanded(
                child: _isLoadingRemoteFiles
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(
                              color: Color(0xFF4E6AF3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Loading files...',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : displayedFiles.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _selectedDateRange != null
                                      ? Icons.filter_alt_off_rounded
                                      : Icons.folder_open,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _selectedDateRange != null
                                      ? 'No files found within selected date range'
                                      : (_currentRemotePath == '/'
                                          ? 'No shared folders available'
                                          : 'No files in this folder'),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 15,
                                  ),
                                ),
                                if (_selectedDateRange != null) ...[
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _selectedDateRange = null;
                                      });
                                      _loadRemoteFiles(_currentRemotePath);
                                    },
                                    icon: const Icon(Icons.clear_rounded),
                                    label: const Text('Clear Date Filter'),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _currentRemotePath != '/'
                                ? displayedFiles.length + 1
                                : displayedFiles.length,
                            itemBuilder: (context, index) {
                              if (_currentRemotePath != '/' && index == 0) {
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4E6AF3)
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.arrow_upward_rounded,
                                        color: Color(0xFF4E6AF3),
                                        size: 20,
                                      ),
                                    ),
                                    title: const Text(
                                      '.. (Back to Shared Folders)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    onTap: _navigateUp,
                                  ),
                                );
                              }

                              final fileIndex = _currentRemotePath != '/'
                                  ? index - 1
                                  : index;
                              final file = displayedFiles[fileIndex];
                              final task = _getDownloadTask(file.path);
                              final isReceiving = task != null &&
                                  (task.status == 'Starting' || task.status == 'Receiving');

                              return Card(
                                margin: const EdgeInsets.only(bottom: 4),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  leading: _buildFileThumbnail(file),
                                  title: Text(
                                    file.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: file.isDirectory
                                      ? Text(
                                          _currentRemotePath == '/'
                                              ? 'Shared Folder • Tap to open'
                                              : 'Folder',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _currentRemotePath == '/'
                                                ? const Color(0xFF4E6AF3)
                                                : Colors.grey[600],
                                            fontWeight: _currentRemotePath == '/'
                                                ? FontWeight.w500
                                                : FontWeight.normal,
                                          ),
                                        )
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (isReceiving) ...[
                                              Text(
                                                'Receiving: ${_formatFileSize(task.receivedBytes)} / ${_formatFileSize(task.totalBytes)} (${(task.progress * 100).toInt()}%)',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF4E6AF3),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ] else ...[
                                              Text(
                                                _formatFileSize(file.size),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                            Text(
                                              _formatDate(file.modified),
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey[500],
                                              ),
                                            ),
                                          ],
                                        ),
                                  trailing: file.isDirectory
                                      ? const Icon(
                                          Icons.chevron_right,
                                          color: Color(0xFF4E6AF3),
                                        )
                                      : _buildDownloadButton(file),
                                  onTap: file.isDirectory
                                      ? () => _loadRemoteFiles(file.path)
                                      : () => _showFilePreviewDialog(file),
                                ),
                              );
                            },
                          ),
              ),
              _buildActiveDownloadsBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateRangeFilterBar() {
    final hasFilter = _selectedDateRange != null;
    final isCamera = _currentRemotePath.toLowerCase().contains('camera') ||
        _currentRemotePath.toLowerCase().contains('dcim');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: hasFilter
            ? const Color(0xFF4E6AF3).withValues(alpha: 0.1)
            : (isCamera
                ? const Color(0xFF4E6AF3).withValues(alpha: 0.05)
                : (Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[900]
                    : Colors.grey[50])),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_rounded,
            size: 16,
            color: hasFilter ? const Color(0xFF4E6AF3) : Colors.grey[600],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: _showDateRangeFilterDialog,
              child: Text(
                hasFilter
                    ? '${_formatDateShort(_selectedDateRange!.start)} - ${_formatDateShort(_selectedDateRange!.end)}'
                    : isCamera
                        ? 'Filter Camera photos by date range...'
                        : 'Filter by date range...',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: hasFilter ? FontWeight.bold : FontWeight.normal,
                  color: hasFilter
                      ? const Color(0xFF4E6AF3)
                      : (Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[300]
                          : Colors.grey[700]),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (hasFilter) ...[
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Clear date filter',
              onPressed: () {
                setState(() {
                  _selectedDateRange = null;
                });
                _loadRemoteFiles(_currentRemotePath);
              },
            ),
            const SizedBox(width: 8),
          ],
          TextButton.icon(
            onPressed: _showDateRangeFilterDialog,
            icon: Icon(
              hasFilter ? Icons.edit_calendar_rounded : Icons.tune_rounded,
              size: 14,
            ),
            label: Text(
              hasFilter ? 'Change' : 'Filter',
              style: const TextStyle(fontSize: 12),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: const Color(0xFF4E6AF3),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDateRangeFilterDialog() async {
    final now = DateTime.now();
    final result = await showDialog<dynamic>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.date_range_rounded, color: Color(0xFF4E6AF3)),
            SizedBox(width: 10),
            Text('Select Date Range', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.all_inclusive_rounded),
              title: const Text('All Dates (No filter)'),
              onTap: () => Navigator.pop(context, 'clear'),
            ),
            ListTile(
              leading: const Icon(Icons.today_rounded),
              title: const Text('Today'),
              onTap: () => Navigator.pop(
                context,
                DateTimeRange(
                  start: DateTime(now.year, now.month, now.day),
                  end: DateTime(now.year, now.month, now.day, 23, 59, 59),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_view_week_rounded),
              title: const Text('Last 7 Days'),
              onTap: () => Navigator.pop(
                context,
                DateTimeRange(
                  start: now.subtract(const Duration(days: 7)),
                  end: now,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_rounded),
              title: const Text('Last 30 Days'),
              onTap: () => Navigator.pop(
                context,
                DateTimeRange(
                  start: now.subtract(const Duration(days: 30)),
                  end: now,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_calendar_rounded, color: Color(0xFF4E6AF3)),
              title: const Text(
                'Custom Date Range...',
                style: TextStyle(color: Color(0xFF4E6AF3), fontWeight: FontWeight.bold),
              ),
              onTap: () => Navigator.pop(context, 'custom'),
            ),
          ],
        ),
      ),
    );

    if (result == 'clear') {
      setState(() {
        _selectedDateRange = null;
      });
      _loadRemoteFiles(_currentRemotePath);
    } else if (result == 'custom') {
      if (!mounted) return;
      final customRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDateRange: _selectedDateRange ??
            DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
      );
      if (customRange != null) {
        setState(() {
          _selectedDateRange = customRange;
        });
        _loadRemoteFiles(_currentRemotePath);
      }
    } else if (result is DateTimeRange) {
      setState(() {
        _selectedDateRange = result;
      });
      _loadRemoteFiles(_currentRemotePath);
    }
  }

  String _formatDateShort(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Widget _buildFileThumbnail(RemoteFileInfo file) {
    if (file.isDirectory) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF4E6AF3).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.folder_rounded,
          color: Color(0xFF4E6AF3),
          size: 24,
        ),
      );
    }

    if (_isImageFile(file)) {
      final previewUrl = _getRemoteFileUrl(file, preview: true);
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.blue.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: previewUrl.isNotEmpty
            ? Image.network(
                previewUrl,
                cacheWidth: 140,
                cacheHeight: 140,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.image_rounded,
                    color: Colors.blue,
                    size: 22,
                  );
                },
              )
            : const Icon(Icons.image_rounded, color: Colors.blue, size: 22),
      );
    }

    if (_isVideoFile(file)) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2C243B), Color(0xFF1E2238)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.redAccent.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.video_library_rounded,
              color: Colors.white70,
              size: 22,
            ),
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 10,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _getFileIconColor(file.type).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _getFileIcon(file.type),
        color: _getFileIconColor(file.type),
        size: 22,
      ),
    );
  }

  Widget _buildDownloadButton(RemoteFileInfo file) {
    final task = _getDownloadTask(file.path);

    if (task != null) {
      if (task.status == 'Starting' || task.status == 'Receiving') {
        final percent = (task.progress * 100).toInt();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF4E6AF3).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF4E6AF3).withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  value: task.progress > 0 ? task.progress : null,
                  strokeWidth: 2,
                  color: const Color(0xFF4E6AF3),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$percent%',
                style: const TextStyle(
                  color: Color(0xFF4E6AF3),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      } else if (task.status == 'Completed') {
        return IconButton(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF2AB673),
            size: 24,
          ),
          tooltip: 'Downloaded - Tap to open',
          onPressed: () async {
            try {
              await OpenFile.open(task.savePath);
            } catch (e) {
              _showErrorSnackBar('Error opening file: $e');
            }
          },
        );
      } else if (task.status == 'Failed') {
        return IconButton(
          icon: const Icon(
            Icons.replay_rounded,
            color: Colors.redAccent,
            size: 22,
          ),
          tooltip: 'Download failed - Tap to retry',
          onPressed: () => _downloadFile(file),
        );
      }
    }

    return IconButton(
      icon: const Icon(
        Icons.download_rounded,
        color: Color(0xFF2AB673),
        size: 24,
      ),
      tooltip: 'Download',
      onPressed: () => _downloadFile(file),
    );
  }

  Widget _buildActiveDownloadsBar() {
    final activeTasks = _downloadQueue
        .where((t) => t.status == 'Starting' || t.status == 'Receiving')
        .toList();

    if (activeTasks.isEmpty) return const SizedBox.shrink();

    final currentTask = activeTasks.last;
    final percent = (currentTask.progress * 100).toInt();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E2640)
            : const Color(0xFFEEF2FF),
        border: Border(
          top: BorderSide(
            color: const Color(0xFF4E6AF3).withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  value: currentTask.progress > 0 ? currentTask.progress : null,
                  strokeWidth: 2,
                  color: const Color(0xFF4E6AF3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Receiving: ${currentTask.file.name}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4E6AF3),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${_formatFileSize(currentTask.receivedBytes)} / ${_formatFileSize(currentTask.totalBytes)} ($percent%)',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4E6AF3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: currentTask.progress > 0 ? currentTask.progress : null,
              minHeight: 4,
              backgroundColor: const Color(0xFF4E6AF3).withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF4E6AF3)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFilePreviewDialog(RemoteFileInfo file) async {
    if (file.isDirectory) return;

    final previewUrl = _getRemoteFileUrl(file, preview: true);

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final task = _getDownloadTask(file.path);
            final isDownloading =
                task != null && (task.status == 'Starting' || task.status == 'Receiving');
            final isCompleted = task != null && task.status == 'Completed';

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 600,
                  maxHeight: 700,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[900]
                            : Colors.grey[100],
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isImageFile(file)
                                ? Icons.image_rounded
                                : _isVideoFile(file)
                                    ? Icons.videocam_rounded
                                    : _isAudioFile(file)
                                        ? Icons.audiotrack_rounded
                                        : _isPdfFile(file)
                                            ? Icons.picture_as_pdf_rounded
                                            : Icons.insert_drive_file_rounded,
                            color: _getFileIconColor(file.type),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              file.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            tooltip: 'Close preview',
                          ),
                        ],
                      ),
                    ),

                    // Preview Content Body
                    Flexible(
                      child: Container(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.black87
                            : Colors.grey[50],
                        alignment: Alignment.center,
                        child: _buildPreviewContentBody(file, previewUrl, setDialogState),
                      ),
                    ),

                    // Footer with live download button & info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[900]
                            : Colors.white,
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // File info summary
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Size: ${_formatFileSize(file.size)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                'Modified: ${_formatDate(file.modified)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Live status or Action Button
                          if (isDownloading) ...[
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _isVideoFile(file)
                                          ? 'Receiving & preparing to play...'
                                          : 'Receiving file...',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF4E6AF3),
                                      ),
                                    ),
                                    Text(
                                      '${_formatFileSize(task.receivedBytes)} / ${_formatFileSize(task.totalBytes)} (${(task.progress * 100).toInt()}%)',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF4E6AF3),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: task.progress > 0 ? task.progress : null,
                                    minHeight: 6,
                                    backgroundColor: const Color(0xFF4E6AF3).withValues(alpha: 0.15),
                                    valueColor: const AlwaysStoppedAnimation(Color(0xFF4E6AF3)),
                                  ),
                                ),
                              ],
                            ),
                          ] else if (isCompleted) ...[
                            ElevatedButton.icon(
                              onPressed: () async {
                                try {
                                  final result = await OpenFile.open(task.savePath);
                                  if (result.type != ResultType.done && result.message.isNotEmpty) {
                                    _showErrorSnackBar('Could not open file: ${result.message}');
                                  }
                                } catch (e) {
                                  _showErrorSnackBar('Error opening file: $e');
                                }
                              },
                              icon: Icon(
                                _isVideoFile(file)
                                    ? Icons.play_arrow_rounded
                                    : Icons.open_in_new_rounded,
                              ),
                              label: Text(_isVideoFile(file) ? 'Play Video' : 'Open File'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2AB673),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ] else ...[
                            ElevatedButton.icon(
                              onPressed: () {
                                _downloadFile(
                                  file,
                                  autoOpenOnComplete: _isVideoFile(file),
                                  onProgress: () => setDialogState(() {}),
                                );
                                setDialogState(() {});
                              },
                              icon: Icon(
                                _isVideoFile(file)
                                    ? Icons.play_circle_fill_rounded
                                    : Icons.download_rounded,
                              ),
                              label: Text(
                                _isVideoFile(file) ? 'Download & Play' : 'Download File',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4E6AF3),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPreviewContentBody(
    RemoteFileInfo file,
    String previewUrl,
    StateSetter setDialogState,
  ) {
    if (_isImageFile(file)) {
      return Stack(
        alignment: Alignment.center,
        children: [
          InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Image.network(
                previewUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                          color: const Color(0xFF4E6AF3),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Loading image preview...',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_rounded, size: 54, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Could not load image preview', style: TextStyle(color: Colors.grey)),
                    ],
                  );
                },
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white70),
                  SizedBox(width: 4),
                  Text(
                    'Pinch / scroll to zoom',
                    style: TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_isVideoFile(file)) {
      final task = _getDownloadTask(file.path);
      final isDownloading =
          task != null && (task.status == 'Starting' || task.status == 'Receiving');
      final isCompleted = task != null && task.status == 'Completed';

      void handleVideoPlayTap() async {
        if (isCompleted) {
          try {
            final result = await OpenFile.open(task.savePath);
            if (result.type != ResultType.done && result.message.isNotEmpty) {
              _showErrorSnackBar('Could not open file: ${result.message}');
            }
          } catch (e) {
            _showErrorSnackBar('Error opening file: $e');
          }
        } else if (!isDownloading) {
          _downloadFile(
            file,
            autoOpenOnComplete: true,
            onProgress: () => setDialogState(() {}),
          );
          setDialogState(() {});
        }
      }

      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: handleVideoPlayTap,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4E6AF3), Color(0xFF9C27B0)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4E6AF3).withValues(alpha: 0.35),
                        blurRadius: 18,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: isDownloading
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 60,
                              height: 60,
                              child: CircularProgressIndicator(
                                value: task.progress > 0 ? task.progress : null,
                                strokeWidth: 4,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${(task.progress * 100).toInt()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        )
                      : const Icon(
                          Icons.play_arrow_rounded,
                          size: 60,
                          color: Colors.white,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              file.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Video File • ${_formatFileSize(file.size)}',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isCompleted
                  ? 'Video downloaded! Tap play button to watch.'
                  : isDownloading
                      ? 'Downloading video... Will automatically play once complete.'
                      : 'Tap to download and automatically play video.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_isTextFile(file) && file.size < 500000) {
      return FutureBuilder<http.Response>(
        future: http.get(Uri.parse(previewUrl)).timeout(const Duration(seconds: 5)),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF4E6AF3)),
            );
          }
          if (snapshot.hasData && snapshot.data!.statusCode == 200) {
            final text = snapshot.data!.body;
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: SelectableText(
                  text,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            );
          }
          return Center(
            child: Text(
              'Text preview unavailable',
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        },
      );
    }

    // Generic file fallback
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _getFileIconColor(file.type).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getFileIcon(file.type),
              size: 54,
              color: _getFileIconColor(file.type),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            file.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Type: ${file.type}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  void _showSharedPathsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Shared Folders'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: Column(
            children: [
              const Text(
                'Select folders to share with other devices:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _sharedPaths.length,
                  itemBuilder: (context, index) {
                    final path = _sharedPaths[index];
                    return ListTile(
                      leading: const Icon(Icons.folder, size: 20),
                      title: Text(
                        p.basename(path),
                        style: const TextStyle(fontSize: 12),
                      ),
                      subtitle: Text(
                        path,
                        style: const TextStyle(fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle, size: 18),
                        onPressed: () {
                          setState(() {
                            _sharedPaths.removeAt(index);
                          });
                          Navigator.of(context).pop();
                          _showSharedPathsDialog();
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final result = await FilePicker.platform.getDirectoryPath();
              if (result != null && !_sharedPaths.contains(result)) {
                setState(() {
                  _sharedPaths.add(result);
                });
                await _saveSettings();
              }
            },
            child: const Text('Add Folder'),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String type) {
    if (type.startsWith('image/')) return Icons.image;
    if (type.startsWith('video/')) return Icons.video_file;
    if (type.startsWith('audio/')) return Icons.audio_file;
    if (type.contains('pdf')) return Icons.picture_as_pdf;
    if (type.contains('document') || type.contains('word')) return Icons.description;
    if (type.contains('spreadsheet') || type.contains('excel')) return Icons.table_chart;
    if (type.contains('presentation')) return Icons.slideshow;
    if (type.contains('zip') || type.contains('compressed')) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  Color _getFileIconColor(String type) {
    if (type.startsWith('image/')) return Colors.blue;
    if (type.startsWith('video/')) return Colors.red;
    if (type.startsWith('audio/')) return Colors.purple;
    if (type.contains('pdf')) return Colors.red;
    if (type.contains('document') || type.contains('word')) return Colors.blue;
    if (type.contains('spreadsheet') || type.contains('excel')) return const Color(0xFF2AB673);
    if (type.contains('presentation')) return Colors.orange;
    if (type.contains('zip') || type.contains('compressed')) return Colors.amber;
    return Colors.grey;
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays == 0) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }
}

// Data models for mobile sync
class SyncDevice {
  final String name;
  final String ip;
  final int port;
  final String accessCode;
  final List<String> capabilities;
  final DateTime lastSeen;

  SyncDevice({
    required this.name,
    required this.ip,
    required this.port,
    required this.accessCode,
    required this.capabilities,
    required this.lastSeen,
  });
}

class RemoteFileInfo {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;
  final String type;

  RemoteFileInfo({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
    required this.type,
  });

  factory RemoteFileInfo.fromJson(Map<String, dynamic> json) {
    return RemoteFileInfo(
      name: json['name'],
      path: json['path'],
      isDirectory: json['isDirectory'],
      size: json['size'],
      modified: DateTime.parse(json['modified']),
      type: json['type'],
    );
  }
}

class DownloadTask {
  final RemoteFileInfo file;
  final String savePath;
  double progress;
  String status; // 'Starting', 'Receiving', 'Completed', 'Failed'
  int receivedBytes;
  int totalBytes;

  DownloadTask({
    required this.file,
    required this.savePath,
    required this.progress,
    required this.status,
    this.receivedBytes = 0,
    this.totalBytes = 0,
  });
}
  
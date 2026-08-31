import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:mime/mime.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:speedsharemob/DeviceNameManager.dart';
import 'package:speedsharemob/NetworkStatusWidget.dart';
import 'package:speedsharemob/SpeedShareAppBar.dart';
import 'package:speedsharemob/BackgroundService.dart';

enum StreamTabMode { connect, stream }
enum StreamMediaType { audio, video }

class StreamMediaItem {
  final String id;
  final String path;
  final String name;
  final StreamMediaType type;
  final int size;
  final String extension;
  final String? artist;
  final String? album;

  StreamMediaItem({
    required this.id,
    required this.path,
    required this.name,
    required this.type,
    required this.size,
    required this.extension,
    this.artist,
    this.album,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type == StreamMediaType.audio ? 'audio' : 'video',
    'size': size,
    'extension': extension,
    'artist': artist ?? '',
    'album': album ?? '',
  };

  factory StreamMediaItem.fromJson(Map<String, dynamic> json) => StreamMediaItem(
    id: json['id'] ?? '',
    path: '',
    name: json['name'] ?? 'Unknown Media',
    type: json['type'] == 'audio' ? StreamMediaType.audio : StreamMediaType.video,
    size: json['size'] ?? 0,
    extension: json['extension'] ?? '',
    artist: json['artist'],
    album: json['album'],
  );
}

class StreamDevice {
  final String name;
  final String ip;
  final int port;
  final bool hasAccessCode;
  final int mediaCount;
  final int audioCount;
  final int videoCount;
  DateTime lastSeen;

  StreamDevice({
    required this.name,
    required this.ip,
    required this.port,
    required this.hasAccessCode,
    this.mediaCount = 0,
    this.audioCount = 0,
    this.videoCount = 0,
    required this.lastSeen,
  });
}

class ConnectedStreamClient {
  final String ip;
  final String name;
  DateTime lastActive;
  String currentPlaying;

  ConnectedStreamClient({
    required this.ip,
    required this.name,
    required this.lastActive,
    required this.currentPlaying,
  });
}

class StreamScreen extends StatefulWidget {
  const StreamScreen({super.key});

  @override
  State<StreamScreen> createState() => StreamScreenState();
}

class StreamScreenState extends State<StreamScreen> with TickerProviderStateMixin {
  // Mode switcher: Connect vs Stream (Host)
  StreamTabMode _activeTab = StreamTabMode.connect;

  // Stream Server (Host)
  HttpServer? _streamServer;
  RawDatagramSocket? _streamDiscoverySocket;
  int _serverPort = 8084;
  String? _accessCode;
  bool _isStreaming = false;
  final List<StreamMediaItem> _hostedMediaList = [];
  final Map<String, ConnectedStreamClient> _connectedListeners = {};

  // Stream Client (Connect)
  final List<StreamDevice> _discoveredHosts = [];
  StreamDevice? _connectedDevice;
  String? _devicePin;
  List<StreamMediaItem> _remoteCatalog = [];
  bool _isLoadingCatalog = false;
  String _searchQuery = '';
  String _selectedCategoryFilter = 'All'; // 'All', 'Music', 'Videos'
  Timer? _discoveryTimer;

  // Audio Playback Engine
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamMediaItem? _currentAudioItem;
  bool _isAudioPlaying = false;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  StreamSubscription? _audioPosSub;
  StreamSubscription? _audioDurSub;
  StreamSubscription? _audioStateSub;
  StreamSubscription? _audioCompleteSub;
  double _audioVolume = 1.0;
  bool _isAudioLoop = false;

  // Animation Controllers
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _discRotationController;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initAudioListeners();
    _initDiscovery();
    _startPeriodicDiscovery();
  }

  @override
  void dispose() {
    _discoveryTimer?.cancel();
    _pulseController.dispose();
    _discRotationController.dispose();
    _audioPosSub?.cancel();
    _audioDurSub?.cancel();
    _audioStateSub?.cancel();
    _audioCompleteSub?.cancel();
    _audioPlayer.dispose();
    _streamDiscoverySocket?.close();
    _streamServer?.close(force: true);
    super.dispose();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _discRotationController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    );
  }

  void _initAudioListeners() {
    _audioPosSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _audioPosition = pos);
    });

    _audioDurSub = _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _audioDuration = dur);
    });

    _audioStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isAudioPlaying = state == PlayerState.playing;
        });
        if (state == PlayerState.playing) {
          _discRotationController.repeat();
        } else {
          _discRotationController.stop();
        }
      }
    });

    _audioCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (_isAudioLoop) {
        _audioPlayer.seek(Duration.zero);
        _audioPlayer.resume();
      } else {
        _playNextAudioTrack();
      }
    });
  }

  bool _isTcpScanning = false;

  Future<void> _initDiscovery() async {
    try {
      try {
        _streamDiscoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          8085,
          reuseAddress: true,
        );
      } catch (e) {
        _streamDiscoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          8085,
        );
      }
      _streamDiscoverySocket?.broadcastEnabled = true;

      try {
        _streamDiscoverySocket?.joinMulticast(InternetAddress('239.255.255.250'));
      } catch (_) {}

      _streamDiscoverySocket?.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _streamDiscoverySocket?.receive();
          if (datagram != null) {
            _handleDiscoveryDatagram(datagram);
          }
        }
      }, onError: (e) {
        if (e is SocketException &&
            (e.osError?.errorCode == 65 || e.osError?.errorCode == 51)) {
          return;
        }
        debugPrint('Stream discovery socket error: $e');
      });
    } catch (e) {
      debugPrint('Error initializing stream discovery: $e');
    }
  }

  void _startPeriodicDiscovery() {
    _discoveryTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_isStreaming) {
        _sendStreamAnnouncement();
      }
      _sendStreamProbe();
      _cleanupStaleHosts();
    });
  }

  void _cleanupStaleHosts() {
    final threshold = DateTime.now().subtract(const Duration(seconds: 15));
    if (mounted) {
      setState(() {
        _discoveredHosts.removeWhere((d) => d.lastSeen.isBefore(threshold));
      });
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
      for (var iface in interfaces) {
        for (var addr in iface.addresses) {
          if (addr.address == incomingIp) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  void _handleDiscoveryDatagram(Datagram datagram) async {
    try {
      final message = utf8.decode(datagram.data);
      final data = json.decode(message) as Map<String, dynamic>;
      final senderIp = datagram.address.address;
      final senderName = data['deviceName'] as String?;

      if (await _isSelfDevice(senderIp, senderName)) return;

      if (data['type'] == 'SPEEDSHARE_STREAM_GOODBYE') {
        if (mounted) {
          setState(() {
            _discoveredHosts.removeWhere((d) => d.ip == senderIp);
          });
        }
      } else if (data['type'] == 'SPEEDSHARE_STREAM_PROBE') {
        if (_isStreaming) {
          _sendStreamAnnouncement();
        }
      } else if (data['type'] == 'SPEEDSHARE_STREAM_ANNOUNCE') {
        final host = StreamDevice(
          name: data['deviceName'] ?? 'SpeedShare Stream Host',
          ip: senderIp,
          port: data['streamPort'] ?? 8084,
          hasAccessCode: data['hasAccessCode'] ?? false,
          mediaCount: data['mediaCount'] ?? 0,
          audioCount: data['audioCount'] ?? 0,
          videoCount: data['videoCount'] ?? 0,
          lastSeen: DateTime.now(),
        );

        if (mounted) {
          setState(() {
            _discoveredHosts.removeWhere((d) => d.ip == host.ip);
            _discoveredHosts.add(host);
          });
        }
      }
    } catch (e) {
      debugPrint('Error parsing stream discovery packet: $e');
    }
  }

  Future<void> _sendStreamAnnouncement() async {
    if (_streamDiscoverySocket == null || !_isStreaming) return;
    try {
      final deviceName = await DeviceNameManager.getDeviceName();
      final audioCount = _hostedMediaList.where((m) => m.type == StreamMediaType.audio).length;
      final videoCount = _hostedMediaList.where((m) => m.type == StreamMediaType.video).length;

      final message = json.encode({
        'type': 'SPEEDSHARE_STREAM_ANNOUNCE',
        'deviceName': deviceName,
        'streamPort': _serverPort,
        'hasAccessCode': _accessCode != null && _accessCode!.isNotEmpty,
        'mediaCount': _hostedMediaList.length,
        'audioCount': audioCount,
        'videoCount': videoCount,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final bytes = utf8.encode(message);

      // Global broadcast
      try {
        _streamDiscoverySocket?.send(bytes, InternetAddress('255.255.255.255'), 8085);
      } catch (_) {}

      // Multicast
      try {
        _streamDiscoverySocket?.send(bytes, InternetAddress('239.255.255.250'), 8085);
      } catch (_) {}

      // Subnet broadcasts
      final interfaces = await NetworkInterface.list();
      for (var iface in interfaces) {
        if (iface.name.toLowerCase().contains('lo')) continue;
        for (var addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final subnet = parts.sublist(0, 3).join('.');
              try {
                _streamDiscoverySocket?.send(bytes, InternetAddress('$subnet.255'), 8085);
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _sendStreamProbe() async {
    if (_streamDiscoverySocket == null) return;
    try {
      final deviceName = await DeviceNameManager.getDeviceName();
      final message = json.encode({
        'type': 'SPEEDSHARE_STREAM_PROBE',
        'deviceName': deviceName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      final bytes = utf8.encode(message);

      // Global broadcast
      try {
        _streamDiscoverySocket?.send(bytes, InternetAddress('255.255.255.255'), 8085);
      } catch (_) {}

      // Multicast
      try {
        _streamDiscoverySocket?.send(bytes, InternetAddress('239.255.255.250'), 8085);
      } catch (_) {}

      // Subnet broadcasts
      final interfaces = await NetworkInterface.list();
      for (var iface in interfaces) {
        if (iface.name.toLowerCase().contains('lo')) continue;
        for (var addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final subnet = parts.sublist(0, 3).join('.');
              try {
                _streamDiscoverySocket?.send(bytes, InternetAddress('$subnet.255'), 8085);
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}

    // Run TCP subnet scanner fallback if not streaming
    if (!_isStreaming && !_isTcpScanning) {
      _checkDirectStreamTCPConnections();
    }
  }

  Future<void> _checkDirectStreamTCPConnections() async {
    if (_isTcpScanning) return;
    _isTcpScanning = true;
    try {
      final interfaces = await NetworkInterface.list();
      final localIps = interfaces
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .toSet();
      localIps.addAll(['127.0.0.1', '::1']);

      for (var interface in interfaces) {
        if (interface.name.toLowerCase().contains('lo')) continue;
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.address.startsWith('127.') &&
              !addr.address.startsWith('169.254.')) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final prefix = parts.sublist(0, 3).join('.');
              final currentOctet = int.tryParse(parts[3]) ?? 1;

              final prioritySet = <int>{};
              prioritySet.add(1); // Gateway
              for (int delta = 1; delta <= 20; delta++) {
                if (currentOctet - delta >= 1) prioritySet.add(currentOctet - delta);
                if (currentOctet + delta <= 254) prioritySet.add(currentOctet + delta);
              }
              for (int i = 1; i <= 254; i++) {
                prioritySet.add(i);
              }

              final ipsToScan = prioritySet
                  .map((i) => '$prefix.$i')
                  .where((ip) => !localIps.contains(ip))
                  .toList();

              const int chunkSize = 30;
              for (int j = 0; j < ipsToScan.length; j += chunkSize) {
                if (!mounted) break;
                final end = (j + chunkSize < ipsToScan.length)
                    ? j + chunkSize
                    : ipsToScan.length;
                final chunk = ipsToScan.sublist(j, end);
                await Future.wait(
                  chunk.map((ip) => _probeStreamHostTcp(ip)),
                );
              }
            }
          }
        }
      }
    } catch (_) {
    } finally {
      _isTcpScanning = false;
    }
  }

  Future<void> _probeStreamHostTcp(String ip) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 450);
    try {
      final request = await client.getUrl(Uri.parse('http://$ip:$_serverPort/api/stream/info'));
      final response = await request.close().timeout(const Duration(milliseconds: 600));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = json.decode(body) as Map<String, dynamic>;
        final deviceName = data['deviceName'] as String? ?? 'SpeedShare Stream Host';
        final hasCode = data['hasAccessCode'] as bool? ?? false;
        final mediaCount = data['mediaCount'] as int? ?? 0;

        final host = StreamDevice(
          name: deviceName,
          ip: ip,
          port: _serverPort,
          hasAccessCode: hasCode,
          mediaCount: mediaCount,
          lastSeen: DateTime.now(),
        );

        if (mounted) {
          setState(() {
            _discoveredHosts.removeWhere((d) => d.ip == ip);
            _discoveredHosts.add(host);
          });
        }
      }
    } catch (_) {
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _sendStreamGoodbye() async {
    if (_streamDiscoverySocket == null) return;
    try {
      final message = json.encode({
        'type': 'SPEEDSHARE_STREAM_GOODBYE',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      final bytes = utf8.encode(message);

      try {
        _streamDiscoverySocket?.send(bytes, InternetAddress('255.255.255.255'), 8085);
      } catch (_) {}
      try {
        _streamDiscoverySocket?.send(bytes, InternetAddress('239.255.255.250'), 8085);
      } catch (_) {}
    } catch (_) {}
  }

  // --- STREAM HOST SERVER LOGIC ---

  Future<void> _toggleStreamServer() async {
    if (_isStreaming) {
      await _stopStreamServer();
    } else {
      await _startStreamServer();
    }
  }

  Future<void> _startStreamServer() async {
    if (_hostedMediaList.isEmpty) {
      _showSnackBar('Please select at least one music or video file to stream', isError: true);
      return;
    }

    try {
      // Generate 4-digit numeric code
      _accessCode = (1000 + Random().nextInt(9000)).toString();

      // Bind HTTP server
      _streamServer = await HttpServer.bind(InternetAddress.anyIPv4, _serverPort);
      _streamServer!.listen(
        _handleStreamHttpRequest,
        onError: (e) => debugPrint('Stream server error: $e'),
      );

      setState(() {
        _isStreaming = true;
      });

      _pulseController.repeat(reverse: true);
      _sendStreamAnnouncement();

      // Keep CPU awake and prevent Android from killing the stream in background
      BackgroundService.start(
        key: 'stream',
        title: 'SpeedShare — Streaming',
        body: 'Live media stream running on port $_serverPort',
      );
      _showSnackBar('Live Media Stream started on port $_serverPort! PIN: $_accessCode');
    } catch (e) {
      // Fallback to random port if 8084 occupied
      try {
        _streamServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
        _serverPort = _streamServer!.port;
        _streamServer!.listen(_handleStreamHttpRequest);

        setState(() {
          _isStreaming = true;
        });

        _pulseController.repeat(reverse: true);
        _sendStreamAnnouncement();
        _showSnackBar('Stream started on port $_serverPort! PIN: $_accessCode');
      } catch (err) {
        _showSnackBar('Failed to start stream server: $err', isError: true);
      }
    }
  }

  Future<void> _stopStreamServer() async {
    try {
      await _sendStreamGoodbye();
      await _streamServer?.close(force: true);
      _streamServer = null;
      _accessCode = null;
      _connectedListeners.clear();

      setState(() {
        _isStreaming = false;
      });

      BackgroundService.stop(key: 'stream');
      _pulseController.stop();
      _showSnackBar('Media streaming stopped');
    } catch (e) {
      _showSnackBar('Error stopping stream: $e', isError: true);
    }
  }

  void _recordStreamListener(String clientIp, String action) {
    if (mounted) {
      setState(() {
        if (_connectedListeners.containsKey(clientIp)) {
          final l = _connectedListeners[clientIp]!;
          l.lastActive = DateTime.now();
          l.currentPlaying = action;
        } else {
          _connectedListeners[clientIp] = ConnectedStreamClient(
            ip: clientIp,
            name: 'Device ($clientIp)',
            lastActive: DateTime.now(),
            currentPlaying: action,
          );
        }
      });
    }
  }

  void _handleStreamHttpRequest(HttpRequest request) async {
    // Add CORS headers for web/flexible clients
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', '*');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 204;
      await request.response.close();
      return;
    }

    try {
      final uri = request.uri;
      final clientIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';

      // 1. Info / Ping Endpoint
      if (uri.path == '/api/stream/info') {
        final deviceName = await DeviceNameManager.getDeviceName();
        final resp = json.encode({
          'deviceName': deviceName,
          'hasAccessCode': _accessCode != null && _accessCode!.isNotEmpty,
          'mediaCount': _hostedMediaList.length,
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(resp);
        await request.response.close();
        return;
      }

      // Check PIN
      final providedCode = uri.queryParameters['code']?.trim();
      if (_accessCode != null && _accessCode!.isNotEmpty && providedCode != _accessCode) {
        request.response.statusCode = 403;
        request.response.headers.contentType = ContentType.json;
        request.response.write(json.encode({'error': 'Invalid stream PIN'}));
        await request.response.close();
        return;
      }

      // 2. Catalog Endpoint
      if (uri.path == '/api/stream/catalog') {
        final catalog = _hostedMediaList.map((m) => m.toJson()).toList();
        request.response.headers.contentType = ContentType.json;
        request.response.write(json.encode({
          'host': await DeviceNameManager.getDeviceName(),
          'items': catalog,
        }));
        await request.response.close();
        return;
      }

      // 3. Media Streaming Endpoint with Range / 206 Partial Content
      if (uri.path == '/api/stream/media') {
        final mediaId = uri.queryParameters['id'];
        final item = _hostedMediaList.firstWhere(
          (m) => m.id == mediaId,
          orElse: () => StreamMediaItem(
            id: '',
            path: '',
            name: '',
            type: StreamMediaType.audio,
            size: 0,
            extension: '',
          ),
        );

        if (item.id.isEmpty || !File(item.path).existsSync()) {
          request.response.statusCode = 404;
          request.response.write('Media item not found');
          await request.response.close();
          return;
        }

        _recordStreamListener(clientIp, item.name);

        final file = File(item.path);
        final fileSize = await file.length();
        final mimeTypeStr = lookupMimeType(item.path) ??
            (item.type == StreamMediaType.audio ? 'audio/mpeg' : 'video/mp4');

        ContentType contentType;
        try {
          final parts = mimeTypeStr.split('/');
          contentType = ContentType(parts[0], parts[1]);
        } catch (_) {
          contentType = ContentType.binary;
        }

        request.response.headers.contentType = contentType;
        request.response.headers.add('Accept-Ranges', 'bytes');
        request.response.headers.add(
          'Content-Disposition',
          'inline; filename="${p.basename(item.path)}"',
        );

        // HTTP 206 Range Request
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
        return;
      }

      request.response.statusCode = 404;
      await request.response.close();
    } catch (e) {
      debugPrint('Error serving stream request: $e');
      try {
        request.response.statusCode = 500;
        await request.response.close();
      } catch (_) {}
    }
  }

  // --- HOST MEDIA PICKER ---

  Future<void> _pickMediaFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'mp3', 'wav', 'aac', 'm4a', 'flac', 'ogg', 'wma', 'opus',
          'mp4', 'mkv', 'webm', 'mov', 'avi', 'wmv', '3gp', 'm4v'
        ],
      );

      if (result != null && result.files.isNotEmpty) {
        for (var file in result.files) {
          if (file.path != null && file.path!.isNotEmpty) {
            _addFileToHostedMedia(file.path!);
          }
        }
        setState(() {});
        if (_isStreaming) _sendStreamAnnouncement();
      }
    } catch (e) {
      _showSnackBar('Error picking files: $e', isError: true);
    }
  }

  Future<void> _pickMediaFolder() async {
    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null) {
        final dir = Directory(selectedDirectory);
        final allowedExts = {
          '.mp3', '.wav', '.aac', '.m4a', '.flac', '.ogg', '.wma', '.opus',
          '.mp4', '.mkv', '.webm', '.mov', '.avi', '.wmv', '.3gp', '.m4v'
        };

        int addedCount = 0;
        await for (var entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (allowedExts.contains(ext)) {
              _addFileToHostedMedia(entity.path);
              addedCount++;
            }
          }
        }
        setState(() {});
        _showSnackBar('Added $addedCount media items from folder');
        if (_isStreaming) _sendStreamAnnouncement();
      }
    } catch (e) {
      _showSnackBar('Error selecting folder: $e', isError: true);
    }
  }

  void _addFileToHostedMedia(String filePath) {
    if (_hostedMediaList.any((m) => m.path == filePath)) return;

    final name = p.basename(filePath);
    final ext = p.extension(filePath).toLowerCase();
    final audioExts = {'.mp3', '.wav', '.aac', '.m4a', '.flac', '.ogg', '.wma', '.opus'};
    final isAudio = audioExts.contains(ext);
    final file = File(filePath);
    final size = file.existsSync() ? file.lengthSync() : 0;
    final id = (filePath.hashCode ^ DateTime.now().microsecondsSinceEpoch).abs().toString();

    _hostedMediaList.add(StreamMediaItem(
      id: id,
      path: filePath,
      name: name,
      type: isAudio ? StreamMediaType.audio : StreamMediaType.video,
      size: size,
      extension: ext.replaceAll('.', '').toUpperCase(),
    ));
  }

  void _removeHostedMedia(String id) {
    setState(() {
      _hostedMediaList.removeWhere((m) => m.id == id);
    });
    if (_isStreaming) _sendStreamAnnouncement();
  }

  void _clearAllHostedMedia() {
    setState(() {
      _hostedMediaList.clear();
    });
    if (_isStreaming) _sendStreamAnnouncement();
  }

  // --- CONNECT / CLIENT LOGIC ---

  Future<void> _connectToHost(StreamDevice host) async {
    if (host.hasAccessCode) {
      final pin = await _showPinDialog(host.name);
      if (pin == null || pin.isEmpty) return;
      _devicePin = pin;
    } else {
      _devicePin = null;
    }

    _connectedDevice = host;
    await _fetchHostCatalog();
  }

  Future<String?> _showPinDialog(String hostName) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.lock_rounded, color: Color(0xFF4E6AF3)),
            const SizedBox(width: 8),
            Expanded(child: Text('Enter Stream PIN for $hostName', style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 6, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: 'PIN',
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4E6AF3),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchHostCatalog() async {
    if (_connectedDevice == null) return;

    setState(() {
      _isLoadingCatalog = true;
    });

    try {
      final codeParam = _devicePin != null ? '&code=$_devicePin' : '';
      final uri = Uri.parse('http://${_connectedDevice!.ip}:${_connectedDevice!.port}/api/stream/catalog?$codeParam');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = (data['items'] as List)
            .map((item) => StreamMediaItem.fromJson(item))
            .toList();

        setState(() {
          _remoteCatalog = items;
          _isLoadingCatalog = false;
        });
      } else if (response.statusCode == 403) {
        _showSnackBar('Invalid PIN for ${_connectedDevice!.name}', isError: true);
        setState(() {
          _isLoadingCatalog = false;
          _connectedDevice = null;
        });
      } else {
        _showSnackBar('Failed to load stream catalog (${response.statusCode})', isError: true);
        setState(() => _isLoadingCatalog = false);
      }
    } catch (e) {
      _showSnackBar('Error connecting to host: $e', isError: true);
      setState(() => _isLoadingCatalog = false);
    }
  }

  void _disconnectFromHost() {
    if (_currentAudioItem != null && !_isStreaming) {
      _audioPlayer.stop();
      setState(() {
        _currentAudioItem = null;
        _isAudioPlaying = false;
      });
    }
    setState(() {
      _connectedDevice = null;
      _devicePin = null;
      _remoteCatalog = [];
      _searchQuery = '';
      _selectedCategoryFilter = 'All';
    });
    _showSnackBar('Disconnected from host');
  }

  void _playMediaItem(StreamMediaItem item, {bool isLocalHost = false}) {
    if (item.type == StreamMediaType.audio) {
      _startAudioStream(item, isLocalHost: isLocalHost);
    } else {
      _startVideoStream(item, isLocalHost: isLocalHost);
    }
  }

  void _startAudioStream(StreamMediaItem item, {bool isLocalHost = false}) async {
    try {
      await _audioPlayer.stop();
      setState(() {
        _currentAudioItem = item;
        _isAudioPlaying = false;
        _audioPosition = Duration.zero;
        _audioDuration = Duration.zero;
      });

      if (isLocalHost) {
        await _audioPlayer.play(DeviceFileSource(item.path));
      } else {
        final codeParam = _devicePin != null ? '&code=$_devicePin' : '';
        final streamUrl = 'http://${_connectedDevice!.ip}:${_connectedDevice!.port}/api/stream/media?id=${item.id}$codeParam';
        await _audioPlayer.play(UrlSource(streamUrl));
      }
    } catch (e) {
      _showSnackBar('Error playing audio: $e', isError: true);
    }
  }

  void _playNextAudioTrack() {
    final list = _activeTab == StreamTabMode.connect
        ? _remoteCatalog.where((m) => m.type == StreamMediaType.audio).toList()
        : _hostedMediaList.where((m) => m.type == StreamMediaType.audio).toList();

    if (list.isEmpty || _currentAudioItem == null) return;
    final currentIndex = list.indexWhere((m) => m.id == _currentAudioItem!.id);
    if (currentIndex != -1 && currentIndex + 1 < list.length) {
      _playMediaItem(list[currentIndex + 1], isLocalHost: _activeTab == StreamTabMode.stream);
    } else if (list.isNotEmpty) {
      _playMediaItem(list.first, isLocalHost: _activeTab == StreamTabMode.stream);
    }
  }

  void _playPreviousAudioTrack() {
    final list = _activeTab == StreamTabMode.connect
        ? _remoteCatalog.where((m) => m.type == StreamMediaType.audio).toList()
        : _hostedMediaList.where((m) => m.type == StreamMediaType.audio).toList();

    if (list.isEmpty || _currentAudioItem == null) return;
    final currentIndex = list.indexWhere((m) => m.id == _currentAudioItem!.id);
    if (currentIndex > 0) {
      _playMediaItem(list[currentIndex - 1], isLocalHost: _activeTab == StreamTabMode.stream);
    }
  }

  void _startVideoStream(StreamMediaItem item, {bool isLocalHost = false}) {
    String videoUrl;
    if (isLocalHost) {
      videoUrl = item.path;
    } else {
      final codeParam = _devicePin != null ? '&code=$_devicePin' : '';
      videoUrl = 'http://${_connectedDevice!.ip}:${_connectedDevice!.port}/api/stream/media?id=${item.id}$codeParam';
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoStreamPlayerModal(
          mediaItem: item,
          mediaUrl: videoUrl,
          isLocal: isLocalHost,
        ),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF2AB673),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // --- UI BUILD METHODS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SpeedShareAppBar(
        title: 'SpeedShare Stream',
        subtitle: _activeTab == StreamTabMode.stream ? 'Host Media Live' : 'Stream Media Direct',
      ),
      body: Column(
        children: [
          // Network connection status header widget
          const NetworkStatusWidget(),

          // Dual Tab Mode Switcher: Connect vs Stream
          _buildTabSwitcher(),

          // Main Tab Body
          Expanded(
            child: _activeTab == StreamTabMode.connect
                ? _buildConnectTab()
                : _buildStreamHostTab(),
          ),

          // Persistent Audio Mini Player (if audio loaded)
          if (_currentAudioItem != null) _buildAudioMiniPlayer(),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[200],
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              title: 'Connect & Play',
              icon: Icons.play_circle_fill_rounded,
              isSelected: _activeTab == StreamTabMode.connect,
              onTap: () {
                setState(() => _activeTab = StreamTabMode.connect);
                _sendStreamProbe();
              },
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildTabButton(
              title: 'Stream / Host',
              icon: Icons.podcasts_rounded,
              isSelected: _activeTab == StreamTabMode.stream,
              onTap: () => setState(() => _activeTab = StreamTabMode.stream),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF4E6AF3) : const Color(0xFF4E6AF3))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF4E6AF3).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.grey[400] : Colors.grey[700]),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.grey[400] : Colors.grey[700]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- CONNECT TAB (RECEIVE / BROWSE / PLAY) ---

  Widget _buildConnectTab() {
    if (_connectedDevice != null) {
      return _buildRemoteCatalogView();
    }

    return RefreshIndicator(
      onRefresh: () async {
        _sendStreamProbe();
        await Future.delayed(const Duration(milliseconds: 600));
      },
      color: const Color(0xFF4E6AF3),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Header Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4E6AF3).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.wifi_tethering_rounded, color: Color(0xFF4E6AF3), size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nearby Stream Hosts',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Stream songs and movies directly without downloading them',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.sync_rounded),
                    tooltip: 'Refresh',
                    onPressed: _sendStreamProbe,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Discovered Hosts List
          if (_discoveredHosts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF4E6AF3).withValues(alpha: 0.08),
                        ),
                        child: const Icon(Icons.radar_rounded, size: 48, color: Color(0xFF4E6AF3)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Searching for streaming devices...',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Make sure the host device has "Stream" active on the same Wi-Fi',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _showManualConnectDialog,
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: const Text('Connect with IP'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              'Discovered (${_discoveredHosts.length})',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _discoveredHosts.length,
              itemBuilder: (context, index) {
                final host = _discoveredHosts[index];
                return _buildHostCard(host);
              },
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: _showManualConnectDialog,
                icon: const Icon(Icons.add_link_rounded, size: 16),
                label: const Text('Manual IP Connect'),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

  Widget _buildHostCard(StreamDevice host) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.speaker_group_rounded, color: Colors.white, size: 22),
        ),
        title: Text(
          host.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Text('${host.ip}:${host.port}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildBadge(Icons.audiotrack_rounded, '${host.audioCount} Songs', const Color(0xFF4E6AF3)),
                const SizedBox(width: 6),
                _buildBadge(Icons.videocam_rounded, '${host.videoCount} Videos', const Color(0xFF2AB673)),
              ],
            ),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: () => _connectToHost(host),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4E6AF3),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          child: const Text('Browse', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _buildBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  void _showManualConnectDialog() {
    final ipController = TextEditingController();
    final portController = TextEditingController(text: '8084');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Connect to Stream Host'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: 'Host IP Address',
                hintText: 'e.g. 192.168.1.5',
                prefixIcon: Icon(Icons.wifi_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Stream Port',
                prefixIcon: Icon(Icons.settings_ethernet_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final ip = ipController.text.trim();
              final port = int.tryParse(portController.text.trim()) ?? 8084;
              if (ip.isNotEmpty) {
                Navigator.pop(context);
                final customHost = StreamDevice(
                  name: 'Custom Host ($ip)',
                  ip: ip,
                  port: port,
                  hasAccessCode: false,
                  lastSeen: DateTime.now(),
                );
                _connectToHost(customHost);
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  // --- REMOTE CATALOG VIEW (CONNECTED TO HOST) ---

  Widget _buildRemoteCatalogView() {
    final filtered = _remoteCatalog.where((item) {
      if (_selectedCategoryFilter == 'Music' && item.type != StreamMediaType.audio) return false;
      if (_selectedCategoryFilter == 'Videos' && item.type != StreamMediaType.video) return false;
      if (_searchQuery.isNotEmpty && !item.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Connected Host Header Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[900]
                : Colors.blue.withValues(alpha: 0.05),
            border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2AB673).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_tethering_rounded, color: Color(0xFF2AB673), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _connectedDevice!.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${_remoteCatalog.length} media items • Swipe down to refresh',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _disconnectFromHost,
                icon: const Icon(Icons.link_off_rounded, size: 16, color: Colors.redAccent),
                label: const Text(
                  'Disconnect',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),

        // Search & Category Filters
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search songs & videos...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[800]
                        : Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildCategoryChip('All', _remoteCatalog.length),
              const SizedBox(width: 4),
              _buildCategoryChip(
                'Music',
                _remoteCatalog.where((m) => m.type == StreamMediaType.audio).length,
              ),
              const SizedBox(width: 4),
              _buildCategoryChip(
                'Videos',
                _remoteCatalog.where((m) => m.type == StreamMediaType.video).length,
              ),
            ],
          ),
        ),

        // Catalog List with Pull to Refresh
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchHostCatalog,
            color: const Color(0xFF4E6AF3),
            child: _isLoadingCatalog
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverFillRemaining(
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.video_library_rounded, size: 50, color: Colors.grey[400]),
                                  const SizedBox(height: 12),
                                  Text(
                                    _searchQuery.isNotEmpty
                                        ? 'No matching media found'
                                        : 'No media shared by host',
                                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Swipe down to refresh catalog',
                                    style: TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final isPlayingThis = _currentAudioItem?.id == item.id;
                          return _buildMediaItemTile(item, isPlayingThis: isPlayingThis);
                        },
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChip(String label, int count) {
    final isSelected = _selectedCategoryFilter == label;
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _selectedCategoryFilter = label);
      },
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : null,
      ),
      selectedColor: const Color(0xFF4E6AF3),
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildMediaItemTile(StreamMediaItem item, {required bool isPlayingThis}) {
    final isAudio = item.type == StreamMediaType.audio;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isPlayingThis ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPlayingThis
            ? const BorderSide(color: Color(0xFF4E6AF3), width: 1.5)
            : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: isAudio
                ? const Color(0xFF4E6AF3).withValues(alpha: 0.15)
                : const Color(0xFF2AB673).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isAudio ? Icons.music_note_rounded : Icons.movie_rounded,
            color: isAudio ? const Color(0xFF4E6AF3) : const Color(0xFF2AB673),
            size: 22,
          ),
        ),
        title: Text(
          item.name,
          style: TextStyle(
            fontWeight: isPlayingThis ? FontWeight.bold : FontWeight.w600,
            fontSize: 14,
            color: isPlayingThis ? const Color(0xFF4E6AF3) : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Text(item.extension, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(width: 8),
            Text(_formatBytes(item.size), style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        trailing: ElevatedButton.icon(
          onPressed: () => _playMediaItem(item, isLocalHost: false),
          icon: Icon(
            isPlayingThis && _isAudioPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            size: 18,
          ),
          label: Text(isPlayingThis && _isAudioPlaying ? 'Playing' : 'Stream'),
          style: ElevatedButton.styleFrom(
            backgroundColor: isPlayingThis ? const Color(0xFF2AB673) : const Color(0xFF4E6AF3),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  // --- STREAM HOST TAB (HOST / SELECT / MANAGE) ---

  Widget _buildStreamHostTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Host Status Card
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isStreaming
                              ? const Color(0xFF2AB673).withValues(alpha: 0.15)
                              : Colors.grey.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isStreaming ? Icons.podcasts_rounded : Icons.podcasts_outlined,
                          color: _isStreaming ? const Color(0xFF2AB673) : Colors.grey,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isStreaming ? 'Stream Server Active' : 'Stream Server Offline',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isStreaming
                                  ? 'Broadcasting ${_hostedMediaList.length} items on port $_serverPort'
                                  : 'Select music & videos, then start streaming to nearby devices',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (_isStreaming && _accessCode != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4E6AF3).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF4E6AF3).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Stream PIN Code:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          Row(
                            children: [
                              Text(
                                _accessCode!,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 3,
                                  color: Color(0xFF4E6AF3),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 18, color: Color(0xFF4E6AF3)),
                                tooltip: 'Copy PIN',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _accessCode!));
                                  _showSnackBar('PIN copied to clipboard');
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _toggleStreamServer,
                      icon: Icon(_isStreaming ? Icons.stop_circle_rounded : Icons.play_circle_filled_rounded),
                      label: Text(
                        _isStreaming ? 'Stop Streaming' : 'Start Streaming Live',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isStreaming ? Colors.redAccent : const Color(0xFF2AB673),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Action Buttons to Add Media
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickMediaFiles,
                  icon: const Icon(Icons.add_to_photos_rounded, size: 18),
                  label: const Text('Add Files'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickMediaFolder,
                  icon: const Icon(Icons.create_new_folder_rounded, size: 18),
                  label: const Text('Add Folder'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Hosted Media Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Hosted Media (${_hostedMediaList.length})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              if (_hostedMediaList.isNotEmpty)
                TextButton(
                  onPressed: _clearAllHostedMedia,
                  child: const Text('Clear All', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
            ],
          ),

          const SizedBox(height: 8),

          if (_hostedMediaList.isEmpty)
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.queue_music_rounded, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      const Text(
                        'No music or video selected yet',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Click "Add Files" or "Add Folder" to add songs and videos to your stream',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _hostedMediaList.length,
              itemBuilder: (context, index) {
                final item = _hostedMediaList[index];
                final isAudio = item.type == StreamMediaType.audio;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isAudio
                            ? const Color(0xFF4E6AF3).withValues(alpha: 0.15)
                            : const Color(0xFF2AB673).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isAudio ? Icons.music_note_rounded : Icons.movie_rounded,
                        color: isAudio ? const Color(0xFF4E6AF3) : const Color(0xFF2AB673),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${item.extension} • ${_formatBytes(item.size)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.play_circle_outline_rounded, size: 22, color: Color(0xFF4E6AF3)),
                          tooltip: 'Preview',
                          onPressed: () => _playMediaItem(item, isLocalHost: true),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
                          tooltip: 'Remove',
                          onPressed: () => _removeHostedMedia(item.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          // Connected Listeners Section (if any)
          if (_connectedListeners.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Connected Listeners (${_connectedListeners.length})',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _connectedListeners.length,
              itemBuilder: (context, index) {
                final client = _connectedListeners.values.elementAt(index);
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.headphones_rounded, color: Color(0xFF2AB673)),
                    title: Text(client.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Streaming: ${client.currentPlaying}', style: const TextStyle(fontSize: 11)),
                    trailing: const Icon(Icons.fiber_manual_record_rounded, size: 12, color: Color(0xFF2AB673)),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // --- AUDIO MINI PLAYER & FULL MODAL ---

  Widget _buildAudioMiniPlayer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = _currentAudioItem!;

    return GestureDetector(
      onTap: () => _showAudioPlayerModal(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
          border: Border(
            top: BorderSide(color: const Color(0xFF4E6AF3).withValues(alpha: 0.3), width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mini progress line
              LinearProgressIndicator(
                value: _audioDuration.inMilliseconds > 0
                    ? (_audioPosition.inMilliseconds / _audioDuration.inMilliseconds).clamp(0.0, 1.0)
                    : 0.0,
                minHeight: 2.5,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4E6AF3)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  // Animated Vinyl Disc
                  RotationTransition(
                    turns: _discRotationController,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.music_note_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${_formatDuration(_audioPosition)} / ${_formatDuration(_audioDuration)}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded),
                    onPressed: _playPreviousAudioTrack,
                  ),
                  IconButton(
                    icon: Icon(
                      _isAudioPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                      size: 36,
                      color: const Color(0xFF4E6AF3),
                    ),
                    onPressed: () {
                      if (_isAudioPlaying) {
                        _audioPlayer.pause();
                      } else {
                        _audioPlayer.resume();
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: _playNextAudioTrack,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () async {
                      await _audioPlayer.stop();
                      setState(() => _currentAudioItem = null);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAudioPlayerModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final item = _currentAudioItem;
          if (item == null) return const SizedBox.shrink();

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF181824) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                // Vinyl Disc / Artwork Display
                Expanded(
                  child: Center(
                    child: RotationTransition(
                      turns: _discRotationController,
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [
                              Color(0xFF2B2B36),
                              Color(0xFF111118),
                              Color(0xFF4E6AF3),
                            ],
                            stops: [0.0, 0.85, 1.0],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4E6AF3).withValues(alpha: 0.35),
                              blurRadius: 30,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.album_rounded, size: 90, color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  item.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _activeTab == StreamTabMode.connect
                      ? 'Live Streaming from ${_connectedDevice?.name ?? "Host"}'
                      : 'Local Audio Stream Host',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                // Scrubber Bar
                Slider(
                  value: _audioDuration.inMilliseconds > 0
                      ? _audioPosition.inMilliseconds.clamp(0, _audioDuration.inMilliseconds).toDouble()
                      : 0.0,
                  max: _audioDuration.inMilliseconds > 0 ? _audioDuration.inMilliseconds.toDouble() : 1.0,
                  activeColor: const Color(0xFF4E6AF3),
                  onChanged: (val) {
                    _audioPlayer.seek(Duration(milliseconds: val.toInt()));
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(_audioPosition), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(_formatDuration(_audioDuration), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Playback Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: Icon(
                        _isAudioLoop ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                        color: _isAudioLoop ? const Color(0xFF4E6AF3) : Colors.grey,
                      ),
                      onPressed: () {
                        setState(() => _isAudioLoop = !_isAudioLoop);
                        setModalState(() {});
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, size: 36),
                      onPressed: () {
                        _playPreviousAudioTrack();
                        setModalState(() {});
                      },
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)]),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          _isAudioPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 40,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          if (_isAudioPlaying) {
                            _audioPlayer.pause();
                          } else {
                            _audioPlayer.resume();
                          }
                          setModalState(() {});
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, size: 36),
                      onPressed: () {
                        _playNextAudioTrack();
                        setModalState(() {});
                      },
                    ),
                    IconButton(
                      icon: Icon(_audioVolume > 0 ? Icons.volume_up_rounded : Icons.volume_off_rounded),
                      onPressed: () {
                        final newVol = _audioVolume > 0 ? 0.0 : 1.0;
                        _audioPlayer.setVolume(newVol);
                        setState(() => _audioVolume = newVol);
                        setModalState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// --- VIDEO STREAM PLAYER FULLSCREEN MODAL ---

class VideoStreamPlayerModal extends StatefulWidget {
  final StreamMediaItem mediaItem;
  final String mediaUrl;
  final bool isLocal;

  const VideoStreamPlayerModal({
    super.key,
    required this.mediaItem,
    required this.mediaUrl,
    this.isLocal = false,
  });

  @override
  State<VideoStreamPlayerModal> createState() => _VideoStreamPlayerModalState();
}

class _VideoStreamPlayerModalState extends State<VideoStreamPlayerModal> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showControls = true;
  Timer? _hideControlsTimer;
  double _playbackSpeed = 1.0;
  final FocusNode _videoFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    try {
      if (widget.isLocal) {
        _controller = VideoPlayerController.file(File(widget.mediaUrl));
      } else {
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.mediaUrl));
      }

      await _controller.initialize();
      _controller.addListener(() {
        if (mounted) setState(() {});
      });
      _controller.play();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _resetControlsTimer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _videoFocusNode.dispose();
    _hideControlsTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _resetControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
      setState(() => _showControls = true);
    } else {
      _controller.play();
      _resetControlsTimer();
    }
  }

  void _seekRelative(int seconds) {
    final current = _controller.value.position;
    final target = current + Duration(seconds: seconds);
    _controller.seekTo(target);
    _resetControlsTimer();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.mediaPlayPause ||
          key == LogicalKeyboardKey.mediaPlay ||
          key == LogicalKeyboardKey.mediaPause) {
        _togglePlayPause();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.mediaRewind ||
          key == LogicalKeyboardKey.mediaTrackPrevious) {
        _seekRelative(-10);
        setState(() => _showControls = true);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.mediaFastForward ||
          key == LogicalKeyboardKey.mediaTrackNext) {
        _seekRelative(10);
        setState(() => _showControls = true);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        setState(() => _showControls = !_showControls);
        if (_showControls) _resetControlsTimer();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack) {
        Navigator.maybePop(context);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _videoFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: GestureDetector(
            onTap: () {
              setState(() => _showControls = !_showControls);
              if (_showControls) _resetControlsTimer();
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Video Surface
                Center(
                  child: _isInitialized
                      ? AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        )
                      : _hasError
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 50),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'Error streaming video format',
                                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _errorMessage,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                ],
                              ),
                            )
                          : const CircularProgressIndicator(color: Color(0xFF4E6AF3)),
                ),

                // Overlay Controls
                if (_showControls && _isInitialized)
                  Container(
                    color: Colors.black45,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top Bar
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.mediaItem.name,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              PopupMenuButton<double>(
                                icon: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('${_playbackSpeed}x', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                onSelected: (speed) {
                                  _controller.setPlaybackSpeed(speed);
                                  setState(() => _playbackSpeed = speed);
                                },
                                itemBuilder: (context) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((s) => PopupMenuItem(
                                  value: s,
                                  child: Text('${s}x'),
                                )).toList(),
                              ),
                            ],
                          ),
                        ),

                        // Center Play / Rewind / Fast-Forward
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 36),
                              onPressed: () => _seekRelative(-10),
                            ),
                            const SizedBox(width: 24),
                            Container(
                              decoration: const BoxDecoration(
                                color: Color(0xFF4E6AF3),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: Icon(
                                  _controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 42,
                                ),
                                onPressed: _togglePlayPause,
                              ),
                            ),
                            const SizedBox(width: 24),
                            IconButton(
                              icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 36),
                              onPressed: () => _seekRelative(10),
                            ),
                          ],
                        ),

                        // Bottom Scrubber Bar
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              VideoProgressIndicator(
                                _controller,
                                allowScrubbing: true,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                colors: const VideoProgressColors(
                                  playedColor: Color(0xFF4E6AF3),
                                  bufferedColor: Colors.white30,
                                  backgroundColor: Colors.white10,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(_controller.value.position),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  Text(
                                    _formatDuration(_controller.value.duration),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

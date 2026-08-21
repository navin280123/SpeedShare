import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:speedsharemob/FileSenderScreen.dart';
import 'package:speedsharemob/ReceiveScreen.dart';
import 'package:speedsharemob/SettingsScreen.dart';
import 'package:speedsharemob/SyncScreen.dart';
import 'package:speedsharemob/StreamScreen.dart';
import 'package:speedsharemob/DeviceNameManager.dart';
import 'package:speedsharemob/PermissionManager.dart';
import 'package:speedsharemob/SharedContentService.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  String computerName = '';
  final GlobalKey<FileSenderScreenState> _fileSenderKey =
      GlobalKey<FileSenderScreenState>();
  StreamSubscription<List<String>>? _sharedFilesSub;
  bool _isWindowDragging = false;

  final List<Map<String, dynamic>> _navigationOptions = [
    {'title': 'Home', 'icon': Icons.home_rounded},
    {'title': 'Send', 'icon': Icons.send_rounded},
    {'title': 'Receive', 'icon': Icons.download_rounded},
    {'title': 'Sync', 'icon': Icons.sync_rounded},
    {'title': 'Stream', 'icon': Icons.play_circle_fill_rounded},
    {'title': 'Settings', 'icon': Icons.settings_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _getComputerName();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PermissionManager().showPermissionRationaleDialog(context);
    });
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();

    // Check if initial files were passed
    final pending = SharedContentService().pendingFiles;
    if (pending.isNotEmpty) {
      _selectedIndex = 1;
    }

    // Listen for incoming files from system sharing or CLI or drops
    _sharedFilesSub = SharedContentService().onFilesReceived.listen((paths) {
      if (mounted && paths.isNotEmpty) {
        setState(() {
          _selectedIndex = 1; // Switch to Send Screen
        });
        _fileSenderKey.currentState?.loadFilesFromPaths(paths);
      }
    });
  }

  @override
  void dispose() {
    _sharedFilesSub?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _getComputerName() async {
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

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(
      index: _selectedIndex,
      children: [
        _buildHomeScreen(), // Index 0: Home Screen
        FileSenderScreen(key: _fileSenderKey), // Index 1: Send
        const ReceiveScreen(), // Index 2: Receive
        const SyncScreen(), // Index 3: Sync
        const StreamScreen(), // Index 4: Stream
        const SettingsScreen(), // Index 5: Settings
      ],
    );

    return DropTarget(
      onDragEntered: (detail) {
        setState(() {
          _isWindowDragging = true;
        });
      },
      onDragExited: (detail) {
        setState(() {
          _isWindowDragging = false;
        });
      },
      onDragDone: (detail) {
        setState(() {
          _isWindowDragging = false;
        });
        final paths = detail.files
            .map((f) => f.path)
            .where((p) => p.isNotEmpty)
            .toList();
        if (paths.isNotEmpty) {
          SharedContentService().emitFiles(paths);
          setState(() {
            _selectedIndex = 1;
          });
          _fileSenderKey.currentState?.loadFilesFromPaths(paths);
        }
      },
      child: Stack(
        children: [
          Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 600) {
                  // Desktop / Tablet layout
                  return Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: (index) {
                          setState(() {
                            _selectedIndex = index;
                          });
                        },
                        labelType: NavigationRailLabelType.all,
                        destinations:
                            _navigationOptions
                                .map(
                                  (option) => NavigationRailDestination(
                                    icon: Icon(option['icon']),
                                    label: Text(option['title']),
                                  ),
                                )
                                .toList(),
                        backgroundColor:
                            Theme.of(
                              context,
                            ).bottomNavigationBarTheme.backgroundColor,
                        selectedIconTheme: IconThemeData(
                          color:
                              Theme.of(
                                context,
                              ).bottomNavigationBarTheme.selectedItemColor,
                        ),
                        unselectedIconTheme: IconThemeData(
                          color:
                              Theme.of(
                                context,
                              ).bottomNavigationBarTheme.unselectedItemColor,
                        ),
                        selectedLabelTextStyle: TextStyle(
                          color:
                              Theme.of(
                                context,
                              ).bottomNavigationBarTheme.selectedItemColor,
                        ),
                        unselectedLabelTextStyle: TextStyle(
                          color:
                              Theme.of(
                                context,
                              ).bottomNavigationBarTheme.unselectedItemColor,
                        ),
                      ),
                      VerticalDivider(
                        thickness: 1,
                        width: 1,
                        color: Colors.grey.withValues(alpha: 0.2),
                      ),
                      Expanded(child: body),
                    ],
                  );
                } else {
                  // Mobile layout
                  return body;
                }
              },
            ),
            bottomNavigationBar:
                MediaQuery.of(context).size.width >= 600
                    ? const SizedBox.shrink() // Hide on desktop
                    : BottomNavigationBar(
                      currentIndex: _selectedIndex,
                      onTap: (index) {
                        setState(() {
                          _selectedIndex = index;
                        });
                      },
                      items:
                          _navigationOptions
                              .map(
                                (option) => BottomNavigationBarItem(
                                  icon: Icon(option['icon']),
                                  label: option['title'],
                                ),
                              )
                              .toList(),
                    ),
          ),
          if (_isWindowDragging) _buildDragAndDropOverlay(),
        ],
      ),
    );
  }

  Widget _buildDragAndDropOverlay() {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.65),
        child: Container(
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF4E6AF3).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF4E6AF3),
              width: 3,
              style: BorderStyle.solid,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4E6AF3),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4E6AF3).withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.file_upload_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Drop Files to Send with SpeedShare',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Release to immediately prepare files for transfer',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeScreen() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4E6AF3).withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'assets/icon.png',
                            width: 28,
                            height: 28,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShaderMask(
                              shaderCallback:
                                  (bounds) => const LinearGradient(
                                    colors: [
                                      Color(0xFF4E6AF3),
                                      Color(0xFF2AB673),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ).createShader(bounds),
                              child: const Text(
                                'SpeedShare',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            Text(
                              'Fast File Transfers',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color:
                                    Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Device info
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[800]
                                    : Colors.grey[200],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            computerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color:
                                  Theme.of(context).brightness == Brightness.dark
                                      ? Colors.white
                                      : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Main content
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Welcome Card
                          Card(
                            elevation: 3,
                            shadowColor: Colors.black.withValues(alpha: 0.3),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                children: [
                                  Lottie.asset(
                                    'assets/logo.json',
                                    height: 150,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.sync,
                                        size: 80,
                                        color: Theme.of(context).primaryColor,
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  ShaderMask(
                                    shaderCallback:
                                        (bounds) => const LinearGradient(
                                          colors: [
                                            Color(0xFF4E6AF3),
                                            Color(0xFF2AB673),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ).createShader(bounds),
                                    child: const Text(
                                      'Welcome to SpeedShare',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Share files between devices quickly and easily.\nNo internet required - just connect to the same network.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 14, height: 1.4),
                                  ),
                                  const SizedBox(height: 24),

                                  // Feature items
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _buildFeatureItem(
                                        Icons.wifi_off_rounded,
                                        'No Internet',
                                      ),
                                      _buildFeatureItem(
                                        Icons.speed_rounded,
                                        'Fast Transfers',
                                      ),
                                      _buildFeatureItem(
                                        Icons.security_rounded,
                                        'Secure',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Quick Actions
                          const Text(
                            'Quick Actions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          Row(
                            children: [
                              Expanded(
                                child: _buildActionCard(
                                  'Send Files',
                                  Icons.send_rounded,
                                  const Color(0xFF4E6AF3),
                                  'Transfer files to another device',
                                  () {
                                    setState(() {
                                      _selectedIndex = 1;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildActionCard(
                                  'Receive Files',
                                  Icons.download_rounded,
                                  const Color(0xFF2AB673),
                                  'Accept files from another device',
                                  () {
                                    setState(() {
                                      _selectedIndex = 2;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildActionCard(
                                  'Storage Sync',
                                  Icons.sync_rounded,
                                  const Color(0xFFF39C12),
                                  'Sync and explore files across devices',
                                  () {
                                    setState(() {
                                      _selectedIndex = 3;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildActionCard(
                                  'Media Stream',
                                  Icons.play_circle_fill_rounded,
                                  const Color(0xFF9B59B6),
                                  'Stream music & video with zero downloads',
                                  () {
                                    setState(() {
                                      _selectedIndex = 4;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
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

  Widget _buildFeatureItem(IconData icon, String text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF4E6AF3).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFF4E6AF3), size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color:
                Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[300]
                    : Colors.grey[700],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildActionCard(
    String title,
    IconData icon,
    Color color,
    String description,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[400]
                          : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.arrow_forward_rounded, color: color, size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

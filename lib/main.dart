import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:speedsharemob/MainScreen.dart';
import 'package:speedsharemob/PermissionManager.dart';
import 'package:speedsharemob/NotificationService.dart';
import 'package:speedsharemob/SharedContentService.dart';
import 'package:speedsharemob/BackgroundService.dart';

final ValueNotifier<bool> darkModeNotifier = ValueNotifier<bool>(false);

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  BackgroundService.initialize(); // Register foreground service notification channel
  await NotificationService().initialize();
  await SharedContentService().initialize(initialArgs: args);
  await PermissionManager().requestAppPermissions();
  // Load settings
  final prefs = await SharedPreferences.getInstance();
  final bool darkMode = prefs.getBool('darkMode') ?? false;
  darkModeNotifier.value = darkMode;

  // Bug 2: Clean up orphaned .speedshare_tmp files from any previous force-close
  await _cleanOrphanedTempFiles(prefs);

  runApp(const MyApp());
}

/// Deletes any leftover .speedshare_tmp partial-download files.
/// Called at startup so force-killed sessions never leave ghost files.
Future<void> _cleanOrphanedTempFiles(SharedPreferences prefs) async {
  try {
    final String? savedPath = prefs.getString('downloadPath');
    Directory dir;
    if (savedPath != null && savedPath.trim().isNotEmpty) {
      dir = Directory(savedPath.trim());
    } else if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download/speedshare');
    } else {
      final base = await getApplicationDocumentsDirectory();
      dir = Directory('${base.path}/speedshare');
    }
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.speedshare_tmp')) {
          try { await entity.delete(); } catch (_) {}
        }
      }
    }
  } catch (_) {}
}

class MyApp extends StatelessWidget {
  final bool? initialDarkMode;

  const MyApp({super.key, this.initialDarkMode});

  /// Convenience method to update dark mode instantly from anywhere (e.g., SettingsScreen)
  static void updateDarkMode(bool isDark) {
    darkModeNotifier.value = isDark;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: darkModeNotifier,
      builder: (context, isDarkMode, _) {
        return MaterialApp(
          title: 'SpeedShare',
          theme: ThemeData(
            brightness: Brightness.light,
            focusColor: const Color(0xFF4E6AF3).withValues(alpha: 0.25),
            hoverColor: const Color(0xFF4E6AF3).withValues(alpha: 0.12),
            highlightColor: const Color(0xFF4E6AF3).withValues(alpha: 0.18),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4E6AF3),
              primary: const Color(0xFF4E6AF3),
              secondary: const Color(0xFF2AB673),
              brightness: Brightness.light,
            ),
            fontFamily: 'Poppins',
            useMaterial3: true,
            cardTheme: CardThemeData(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                elevation: 2,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            navigationRailTheme: NavigationRailThemeData(
              indicatorColor: const Color(0xFF4E6AF3).withValues(alpha: 0.15),
              indicatorShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              selectedIconTheme: const IconThemeData(
                color: Color(0xFF4E6AF3),
                size: 26,
              ),
              selectedLabelTextStyle: const TextStyle(
                color: Color(0xFF4E6AF3),
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
              unselectedLabelTextStyle: TextStyle(
                color: Colors.grey[600],
                fontFamily: 'Poppins',
              ),
            ),
            scaffoldBackgroundColor: Colors.grey[50],
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              elevation: 0,
              centerTitle: false,
              titleTextStyle: TextStyle(
                color: Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
              iconTheme: IconThemeData(
                color: Colors.black87,
              ),
            ),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              backgroundColor: Colors.white,
              selectedItemColor: const Color(0xFF4E6AF3),
              unselectedItemColor: Colors.grey[600],
              elevation: 8,
              type: BottomNavigationBarType.fixed,
              showSelectedLabels: true,
              showUnselectedLabels: true,
            ),
          ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        focusColor: const Color(0xFF4E6AF3).withValues(alpha: 0.35),
        hoverColor: const Color(0xFF4E6AF3).withValues(alpha: 0.15),
        highlightColor: const Color(0xFF4E6AF3).withValues(alpha: 0.22),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4E6AF3),
          primary: const Color(0xFF4E6AF3),
          secondary: const Color(0xFF2AB673),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Poppins',
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        navigationRailTheme: NavigationRailThemeData(
          indicatorColor: const Color(0xFF4E6AF3).withValues(alpha: 0.25),
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          selectedIconTheme: const IconThemeData(
            color: Color(0xFF4E6AF3),
            size: 26,
          ),
          selectedLabelTextStyle: const TextStyle(
            color: Color(0xFF4E6AF3),
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
          unselectedLabelTextStyle: TextStyle(
            color: Colors.grey[400],
            fontFamily: 'Poppins',
          ),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: const Color(0xFF1E1E1E),
          selectedItemColor: const Color(0xFF4E6AF3),
          unselectedItemColor: Colors.grey[400],
          elevation: 8,
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: true,
          showUnselectedLabels: true,
        ),
      ),
          themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: const MainScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speedsharemob/StreamScreen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('StreamScreen renders dual mode switcher (Connect & Play, Stream / Host)', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'deviceName': 'Test Media Streamer',
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: StreamScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Title & Subtitle in AppBar
    expect(find.text('SpeedShare Stream'), findsOneWidget);

    // Verify Tab Switcher options
    expect(find.text('Connect & Play'), findsOneWidget);
    expect(find.text('Stream / Host'), findsOneWidget);

    // Default mode is Connect & Play -> Nearby Stream Hosts card visible
    expect(find.text('Nearby Stream Hosts'), findsOneWidget);

    // Switch to Stream / Host tab
    await tester.tap(find.text('Stream / Host'));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Host Server status card and Add buttons
    expect(find.text('Stream Server Offline'), findsOneWidget);
    expect(find.text('Start Streaming Live'), findsOneWidget);
    expect(find.text('Add Files'), findsOneWidget);
    expect(find.text('Add Folder'), findsOneWidget);

    // Switch back to Connect & Play tab
    await tester.tap(find.text('Connect & Play'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Nearby Stream Hosts'), findsOneWidget);

    // Flush discovery periodic timer
    await tester.pump(const Duration(seconds: 5));
  });
}

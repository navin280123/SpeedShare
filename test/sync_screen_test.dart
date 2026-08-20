import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speedsharemob/SyncScreen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SyncScreen renders dual mode switcher (Connect & Sync/Share)', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'deviceName': 'Test Phone',
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: SyncScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Title
    expect(find.text('Storage Sync'), findsOneWidget);

    // Verify Tab Switcher options
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Sync / Share'), findsOneWidget);

    // Default mode is Connect -> Browse Other Devices section visible
    expect(find.text('Browse Other Devices'), findsOneWidget);

    // Switch to Sync / Share tab
    await tester.tap(find.text('Sync / Share'));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Share This Device card & Connected Devices card are present
    expect(find.text('Share This Device'), findsOneWidget);
    expect(find.text('Connected Devices'), findsOneWidget);

    // Switch back to Connect tab
    await tester.tap(find.text('Connect'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Browse Other Devices'), findsOneWidget);

    // Flush discovery timer (2.5s)
    await tester.pump(const Duration(seconds: 3));
  });
}

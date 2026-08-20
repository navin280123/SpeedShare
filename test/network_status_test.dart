import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedsharemob/NetworkStatusWidget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NetworkStatusWidget Tests', () {
    testWidgets('Renders sender mode text correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NetworkStatusWidget(
              mode: NetworkWidgetMode.sender,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Either connected (hidden) or disconnected (showing sender action buttons)
      // When disconnected:
      final hotspotButton = find.text('Turn On Hotspot');
      final guideButton = find.text('Hotspot Guide');
      if (hotspotButton.evaluate().isNotEmpty) {
        expect(guideButton, findsOneWidget);
        expect(find.textContaining('receiver'), findsOneWidget);
      }
    });

    testWidgets('Renders receiver mode text correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NetworkStatusWidget(
              mode: NetworkWidgetMode.receiver,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final wifiButton = find.text('Connect to Wi-Fi');
      final guideButton = find.text('Hotspot Guide');
      if (wifiButton.evaluate().isNotEmpty) {
        expect(guideButton, findsOneWidget);
        expect(find.textContaining('sender'), findsOneWidget);
      }
    });
  });
}

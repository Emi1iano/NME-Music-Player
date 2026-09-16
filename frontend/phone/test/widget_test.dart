import 'package:flutter_test/flutter_test.dart';
import 'package:phone/main.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const NmeMusicApp());

    // Verify that the library screen title appears.
    expect(find.text('NME Library'), findsOneWidget);
  });
}
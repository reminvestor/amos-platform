// Basic Flutter widget test for AMOS Mobile App
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/main.dart';

void main() {
  testWidgets('App launches and shows login screen', (WidgetTester tester) async {
    // Build our app and trigger a frame
    await tester.pumpWidget(const ProviderScope(child: AmosApp()));
    await tester.pumpAndSettle();

    // Verify that the login screen is shown (app requires authentication)
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('App renders without errors', (WidgetTester tester) async {
    // Ensure the app can be built without throwing
    await tester.pumpWidget(const ProviderScope(child: AmosApp()));

    // Just pumping once is enough to verify initial render works
    await tester.pump();

    // No exception means success
    expect(tester.takeException(), isNull);
  });
}

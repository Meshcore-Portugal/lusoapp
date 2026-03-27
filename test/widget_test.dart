// This is a basic Flutter widget test.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcapppt/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: McAppPt()));
    // Just verify the app builds and renders without crashing.
    expect(find.byType(McAppPt), findsOneWidget);
  });
}

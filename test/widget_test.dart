import 'package:flutter_test/flutter_test.dart';
import 'package:packit_ai/main.dart';

void main() {
  testWidgets('PackIT opens animated splash screen with branding',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PackITApp());
    expect(find.text('PackIT AI'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('Tapping Get Started opens Home Dashboard',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PackITApp());
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.text('Ask our AI Packaging Expert...'), findsOneWidget);
    expect(find.text('Popular Products'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:deepfake_flutter_app/main.dart';

void main() {
  testWidgets('DeepGuard app renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DeepGuardApp());
    expect(find.text('DEEPGUARD'), findsOneWidget);
  });
}
import 'package:flutter_test/flutter_test.dart';
import 'package:necxa_flutter/main.dart';
import 'package:necxa_flutter/utils/error_handler.dart';

void main() {
  testWidgets('NecxaApp builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const NecxaApp());
    expect(find.byType(NecxaApp), findsOneWidget);
    await tester.pumpAndSettle();
  });

  test('live stream errors are translated into clear messages', () {
    expect(getUserFriendlyError('Permission denied'), contains('Camera or microphone access'));
    expect(getUserFriendlyError('token expired'), contains('Live streaming authentication failed'));
    expect(getUserFriendlyError('joinChannel failed'), contains('Unable to connect to the live channel'));
  });
}

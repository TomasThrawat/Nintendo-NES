import 'package:flutter_test/flutter_test.dart';
import 'package:nintendo_nes/main.dart';

void main() {
  testWidgets('receiver launches directly into the Wi-Fi receiver screen', (tester) async {
    await tester.pumpWidget(const GamepadReceiverApp());
    expect(find.text('NES-Style Gamepad Receiver'), findsOneWidget);
    expect(find.text('Start gamepad receiver'), findsOneWidget);
    expect(find.text('Import ROM'), findsNothing);
    expect(find.text('Open gamepad receiver'), findsNothing);
    expect(find.text('Pairing code'), findsNothing);
  });

  testWidgets('receiver screen starts stopped and does not bind until Start is pressed', (tester) async {
    await tester.pumpWidget(const NintendoNesApp());
    expect(find.text('Start NES receiver'), findsOneWidget);
    expect(find.text('RECEIVER STATUS'), findsOneWidget);
    expect(find.text('Receiver IP address'), findsNothing);
    expect(find.textContaining('Shizuku'), findsOneWidget);
  });
}

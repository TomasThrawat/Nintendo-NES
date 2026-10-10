import 'package:flutter_test/flutter_test.dart';
import 'package:nintendo_nes/main.dart';

void main() {
  testWidgets('receiver launches directly into the Wi-Fi receiver screen', (tester) async {
    await tester.pumpWidget(const NintendoNesApp());
    expect(find.text('Nintendo NES Receiver'), findsOneWidget);
    expect(find.text('Start NES receiver'), findsOneWidget);
    expect(find.text('Import .nes ROM'), findsOneWidget);
    expect(find.text('Open NES receiver'), findsNothing);
    expect(find.text('Pairing code'), findsNothing);
  });

  testWidgets('receiver screen starts stopped and does not bind until Start is pressed', (tester) async {
    await tester.pumpWidget(const NintendoNesApp());
    expect(find.text('Start NES receiver'), findsOneWidget);
    expect(find.text('RECEIVER STATUS'), findsOneWidget);
    expect(find.text('Receiver IP address'), findsNothing);
  });
}

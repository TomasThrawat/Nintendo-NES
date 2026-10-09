import 'package:flutter_test/flutter_test.dart';
import 'package:nintendo_nes/controller_main.dart';

void main() {
  testWidgets('controller app exposes only NES Wi-Fi controls', (tester) async {
    await tester.pumpWidget(const NesWifiControllerApp());
    expect(find.text('NES Wi-Fi Controller'), findsOneWidget);
    expect(find.text('Receiver IPv4 address'), findsOneWidget);
    expect(find.text('16-character pairing code'), findsOneWidget);
    expect(find.text('Start NES receiver'), findsNothing);
    expect(find.text('Xbox 360 Controller'), findsNothing);
  });
}

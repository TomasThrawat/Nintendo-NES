import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nintendo_nes/controller_main.dart';

void main() {
  testWidgets('controller app exposes only NES Wi-Fi controls', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const NesWifiControllerApp());
    expect(find.text('NES Wi-Fi Controller'), findsOneWidget);
    expect(find.text('Receiver IPv4 address'), findsOneWidget);
    expect(find.text('16-character pairing code'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Start NES receiver'), findsNothing);
    expect(find.text('Xbox 360 Controller'), findsNothing);
  });
}

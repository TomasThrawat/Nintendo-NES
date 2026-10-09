import 'package:flutter_test/flutter_test.dart';
import 'package:nintendo_nes/main.dart';

void main() {
  testWidgets('renders the NES receiver home screen', (tester) async {
    await tester.pumpWidget(const NintendoNesApp());
    expect(find.text('Nintendo NES / Famicom'), findsOneWidget);
    expect(find.text('Wi-Fi receiver'), findsOneWidget);
    expect(find.text('Import .nes ROM'), findsOneWidget);
    expect(find.text('Open NES receiver'), findsOneWidget);
    expect(find.text('Use this device as controller'), findsNothing);
  });

  testWidgets('receiver screen starts in stopped state', (tester) async {
    await tester.pumpWidget(const NintendoNesApp());
    await tester.tap(find.text('Open NES receiver'));
    await tester.pumpAndSettle();
    expect(find.text('NES Receiver'), findsOneWidget);
    expect(find.text('Start NES receiver'), findsOneWidget);
    expect(find.text('RECEIVER STATUS'), findsOneWidget);
  });
}

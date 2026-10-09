import 'package:flutter_test/flutter_test.dart';
import 'package:nintendo_nes/main.dart';

void main() {
  testWidgets('renders the NES home screen and Wi-Fi controller entry', (tester) async {
    await tester.pumpWidget(const NintendoNesApp());
    expect(find.text('Nintendo NES / Famicom'), findsOneWidget);
    expect(find.text('Local Wi-Fi controller'), findsOneWidget);
    expect(find.text('Import .nes ROM'), findsOneWidget);
  });
}

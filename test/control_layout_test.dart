import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nintendo_nes/core/controller/nes_controller.dart';
import 'package:nintendo_nes/services/control_layout.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('provides individual editable defaults for every NES button', () async {
    final placements = await ControlLayoutStore.load();
    expect(placements.keys.toSet(), NesButton.values.toSet());
    expect(placements.values.every((p) => p.visible), isTrue);
    expect(placements.values.every((p) => p.scale == 1), isTrue);
  });

  test('persists each button position, size, and visibility', () async {
    const placement = ControlPlacement(
      x: 0.31,
      y: 0.68,
      scale: 1.4,
      visible: false,
    );
    await ControlLayoutStore.save(NesButton.a, placement);
    final restored = (await ControlLayoutStore.load())[NesButton.a]!;
    expect(restored.x, closeTo(0.31, 0.001));
    expect(restored.y, closeTo(0.68, 0.001));
    expect(restored.scale, closeTo(1.4, 0.001));
    expect(restored.visible, isFalse);
  });

  test('reset restores defaults', () async {
    await ControlLayoutStore.save(
      NesButton.start,
      const ControlPlacement(x: 0.9, y: 0.2, scale: 1.5),
    );
    await ControlLayoutStore.reset();
    final restored = (await ControlLayoutStore.load())[NesButton.start]!;
    expect(restored.x, ControlLayoutStore.defaults[NesButton.start]!.x);
    expect(restored.y, ControlLayoutStore.defaults[NesButton.start]!.y);
    expect(restored.scale, 1);
    expect(restored.visible, isTrue);
  });
}

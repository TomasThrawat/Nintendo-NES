import 'package:flutter_test/flutter_test.dart';
import 'package:nintendo_nes/core/controller/gamepad_state.dart';

void main() {
  test('maps all eight NES-style controls to stable gamepad bits', () {
    expect(GamepadState.maskFor(const {GamepadButton.a}), 1);
    expect(GamepadState.maskFor(const {GamepadButton.b}), 2);
    expect(GamepadState.maskFor(const {GamepadButton.select}), 4);
    expect(GamepadState.maskFor(const {GamepadButton.start}), 8);
    expect(GamepadState.maskFor(const {GamepadButton.up}), 16);
    expect(GamepadState.maskFor(const {GamepadButton.down}), 32);
    expect(GamepadState.maskFor(const {GamepadButton.left}), 64);
    expect(GamepadState.maskFor(const {GamepadButton.right}), 128);
  });

  test('round-trips simultaneous input states', () {
    const buttons = {GamepadButton.a, GamepadButton.start, GamepadButton.up, GamepadButton.right};
    expect(GamepadState.buttonsFromMask(GamepadState.maskFor(buttons)), buttons);
    expect(GamepadState.buttonsFromMask(0), isEmpty);
  });
}

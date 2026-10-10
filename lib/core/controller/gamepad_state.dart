enum GamepadButton { a, b, select, start, up, down, left, right }

/// Converts NES-style touch controls into standard gamepad input bits.
class GamepadState {
  const GamepadState._();

  static int maskFor(Iterable<GamepadButton> buttons) {
    var result = 0;
    for (final button in buttons) {
      result |= 1 << button.index;
    }
    return result & 0xff;
  }

  static Set<GamepadButton> buttonsFromMask(int mask) => <GamepadButton>{
        for (final button in GamepadButton.values)
          if ((mask & (1 << button.index)) != 0) button,
      };
}

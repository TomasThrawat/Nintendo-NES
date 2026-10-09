enum NesButton { a, b, select, start, up, down, left, right }

/// Serial controller-port protocol; bit order is A, B, Select, Start, Up,
/// Down, Left, Right. The same state can be updated by local or Wi-Fi input.
class NesController {
  final Set<NesButton> _pressed = <NesButton>{};
  int _shift = 0;
  bool _strobe = false;

  Set<NesButton> get pressed => Set<NesButton>.unmodifiable(_pressed);
  int get pressedMask => maskFor(_pressed);

  void setButtons(Iterable<NesButton> buttons) {
    _pressed..clear()..addAll(buttons);
    if (_strobe) _shift = pressedMask;
  }

  void setButton(NesButton button, bool down) {
    if (down) {
      _pressed.add(button);
    } else {
      _pressed.remove(button);
    }
    if (_strobe) _shift = pressedMask;
  }

  void writeStrobe(int value) {
    final next = (value & 1) != 0;
    if (next || (_strobe && !next)) _shift = pressedMask;
    _strobe = next;
  }

  int readSerial() {
    if (_strobe) return 0x40 | (pressedMask & 1);
    final bit = _shift & 1;
    _shift = ((_shift >> 1) | 0x80) & 0xff;
    return 0x40 | bit;
  }

  static int maskFor(Iterable<NesButton> buttons) {
    var result = 0;
    for (final button in buttons) {
      result |= 1 << button.index;
    }
    return result & 0xff;
  }

  static Set<NesButton> buttonsFromMask(int mask) => <NesButton>{
    for (final button in NesButton.values)
      if ((mask & (1 << button.index)) != 0) button,
  };
}

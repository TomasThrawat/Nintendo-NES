import 'package:flutter/services.dart';

import '../core/controller/gamepad_state.dart';

class SystemGamepadBridge {
  SystemGamepadBridge._();
  static const MethodChannel _channel = MethodChannel('com.tomastharwat.nintendo_nes/gamepad');

  static Future<void> start() async {
    final started = await _channel.invokeMethod<bool>('startGamepad');
    if (started != true) throw StateError('The TV did not register a virtual gamepad.');
  }

  static Future<void> setButtons(Iterable<GamepadButton> buttons) async {
    await _channel.invokeMethod<void>(
      'setButtons',
      <String, Object>{'mask': GamepadState.maskFor(buttons)},
    );
  }

  static Future<void> stop() async {
    await _channel.invokeMethod<void>('stopGamepad');
  }
}

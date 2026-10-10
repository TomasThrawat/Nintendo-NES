import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nintendo_nes/core/controller/gamepad_state.dart';
import 'package:nintendo_nes/services/gamepad_protocol.dart';
import 'package:nintendo_nes/services/local_controller_client.dart';
import 'package:nintendo_nes/services/local_controller_server.dart';

void main() {
  test('encodes and validates the eight-byte input and acknowledgement packets', () {
    final input = encodeGamepadInputPacket(sequence: 42, mask: 0x81);
    expect(input.length, gamepadPacketSize);
    expect(isGamepadInputPacket(input), isTrue);
    expect(isValidGamepadPacket(input), isTrue);
    expect(readGamepadSequence(input), 42);
    expect(readGamepadMask(input), 0x81);

    final ack = encodeGamepadAckPacket(sequence: 42);
    expect(isGamepadAckPacket(ack), isTrue);
    expect(isValidGamepadPacket(ack), isTrue);
    expect(readGamepadSequence(ack), 42);

    final badMagic = List<int>.of(input)..[0] = 0;
    final badType = List<int>.of(input)..[2] = 9;
    expect(isValidGamepadPacket(badMagic), isFalse);
    expect(isValidGamepadPacket(badType), isFalse);
    expect(isValidGamepadPacket(input.take(7).toList()), isFalse);
    expect(() => encodeGamepadInputPacket(sequence: -1, mask: 0), throwsFormatException);
    expect(() => encodeGamepadInputPacket(sequence: 0x100000000, mask: 0), throwsFormatException);
    expect(() => encodeGamepadInputPacket(sequence: 1, mask: 256), throwsFormatException);
  });

  test('rejects duplicate and stale sequence values while allowing uint32 wraparound', () {
    expect(isNewerGamepadSequence(1, -1), isTrue);
    expect(isNewerGamepadSequence(2, 1), isTrue);
    expect(isNewerGamepadSequence(1, 1), isFalse);
    expect(isNewerGamepadSequence(1, 2), isFalse);
    expect(isNewerGamepadSequence(0, 0xffffffff), isTrue);
  });

  test('maps simultaneous NES-style buttons to stable gamepad bits', () {
    const buttons = {
      GamepadButton.a,
      GamepadButton.start,
      GamepadButton.up,
      GamepadButton.right,
    };
    expect(GamepadState.maskFor(buttons), 0x99);
    expect(GamepadState.buttonsFromMask(0x99), buttons);
    expect(GamepadState.buttonsFromMask(0), isEmpty);
  });

  test('UDP loopback transmits simultaneous buttons and releases on disconnect', () async {
    final inputReceived = Completer<void>();
    final released = Completer<void>();
    final disconnected = Completer<void>();
    final observed = <Set<GamepadButton>>[];
    final host = LocalControllerServer(
      port: 0,
      systemGamepadEnabled: false,
      onButtonsChanged: (buttons) {
        observed.add(Set<GamepadButton>.of(buttons));
        if (buttons.contains(GamepadButton.a) &&
            buttons.contains(GamepadButton.right) &&
            !inputReceived.isCompleted) {
          inputReceived.complete();
        }
        if (buttons.isEmpty && inputReceived.isCompleted && !released.isCompleted) {
          released.complete();
        }
      },
      onStatusChanged: (status) {
        if (status == 'Controller disconnected' && !disconnected.isCompleted) {
          disconnected.complete();
        }
      },
    );
    final client = LocalControllerClient();

    try {
      await host.start();
      await client.connect(
        host: '127.0.0.1',
        port: host.boundPort,
        onButtonsChanged: (_) {},
        onStatusChanged: (_) {},
      );
      expect(client.isConnected, isTrue);
      client.setButtons(const {GamepadButton.a, GamepadButton.right});
      await inputReceived.future.timeout(const Duration(seconds: 3));
      expect(host.isConnected, isTrue);
      expect(observed.last, containsAll(const {GamepadButton.a, GamepadButton.right}));

      // Exercise each D-pad direction through the actual UDP client/server protocol.
      for (final direction in const <GamepadButton>[
        GamepadButton.up,
        GamepadButton.down,
        GamepadButton.left,
        GamepadButton.right,
      ]) {
        final previousCount = observed.length;
        client.setButtons({direction});
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (observed.length <= previousCount && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(observed.length, greaterThan(previousCount),
            reason: 'Receiver did not forward $direction');
        expect(observed.last, {direction});
      }

      await client.disconnect();
      await released.future.timeout(const Duration(seconds: 3));
      await disconnected.future.timeout(const Duration(seconds: 3));
      expect(host.isConnected, isFalse);
      expect(observed.last, isEmpty);
    } finally {
      await client.disconnect();
      await host.stop();
    }
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nintendo_nes/core/controller/nes_controller.dart';
import 'package:nintendo_nes/services/local_controller_client.dart';
import 'package:nintendo_nes/services/local_controller_server.dart';
import 'package:nintendo_nes/services/remote_protocol.dart';

void main() {
  test('encodes fixed-size IP-only NES UDP input and acknowledgement packets', () {
    final input = encodeNesInputPacket(sequence: 42, mask: 0x81);
    expect(input.length, nesDatagramSize);
    expect(isNesInputPacket(input), isTrue);
    expect(isValidNesDatagram(input), isTrue);
    expect(readNesSequence(input), 42);
    expect(readNesButtonMask(input), 0x81);

    final ack = encodeNesAckPacket(sequence: 42);
    expect(isNesAckPacket(ack), isTrue);
    expect(isValidNesDatagram(ack), isTrue);
    expect(readNesSequence(ack), 42);

    final malformed = List<int>.of(input)..[0] = 0;
    expect(isValidNesDatagram(malformed), isFalse);
    expect(isValidNesDatagram(input.take(7).toList()), isFalse);
    expect(() => encodeNesInputPacket(sequence: 42, mask: 256), throwsFormatException);
  });

  test('rejects duplicate/stale sequence values and allows uint32 wraparound', () {
    expect(isNewerNesSequence(1, -1), isTrue);
    expect(isNewerNesSequence(2, 1), isTrue);
    expect(isNewerNesSequence(1, 1), isFalse);
    expect(isNewerNesSequence(1, 2), isFalse);
    expect(isNewerNesSequence(0, 0xffffffff), isTrue);
    expect(() => parseButtonMask(256), throwsFormatException);
    expect(() => parseButtonMask(-1), throwsFormatException);
    expect(() => parseSequence(-1), throwsFormatException);
    expect(() => parseSequence(0x100000000), throwsFormatException);
  });

  test('IP-only UDP receiver and controller exchange simultaneous NES input and release on disconnect', () async {
    final inputReceived = Completer<void>();
    final released = Completer<void>();
    final disconnected = Completer<void>();
    final seen = <Set<NesButton>>[];
    final counts = <int>[];
    final host = LocalControllerServer(
      port: 0,
      onButtonsChanged: (buttons) {
        seen.add(Set<NesButton>.of(buttons));
        if (buttons.contains(NesButton.a) &&
            buttons.contains(NesButton.right) &&
            !inputReceived.isCompleted) {
          inputReceived.complete();
        }
        if (buttons.isEmpty &&
            inputReceived.isCompleted &&
            !released.isCompleted) {
          released.complete();
        }
      },
      onStatusChanged: (status) {
        if (status == 'Controller disconnected' && !disconnected.isCompleted) {
          disconnected.complete();
        }
      },
      onInputCountChanged: counts.add,
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
      client.setButtons(const {NesButton.a, NesButton.right});
      await inputReceived.future.timeout(const Duration(seconds: 3));
      expect(host.isConnected, isTrue);
      expect(seen.last, containsAll(const {NesButton.a, NesButton.right}));
      expect(host.inputsReceived, greaterThan(0));
      expect(counts.last, host.inputsReceived);

      await client.disconnect();
      await released.future.timeout(const Duration(seconds: 3));
      await disconnected.future.timeout(const Duration(seconds: 3));
      expect(host.isConnected, isFalse);
      expect(seen.last, isEmpty);
    } finally {
      await client.disconnect();
      await host.stop();
    }
  });
}

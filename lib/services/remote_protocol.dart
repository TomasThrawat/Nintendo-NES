import 'dart:typed_data';

import '../core/controller/nes_controller.dart';

const int nesWifiPort = 27191;
const int nesDatagramMagic = 0x4e; // 'N'
const int nesDatagramVersion = 2;
const int nesDatagramSize = 8;
const int _inputKind = 0;
const int _ackKind = 1;

/// Encodes a fixed-size NES button frame. Like WiFiPad, this is intentionally
/// IP-only and unauthenticated: use it only on a trusted local Wi-Fi network.
Uint8List encodeNesInputPacket({
  required int sequence,
  required int mask,
}) =>
    _encodePacket(kind: _inputKind, sequence: sequence, value: mask);

Uint8List encodeNesAckPacket({required int sequence}) =>
    _encodePacket(kind: _ackKind, sequence: sequence, value: 1);

Uint8List _encodePacket({
  required int kind,
  required int sequence,
  required int value,
}) {
  if (sequence < 0 || sequence > 0xffffffff) {
    throw const FormatException('Input sequence is outside uint32 range.');
  }
  if (value < 0 || value > 0xff) {
    throw const FormatException('NES input value is outside byte range.');
  }
  final packet = Uint8List(nesDatagramSize);
  packet[0] = nesDatagramMagic;
  packet[1] = nesDatagramVersion;
  packet[2] = kind;
  packet[3] = sequence & 0xff;
  packet[4] = (sequence >> 8) & 0xff;
  packet[5] = (sequence >> 16) & 0xff;
  packet[6] = (sequence >> 24) & 0xff;
  packet[7] = value;
  return packet;
}

/// Validates packet structure. This cannot authenticate a sender because the
/// IP-only compatibility protocol intentionally has no shared secret.
bool isValidNesDatagram(List<int> packet) =>
    packet.length == nesDatagramSize &&
    packet[0] == nesDatagramMagic &&
    packet[1] == nesDatagramVersion &&
    (packet[2] == _inputKind || packet[2] == _ackKind) &&
    (packet[2] != _ackKind || packet[7] == 1);

bool isNesInputPacket(List<int> packet) =>
    isValidNesDatagram(packet) && packet[2] == _inputKind;

bool isNesAckPacket(List<int> packet) =>
    isValidNesDatagram(packet) && packet[2] == _ackKind;

int readNesSequence(List<int> packet) =>
    packet[3] | (packet[4] << 8) | (packet[5] << 16) | (packet[6] << 24);

int readNesButtonMask(List<int> packet) => packet[7];

/// RFC-1982-style uint32 sequence comparison; permits wraparound while
/// rejecting duplicates and packets that are older than half the sequence space.
bool isNewerNesSequence(int incoming, int previous) {
  if (previous < 0) {
    return true;
  }
  final difference = (incoming - previous) & 0xffffffff;
  return difference != 0 && difference < 0x80000000;
}

int parseButtonMask(Object? value) {
  if (value is! int || value < 0 || value > 255) {
    throw const FormatException('Invalid NES input mask.');
  }
  return value;
}

int parseSequence(Object? value) {
  if (value is! int || value < 0 || value > 0xffffffff) {
    throw const FormatException('Invalid NES input sequence.');
  }
  return value;
}

Set<NesButton> remoteButtonsFromMask(Object? mask) =>
    NesController.buttonsFromMask(parseButtonMask(mask));

import 'dart:typed_data';

const int gamepadWifiPort = 27191;
const int gamepadPacketMagic = 0x4e; // 'N'
const int gamepadPacketVersion = 2;
const int gamepadPacketSize = 8;
const int _inputType = 0;
const int _ackType = 1;

Uint8List encodeGamepadInputPacket({required int sequence, required int mask}) =>
    _encodePacket(kind: _inputType, sequence: sequence, value: mask);

Uint8List encodeGamepadAckPacket({required int sequence}) =>
    _encodePacket(kind: _ackType, sequence: sequence, value: 1);

Uint8List _encodePacket({required int kind, required int sequence, required int value}) {
  if (sequence < 0 || sequence > 0xffffffff) {
    throw const FormatException('Gamepad sequence is outside uint32 range.');
  }
  if (value < 0 || value > 0xff) {
    throw const FormatException('Gamepad input is outside byte range.');
  }
  final packet = Uint8List(gamepadPacketSize);
  packet[0] = gamepadPacketMagic;
  packet[1] = gamepadPacketVersion;
  packet[2] = kind;
  packet[3] = sequence & 0xff;
  packet[4] = (sequence >> 8) & 0xff;
  packet[5] = (sequence >> 16) & 0xff;
  packet[6] = (sequence >> 24) & 0xff;
  packet[7] = value;
  return packet;
}

bool isValidGamepadPacket(List<int> packet) =>
    packet.length == gamepadPacketSize &&
    packet[0] == gamepadPacketMagic &&
    packet[1] == gamepadPacketVersion &&
    (packet[2] == _inputType || packet[2] == _ackType) &&
    (packet[2] != _ackType || packet[7] == 1);

bool isGamepadInputPacket(List<int> packet) =>
    isValidGamepadPacket(packet) && packet[2] == _inputType;

bool isGamepadAckPacket(List<int> packet) =>
    isValidGamepadPacket(packet) && packet[2] == _ackType;

int readGamepadSequence(List<int> packet) =>
    packet[3] | (packet[4] << 8) | (packet[5] << 16) | (packet[6] << 24);

int readGamepadMask(List<int> packet) => packet[7];

bool isNewerGamepadSequence(int incoming, int previous) {
  if (previous < 0) return true;
  final difference = (incoming - previous) & 0xffffffff;
  return difference != 0 && difference < 0x80000000;
}

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/controller/nes_controller.dart';

const int nesWifiPort = 27191;
const int nesDatagramMagic = 0x4e; // 'N'
const int nesDatagramVersion = 1;
const int nesDatagramSize = 24;
const int _macSize = 16;
const int _inputKind = 0;
const int _ackKind = 1;
const String _alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

String newPairingCode() {
  final random = Random.secure();
  return List<String>.generate(
    16,
    (_) => _alphabet[random.nextInt(_alphabet.length)],
  ).join();
}

String normalizedPairingCode(String value) => value.trim().toUpperCase();

bool isPairingCode(String value) =>
    value.length == 16 && value.split('').every(_alphabet.contains);

bool constantTimeBytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  var difference = 0;
  for (var i = 0; i < left.length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}

/// Encodes an authenticated UDP input frame. The datagram has a fixed size:
/// magic, version, type, 32-bit sequence, 8-bit NES mask, and a truncated
/// HMAC-SHA-256. No peer-controlled lengths are parsed.
Uint8List encodeNesInputPacket({
  required int sequence,
  required int mask,
  required String pairingCode,
}) {
  if (sequence < 0 || sequence > 0xffffffff) {
    throw const FormatException('Input sequence is outside uint32 range.');
  }
  if (mask < 0 || mask > 0xff) {
    throw const FormatException('Input mask is outside byte range.');
  }
  return _encodePacket(
    kind: _inputKind,
    sequence: sequence,
    value: mask,
    pairingCode: pairingCode,
  );
}

/// Encodes a signed receiver acknowledgement for the latest accepted frame.
Uint8List encodeNesAckPacket({
  required int sequence,
  required String pairingCode,
}) =>
    _encodePacket(
      kind: _ackKind,
      sequence: sequence,
      value: 1,
      pairingCode: pairingCode,
    );

Uint8List _encodePacket({
  required int kind,
  required int sequence,
  required int value,
  required String pairingCode,
}) {
  final code = normalizedPairingCode(pairingCode);
  if (!isPairingCode(code)) {
    throw const FormatException('Invalid pairing code.');
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
  final digest = Hmac(
    sha256,
    utf8.encode(code),
  ).convert(packet.sublist(0, 8)).bytes;
  packet.setRange(8, nesDatagramSize, digest.take(_macSize));
  return packet;
}

bool isValidNesDatagram(List<int> packet, String pairingCode) {
  if (packet.length != nesDatagramSize ||
      packet[0] != nesDatagramMagic ||
      packet[1] != nesDatagramVersion ||
      (packet[2] != _inputKind && packet[2] != _ackKind)) {
    return false;
  }
  final code = normalizedPairingCode(pairingCode);
  if (!isPairingCode(code)) {
    return false;
  }
  final digest = Hmac(
    sha256,
    utf8.encode(code),
  ).convert(packet.sublist(0, 8)).bytes;
  return constantTimeBytesEqual(
    packet.sublist(8),
    digest.take(_macSize).toList(growable: false),
  );
}

bool isNesInputPacket(List<int> packet) =>
    packet.length == nesDatagramSize && packet[2] == _inputKind;

bool isNesAckPacket(List<int> packet) =>
    packet.length == nesDatagramSize &&
    packet[2] == _ackKind &&
    packet[7] == 1;

int readNesSequence(List<int> packet) =>
    packet[3] |
    (packet[4] << 8) |
    (packet[5] << 16) |
    (packet[6] << 24);

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

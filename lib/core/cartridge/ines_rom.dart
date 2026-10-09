import 'dart:typed_data';

class RomFormatException implements Exception {
  const RomFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Header parser for iNES and NES 2.0 files; mapper execution is separate.
class NesRom {
  NesRom._({
    required this.isNes2,
    required this.mapper,
    required this.submapper,
    required this.prgRom,
    required this.chrRom,
    required this.hasTrainer,
    required this.hasBattery,
    required this.mirroring,
    required this.prgRamBytes,
  });

  static const headerSize = 16;
  static const trainerSize = 512;
  static const maxSectionBytes = 64 * 1024 * 1024;

  final bool isNes2;
  final int mapper;
  final int submapper;
  final Uint8List prgRom;
  final Uint8List chrRom;
  final bool hasTrainer;
  final bool hasBattery;
  final String mirroring;
  final int prgRamBytes;
  bool get hasChrRam => chrRom.isEmpty;

  static NesRom parse(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw const RomFormatException('The file is shorter than an iNES header.');
    }
    if (bytes[0] != 0x4e || bytes[1] != 0x45 ||
        bytes[2] != 0x53 || bytes[3] != 0x1a) {
      throw const RomFormatException('Invalid ROM signature. Select a valid .nes file.');
    }
    final flags6 = bytes[6];
    final flags7 = bytes[7];
    final nes2 = (flags7 & 0x0c) == 0x08;
    final trainer = (flags6 & 0x04) != 0;
    final mapper = ((flags6 >> 4) & 0x0f) | (flags7 & 0xf0) |
        (nes2 ? ((bytes[8] & 0x0f) << 8) : 0);
    final submapper = nes2 ? bytes[8] >> 4 : 0;
    final prgSize = _romSize(bytes[4], nes2 ? bytes[9] & 0x0f : 0, 16384, nes2);
    final chrSize = _romSize(bytes[5], nes2 ? (bytes[9] >> 4) & 0x0f : 0, 8192, nes2);
    if (prgSize <= 0) {
      throw const RomFormatException('The ROM declares no PRG program data.');
    }
    if (prgSize > maxSectionBytes || chrSize > maxSectionBytes) {
      throw const RomFormatException('The ROM declares an unsupported or excessively large section.');
    }
    final start = headerSize + (trainer ? trainerSize : 0);
    final endPrg = start + prgSize;
    final endChr = endPrg + chrSize;
    if (endChr > bytes.length) {
      throw RomFormatException('The ROM is truncated: expected at least $endChr bytes, got ${bytes.length}.');
    }
    final mirroring = (flags6 & 0x08) != 0
        ? 'Four-screen'
        : (flags6 & 1) != 0 ? 'Vertical' : 'Horizontal';
    final ram = nes2
        ? _ramBytes(bytes[10] & 15)
        : (bytes[8] == 0 ? 8192 : bytes[8] * 8192);
    return NesRom._(
      isNes2: nes2,
      mapper: mapper,
      submapper: submapper,
      prgRom: Uint8List.fromList(bytes.sublist(start, endPrg)),
      chrRom: Uint8List.fromList(bytes.sublist(endPrg, endChr)),
      hasTrainer: trainer,
      hasBattery: (flags6 & 2) != 0,
      mirroring: mirroring,
      prgRamBytes: ram,
    );
  }

  static int _romSize(int lsb, int msb, int unit, bool nes2) {
    if (!nes2) return lsb * unit;
    if (msb != 15) return ((msb << 8) | lsb) * unit;
    final exponent = lsb >> 2;
    if (exponent > 26) return maxSectionBytes + 1;
    return (1 << exponent) * (2 * (lsb & 3) + 1);
  }

  static int _ramBytes(int shift) {
    if (shift == 0) return 0;
    if (shift > 20) return maxSectionBytes + 1;
    return 64 << shift;
  }
}

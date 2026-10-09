import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nintendo_nes/core/cartridge/ines_rom.dart';

Uint8List romBytes({int prg=1,int chr=1,int flags7=0}) {
  final bytes=Uint8List(16+prg*16384+chr*8192);
  bytes.setRange(0,4,<int>[0x4e,0x45,0x53,0x1a]);
  bytes[4]=prg; bytes[5]=chr; bytes[7]=flags7;
  return bytes;
}
void main() {
  test('parses iNES NROM image', () {
    final rom=NesRom.parse(romBytes());
    expect(rom.isNes2,isFalse); expect(rom.mapper,0);
    expect(rom.prgRom.length,16384); expect(rom.chrRom.length,8192);
    expect(rom.mirroring,'Horizontal');
  });
  test('recognizes NES 2.0',()=>expect(NesRom.parse(romBytes(flags7:8)).isNes2,isTrue));
  test('rejects short header, invalid signature and truncated image', () {
    expect(()=>NesRom.parse(Uint8List(15)),throwsA(isA<RomFormatException>()));
    expect(()=>NesRom.parse(Uint8List(16)),throwsA(isA<RomFormatException>()));
    expect(()=>NesRom.parse(romBytes().sublist(0,100)),throwsA(isA<RomFormatException>()));
  });
  test('accounts for the optional trainer before PRG', () {
    final base=romBytes(); base[6]=4;
    final bytes=Uint8List(base.length+512)..setRange(0,16,base)..setRange(528,base.length+512,base.sublist(16));
    final parsed=NesRom.parse(bytes);
    expect(parsed.hasTrainer,isTrue); expect(parsed.prgRom.length,16384);
  });
}

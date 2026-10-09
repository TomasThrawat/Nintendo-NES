import 'dart:typed_data';

import '../cartridge/ines_rom.dart';
import '../controller/nes_controller.dart';

abstract interface class CpuBus {
  int read(int address);
  void write(int address, int value);
}

/// CPU memory map for mapper 0 (NROM). PPU/APU register side effects and DMA
/// are not implemented in this milestone.
class NesBus implements CpuBus {
  NesBus({
    NesController Function()? controller1,
    NesController Function()? controller2,
  }) : controller1 = (controller1 ?? NesController.new)(),
       controller2 = (controller2 ?? NesController.new)();

  final NesController controller1;
  final NesController controller2;
  final Uint8List _ram = Uint8List(2048);
  final Uint8List _prgRam = Uint8List(8192);
  final Uint8List _ppuRegisters = Uint8List(8);
  NesRom? _rom;
  int _openBus = 0;
  NesRom? get cartridge => _rom;

  void insertCartridge(NesRom rom) {
    if (rom.mapper != 0) {
      throw RomFormatException('Mapper ${rom.mapper} is not implemented yet.');
    }
    if (rom.prgRom.length != 16384 && rom.prgRom.length != 32768) {
      throw const RomFormatException('NROM supports 16 KiB or 32 KiB PRG ROM.');
    }
    if (rom.chrRom.isNotEmpty && rom.chrRom.length != 8192) {
      throw const RomFormatException('NROM supports 8 KiB CHR ROM or CHR RAM.');
    }
    _rom = rom;
  }

  @override
  int read(int address) {
    final addr = address & 0xffff;
    if (addr < 0x2000) {
      _openBus = _ram[addr & 0x7ff];
    } else if (addr < 0x4000) {
      _openBus = _ppuRegisters[addr & 7];
    } else if (addr == 0x4016) {
      _openBus = controller1.readSerial();
    } else if (addr == 0x4017) {
      _openBus = controller2.readSerial();
    } else if (addr >= 0x6000 && addr < 0x8000) {
      _openBus = _prgRam[addr - 0x6000];
    } else if (addr >= 0x8000 && _rom != null) {
      final prg = _rom!.prgRom;
      var offset = addr - 0x8000;
      if (prg.length == 16384) offset &= 0x3fff;
      _openBus = prg[offset];
    }
    return _openBus & 0xff;
  }

  @override
  void write(int address, int value) {
    final addr = address & 0xffff;
    final byte = value & 0xff;
    if (addr < 0x2000) {
      _ram[addr & 0x7ff] = byte;
      _openBus = byte;
    } else if (addr < 0x4000) {
      _ppuRegisters[addr & 7] = byte;
      _openBus = byte;
    } else if (addr == 0x4016) {
      controller1.writeStrobe(byte);
      controller2.writeStrobe(byte);
      _openBus = byte;
    } else if (addr >= 0x6000 && addr < 0x8000) {
      _prgRam[addr - 0x6000] = byte;
      _openBus = byte;
    }
  }
}

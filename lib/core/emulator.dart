import 'dart:typed_data';

import 'cartridge/ines_rom.dart';
import 'controller/nes_controller.dart';
import 'cpu/cpu6502.dart';
import 'memory/nes_bus.dart';

/// Testable early core: cartridge, CPU, memory map and input are real.
/// PPU, APU, and the frame scheduler are not implemented yet.
class NesEmulator {
  final NesController controller1 = NesController();
  final NesController controller2 = NesController();
  late final NesBus bus = NesBus(
    controller1: () => controller1,
    controller2: () => controller2,
  );
  NesRom? rom;
  Cpu6502? cpu;
  bool get hasCartridge => rom != null;

  void loadRom(Uint8List bytes) {
    final parsed = NesRom.parse(bytes);
    if (parsed.mapper != 0) {
      throw RomFormatException('Mapper ${parsed.mapper} is not implemented. This milestone supports NROM (mapper 0).');
    }
    bus.insertCartridge(parsed);
    rom = parsed;
    cpu = Cpu6502(bus)..reset();
  }

  int stepInstruction() {
    final active=cpu;
    if (active==null) throw StateError('Load a ROM before stepping the CPU.');
    return active.step();
  }

  void reset() {
    cpu?.reset();
    controller1.setButtons(const <NesButton>{});
    controller2.setButtons(const <NesButton>{});
  }
}

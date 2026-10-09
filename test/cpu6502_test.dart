import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nintendo_nes/core/cpu/cpu6502.dart';
import 'package:nintendo_nes/core/memory/nes_bus.dart';

class TestBus implements CpuBus {
  final bytes=Uint8List(65536);
  @override int read(int address)=>bytes[address&0xffff];
  @override void write(int address,int value)=>bytes[address&0xffff]=value&255;
  void load(int start,List<int> program) {
    bytes.setRange(start,start+program.length,program);
    bytes[0xfffc]=start&255; bytes[0xfffd]=start>>8;
  }
}
void main() {
  test('immediate load, ADC overflow/negative flags, and stack instructions', () {
    final bus=TestBus()..load(0x8000,[0xa9,0x7f,0x69,1,0x48,0xa9,0,0x68]);
    final cpu=Cpu6502(bus)..reset();
    expect(cpu.step(),2); expect(cpu.a,0x7f);
    expect(cpu.step(),2); expect(cpu.a,0x80);
    expect(cpu.p&0x40,isNot(0)); expect(cpu.p&0x80,isNot(0));
    expect(cpu.step(),3); expect(cpu.step(),2); expect(cpu.a,0);
    expect(cpu.step(),4); expect(cpu.a,0x80); expect(cpu.totalCycles,13);
  });
  test('zero page indexing wraps and relative branch updates PC', () {
    final bus=TestBus()..load(0x80fd,[0xa2,1,0xb5,0xff,0xd0,2,0xa9,0,0xea]);
    bus.bytes[0]=0x55;
    final cpu=Cpu6502(bus)..reset();
    cpu.step(); expect(cpu.step(),4); expect(cpu.a,0x55);
    expect(cpu.step(),3); expect(cpu.pc,0x8105);
  });
  test('official opcode table contains all 151 documented opcodes',()=>expect(Cpu6502.supportedOpcodeCount,151));
  test('unsupported unofficial opcodes fail explicitly', () {
    final cpu=Cpu6502(TestBus()..load(0x8000,[0x02]))..reset();
    expect(cpu.step,throwsUnsupportedError);
  });
}

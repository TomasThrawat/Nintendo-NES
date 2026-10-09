import '../memory/nes_bus.dart';

class _Op {
  const _Op(this.name, this.mode, this.cycles);
  final String name;
  final String mode;
  final int cycles;
  bool get pagePenalty =>
      const {'ADC','AND','CMP','EOR','LDA','LDX','LDY','ORA','SBC'}.contains(name) &&
      const {'ax','ay','iy'}.contains(mode);
}

/// Ricoh 2A03 CPU: all 151 official NMOS 6502 instructions. Unofficial
/// opcodes fail explicitly. Cycle accuracy is instruction-level, not bus-cycle
/// accuracy; DMA, PPU timing, and APU integration are not implemented.
class Cpu6502 {
  Cpu6502(this.bus);
  final CpuBus bus;

  int a = 0, x = 0, y = 0, sp = 0xfd, pc = 0, p = 0x24, totalCycles = 0;
  bool _nmi = false, _irq = false, _pageCrossed = false;

  static const int _c=1, _z=2, _i=4, _d=8, _b=16, _u=32, _v=64, _n=128;
  static const String _definition = '''
00 BRK imp 7 01 ORA ix 6 05 ORA z 3 06 ASL z 5 08 PHP imp 3 09 ORA imm 2 0a ASL acc 2 0d ORA abs 4 0e ASL abs 6
10 BPL rel 2 11 ORA iy 5 15 ORA zx 4 16 ASL zx 6 18 CLC imp 2 19 ORA ay 4 1d ORA ax 4 1e ASL ax 7
20 JSR abs 6 21 AND ix 6 24 BIT z 3 25 AND z 3 26 ROL z 5 28 PLP imp 4 29 AND imm 2 2a ROL acc 2 2c BIT abs 4 2d AND abs 4 2e ROL abs 6
30 BMI rel 2 31 AND iy 5 35 AND zx 4 36 ROL zx 6 38 SEC imp 2 39 AND ay 4 3d AND ax 4 3e ROL ax 7
40 RTI imp 6 41 EOR ix 6 45 EOR z 3 46 LSR z 5 48 PHA imp 3 49 EOR imm 2 4a LSR acc 2 4c JMP abs 3 4d EOR abs 4 4e LSR abs 6
50 BVC rel 2 51 EOR iy 5 55 EOR zx 4 56 LSR zx 6 58 CLI imp 2 59 EOR ay 4 5d EOR ax 4 5e LSR ax 7
60 RTS imp 6 61 ADC ix 6 65 ADC z 3 66 ROR z 5 68 PLA imp 4 69 ADC imm 2 6a ROR acc 2 6c JMP ind 5 6d ADC abs 4 6e ROR abs 6
70 BVS rel 2 71 ADC iy 5 75 ADC zx 4 76 ROR zx 6 78 SEI imp 2 79 ADC ay 4 7d ADC ax 4 7e ROR ax 7
81 STA ix 6 84 STY z 3 85 STA z 3 86 STX z 3 88 DEY imp 2 8a TXA imp 2 8c STY abs 4 8d STA abs 4 8e STX abs 4
90 BCC rel 2 91 STA iy 6 94 STY zx 4 95 STA zx 4 96 STX zy 4 98 TYA imp 2 99 STA ay 5 9a TXS imp 2 9d STA ax 5
a0 LDY imm 2 a1 LDA ix 6 a2 LDX imm 2 a4 LDY z 3 a5 LDA z 3 a6 LDX z 3 a8 TAY imp 2 a9 LDA imm 2 aa TAX imp 2 ac LDY abs 4 ad LDA abs 4 ae LDX abs 4
b0 BCS rel 2 b1 LDA iy 5 b4 LDY zx 4 b5 LDA zx 4 b6 LDX zy 4 b8 CLV imp 2 b9 LDA ay 4 ba TSX imp 2 bc LDY ax 4 bd LDA ax 4 be LDX ay 4
c0 CPY imm 2 c1 CMP ix 6 c4 CPY z 3 c5 CMP z 3 c6 DEC z 5 c8 INY imp 2 c9 CMP imm 2 ca DEX imp 2 cc CPY abs 4 cd CMP abs 4 ce DEC abs 6
d0 BNE rel 2 d1 CMP iy 5 d5 CMP zx 4 d6 DEC zx 6 d8 CLD imp 2 d9 CMP ay 4 dd CMP ax 4 de DEC ax 7
e0 CPX imm 2 e1 SBC ix 6 e4 CPX z 3 e5 SBC z 3 e6 INC z 5 e8 INX imp 2 e9 SBC imm 2 ea NOP imp 2 ec CPX abs 4 ed SBC abs 4 ee INC abs 6
f0 BEQ rel 2 f1 SBC iy 5 f5 SBC zx 4 f6 INC zx 6 f8 SED imp 2 f9 SBC ay 4 fd SBC ax 4 fe INC ax 7
''';

  static final Map<int, _Op> _ops = _parseOps();
  static Map<int, _Op> _parseOps() {
    final tokens = _definition.trim().split(RegExp(r'\s+'));
    final result = <int, _Op>{};
    for (var i=0; i<tokens.length; i+=4) {
      final code = int.parse(tokens[i], radix: 16);
      result[code] = _Op(tokens[i+1], tokens[i+2], int.parse(tokens[i+3]));
    }
    return result;
  }
  static int get supportedOpcodeCount => _ops.length;

  void reset() {
    a=0; x=0; y=0; sp=0xfd; p=_i|_u; pc=_word(0xfffc);
    totalCycles=0; _nmi=false; _irq=false;
  }
  void requestNmi() => _nmi=true;
  void requestIrq() => _irq=true;

  int step() {
    if (_nmi) { _nmi=false; _interrupt(0xfffa); totalCycles+=7; return 7; }
    if (_irq && !_flag(_i)) { _irq=false; _interrupt(0xfffe); totalCycles+=7; return 7; }
    final at=pc, opcode=_byte(pc++);
    final op=_ops[opcode];
    if (op==null) {
      throw UnsupportedError('Unsupported unofficial opcode 0x${opcode.toRadixString(16)} at 0x${at.toRadixString(16)}.');
    }
    _pageCrossed=false;
    var extra=0;
    int value() => _readOperand(op.mode);
    switch (op.name) {
      case 'ADC': _adc(value()); break;
      case 'SBC': _adc(value() ^ 0xff); break;
      case 'AND': a &= value(); _nz(a); break;
      case 'ORA': a |= value(); _nz(a); break;
      case 'EOR': a ^= value(); _nz(a); break;
      case 'LDA': a=value(); _nz(a); break;
      case 'LDX': x=value(); _nz(x); break;
      case 'LDY': y=value(); _nz(y); break;
      case 'STA': bus.write(_address(op.mode), a); break;
      case 'STX': bus.write(_address(op.mode), x); break;
      case 'STY': bus.write(_address(op.mode), y); break;
      case 'CMP': _compare(a,value()); break;
      case 'CPX': _compare(x,value()); break;
      case 'CPY': _compare(y,value()); break;
      case 'BIT':
        final v=value(); _set(_z,(a&v)==0); _set(_n,(v&0x80)!=0); _set(_v,(v&0x40)!=0); break;
      case 'ASL': _modify(op.mode,(v){_set(_c,(v&0x80)!=0);return v<<1;}); break;
      case 'LSR': _modify(op.mode,(v){_set(_c,(v&1)!=0);return v>>1;}); break;
      case 'ROL': _modify(op.mode,(v){final c=_flag(_c)?1:0;_set(_c,(v&0x80)!=0);return (v<<1)|c;}); break;
      case 'ROR': _modify(op.mode,(v){final c=_flag(_c)?0x80:0;_set(_c,(v&1)!=0);return (v>>1)|c;}); break;
      case 'INC': _modify(op.mode,(v)=>v+1); break;
      case 'DEC': _modify(op.mode,(v)=>v-1); break;
      case 'INX': x=(x+1)&255; _nz(x); break;
      case 'INY': y=(y+1)&255; _nz(y); break;
      case 'DEX': x=(x-1)&255; _nz(x); break;
      case 'DEY': y=(y-1)&255; _nz(y); break;
      case 'TAX': x=a; _nz(x); break;
      case 'TAY': y=a; _nz(y); break;
      case 'TXA': a=x; _nz(a); break;
      case 'TYA': a=y; _nz(a); break;
      case 'TSX': x=sp; _nz(x); break;
      case 'TXS': sp=x; break;
      case 'PHA': _push(a); break;
      case 'PHP': _push(p|_b|_u); break;
      case 'PLA': a=_pop(); _nz(a); break;
      case 'PLP': p=(_pop()&~_b)|_u; break;
      case 'CLC': _set(_c,false); break;
      case 'SEC': _set(_c,true); break;
      case 'CLI': _set(_i,false); break;
      case 'SEI': _set(_i,true); break;
      case 'CLV': _set(_v,false); break;
      case 'CLD': _set(_d,false); break;
      case 'SED': _set(_d,true); break;
      case 'JMP':
        final target=_address(op.mode);
        if (op.mode=='ind') {
          final hi=(target&0xff00)|((target+1)&255);
          pc=_byte(target)|(_byte(hi)<<8);
        } else { pc=target; }
        break;
      case 'JSR':
        final target=_address(op.mode), ret=(pc-1)&0xffff;
        _push(ret>>8); _push(ret&255); pc=target; break;
      case 'RTS': pc=((_pop()|(_pop()<<8))+1)&0xffff; break;
      case 'RTI': p=(_pop()&~_b)|_u; pc=_pop()|(_pop()<<8); break;
      case 'BRK':
        pc=(pc+1)&0xffff; _push(pc>>8); _push(pc&255); _push(p|_b|_u);
        _set(_i,true); pc=_word(0xfffe); break;
      case 'BPL': extra=_branch(!_flag(_n)); break;
      case 'BMI': extra=_branch(_flag(_n)); break;
      case 'BVC': extra=_branch(!_flag(_v)); break;
      case 'BVS': extra=_branch(_flag(_v)); break;
      case 'BCC': extra=_branch(!_flag(_c)); break;
      case 'BCS': extra=_branch(_flag(_c)); break;
      case 'BNE': extra=_branch(!_flag(_z)); break;
      case 'BEQ': extra=_branch(_flag(_z)); break;
      case 'NOP': break;
      default: throw StateError('Opcode table inconsistency: ${op.name}.');
    }
    if (op.pagePenalty && _pageCrossed) extra++;
    final elapsed=op.cycles+extra;
    totalCycles+=elapsed;
    return elapsed;
  }

  int _readOperand(String mode) {
    if (mode=='acc') return a;
    if (mode=='rel') return _relative();
    return _byte(_address(mode));
  }
  int _address(String mode) {
    _pageCrossed=false;
    switch (mode) {
      case 'imm': final addr=pc; pc=(pc+1)&0xffff; return addr;
      case 'z': final addr=_byte(pc); pc=(pc+1)&0xffff; return addr;
      case 'zx': final addr=(_byte(pc)+x)&255; pc=(pc+1)&0xffff; return addr;
      case 'zy': final addr=(_byte(pc)+y)&255; pc=(pc+1)&0xffff; return addr;
      case 'abs': final addr=_word(pc); pc=(pc+2)&0xffff; return addr;
      case 'ax': final base=_word(pc); pc=(pc+2)&0xffff; final addr=(base+x)&0xffff; _pageCrossed=(base&0xff00)!=(addr&0xff00); return addr;
      case 'ay': final base=_word(pc); pc=(pc+2)&0xffff; final addr=(base+y)&0xffff; _pageCrossed=(base&0xff00)!=(addr&0xff00); return addr;
      case 'ix':
        final zp=(_byte(pc)+x)&255; pc=(pc+1)&0xffff;
        return _byte(zp)|(_byte((zp+1)&255)<<8);
      case 'iy':
        final zp=_byte(pc); pc=(pc+1)&0xffff;
        final base=_byte(zp)|(_byte((zp+1)&255)<<8), addr=(base+y)&0xffff;
        _pageCrossed=(base&0xff00)!=(addr&0xff00); return addr;
      case 'ind': final addr=_word(pc); pc=(pc+2)&0xffff; return addr;
      default: throw StateError('No address for mode $mode.');
    }
  }
  int _relative() {
    final raw=_byte(pc); pc=(pc+1)&0xffff;
    return raw<128 ? raw : raw-256;
  }
  int _branch(bool take) {
    final offset=_relative();
    if (!take) return 0;
    final old=pc; pc=(pc+offset)&0xffff;
    return 1+(((old&0xff00)!=(pc&0xff00))?1:0);
  }
  void _modify(String mode, int Function(int) action) {
    if (mode=='acc') { a=action(a)&255; _nz(a); return; }
    final address=_address(mode), result=action(_byte(address))&255;
    bus.write(address,result); _nz(result);
  }
  void _adc(int value) {
    final sum=a+value+(_flag(_c)?1:0), result=sum&255;
    _set(_c,sum>255);
    _set(_v,((~(a^value)&(a^result)&0x80)!=0));
    a=result; _nz(a);
  }
  void _compare(int reg,int value) {
    _set(_c,reg>=value); _nz((reg-value)&255);
  }
  void _interrupt(int vector) {
    _push(pc>>8); _push(pc&255); _push((p&~_b)|_u);
    _set(_i,true); pc=_word(vector);
  }
  void _push(int v) { bus.write(0x100|sp,v&255); sp=(sp-1)&255; }
  int _pop() { sp=(sp+1)&255; return _byte(0x100|sp); }
  int _byte(int address) => bus.read(address&0xffff)&255;
  int _word(int address) => _byte(address)|(_byte((address+1)&0xffff)<<8);
  bool _flag(int flag) => (p&flag)!=0;
  void _set(int flag,bool enabled) { p=enabled?(p|flag):(p&~flag); p=(p|_u)&255; }
  void _nz(int value) { final v=value&255; _set(_z,v==0); _set(_n,(v&128)!=0); }
}

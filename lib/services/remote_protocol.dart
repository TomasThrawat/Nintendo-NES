import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../core/controller/nes_controller.dart';

const int maxRemoteFrameBytes = 1024;
const String _alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

String newPairingCode() {
  final random=Random.secure();
  return List<String>.generate(16,(_)=>_alphabet[random.nextInt(_alphabet.length)]).join();
}
String newProtocolNonce() {
  final random=Random.secure();
  return List<String>.generate(16,(_)=>random.nextInt(256).toRadixString(16).padLeft(2,'0')).join();
}
String protocolMac(String key,String message)=>Hmac(sha256,utf8.encode(key)).convert(utf8.encode(message)).toString();
bool constantTimeEquals(String a,String b) {
  if (a.length != b.length) {
    return false;
  }
  var diff=0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff==0;
}
bool isProtocolNonce(Object? v)=>v is String&&RegExp(r'^[0-9a-f]{32}$').hasMatch(v);
String normalizedPairingCode(String v)=>v.trim().toUpperCase();
bool isPairingCode(String v)=>v.length==16&&v.split('').every(_alphabet.contains);
int parseButtonMask(Object? v) {
  if(v is! int||v<0||v>255) { throw const FormatException('Invalid input mask.'); }
  return v;
}
int parseSequence(Object? v) {
  if(v is! int||v<0||v>9007199254740991) { throw const FormatException('Invalid input sequence.'); }
  return v;
}

/// Bounded newline-delimited JSON frames. Oversized or malformed input closes
/// the framing stream instead of allocating based on peer-controlled lengths.
class JsonLineBuffer {
  JsonLineBuffer({required this.onLine,required this.onInvalidFrame});
  final void Function(String) onLine;
  final void Function() onInvalidFrame;
  final List<int> _pending=<int>[];
  bool _closed=false;
  void add(List<int> bytes) {
    if (_closed) {
      return;
    }
    for(final byte in bytes) {
      if(byte==10) {
        if (_pending.isNotEmpty && _pending.last == 13) {
          _pending.removeLast();
        }
        try {
          final line=utf8.decode(_pending,allowMalformed:false);
          _pending.clear(); onLine(line);
        } on FormatException {
          _pending.clear(); _closed=true; onInvalidFrame(); return;
        }
      } else {
        _pending.add(byte);
        if(_pending.length>maxRemoteFrameBytes) {
          _pending.clear(); _closed=true; onInvalidFrame(); return;
        }
      }
    }
  }
  void close(){_closed=true;_pending.clear();}
}
Set<NesButton> remoteButtonsFromMask(Object? mask)=>NesController.buttonsFromMask(parseButtonMask(mask));

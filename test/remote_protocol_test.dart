import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:nintendo_nes/core/controller/nes_controller.dart';
import 'package:nintendo_nes/services/local_controller_client.dart';
import 'package:nintendo_nes/services/local_controller_server.dart';
import 'package:nintendo_nes/services/remote_protocol.dart';

void main() {
  test('generates valid pairing codes and protocol nonces',(){
    expect(isPairingCode(newPairingCode()),isTrue);
    expect(isProtocolNonce(newProtocolNonce()),isTrue);
  });
  test('host/client authenticate, send simultaneous input, release on disconnect',() async {
    final updates=Completer<void>(),released=Completer<void>();
    final seen=<Set<NesButton>>[];
    final host=LocalControllerServer(port:0,onButtonsChanged:(buttons){
      seen.add(Set<NesButton>.of(buttons));
      if(buttons.contains(NesButton.a)&&buttons.contains(NesButton.right)&&!updates.isCompleted) { updates.complete(); }
      if(buttons.isEmpty&&updates.isCompleted&&!released.isCompleted) { released.complete(); }
    },onStatusChanged:(_){});
    final client=LocalControllerClient();
    try {
      await host.start();
      await client.connect(host:'127.0.0.1',port:host.boundPort,pairingCode:host.pairingCode!,
        onButtonsChanged:(_){},onStatusChanged:(_){});
      client.setButtons(const {NesButton.a,NesButton.right});
      await updates.future.timeout(const Duration(seconds:3));
      expect(host.isConnected,isTrue);
      expect(seen.last,containsAll(const {NesButton.a,NesButton.right}));
      await client.disconnect();
      await released.future.timeout(const Duration(seconds:3));
      expect(host.isConnected,isFalse);expect(seen.last,isEmpty);
    } finally {await client.disconnect();await host.stop();}
  });
  test('rejects malformed masks and sequence numbers',(){
    expect(()=>parseButtonMask(256),throwsFormatException);
    expect(()=>parseButtonMask(-1),throwsFormatException);
    expect(()=>parseSequence(-1),throwsFormatException);
    expect(()=>parseSequence('1'),throwsFormatException);
  });
  test('HMAC comparison detects message tampering',(){
    final mac=protocolMac('secret','input|1|3');
    expect(constantTimeEquals(mac,protocolMac('secret','input|1|3')),isTrue);
    expect(constantTimeEquals(mac,protocolMac('secret','input|1|4')),isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nintendo_nes/core/controller/nes_controller.dart';

void main() {
  test('serial controller reads A, B, Select, Start, directions in order', () {
    final c=NesController()..setButtons(const {NesButton.a,NesButton.start});
    c.writeStrobe(1); c.writeStrobe(0);
    expect(c.readSerial()&1,1);
    expect(c.readSerial()&1,0);
    expect(c.readSerial()&1,0);
    expect(c.readSerial()&1,1);
    for(var i=0;i<4;i++) { expect(c.readSerial()&1,0); }
    expect(c.readSerial()&1,1);
  });
  test('strobe reads live A state and mask supports simultaneous presses', () {
    final c=NesController()..writeStrobe(1);
    c.setButtons(const {NesButton.a,NesButton.right});
    expect(c.readSerial()&1,1);
    c.setButton(NesButton.a,false); expect(c.readSerial()&1,0);
    expect(NesController.maskFor(const {NesButton.a,NesButton.right}),0x81);
    expect(NesController.buttonsFromMask(0x81),const {NesButton.a,NesButton.right});
  });
}

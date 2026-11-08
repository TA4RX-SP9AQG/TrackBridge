import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/core/packet_summary.dart';

void main() {
  test('position packet', () {
    final p = summarizePacket('N1TEST-7>APLOX1,SP9KKK-2*:!5003.88N/01956.70E>Spacer yapiyorum');
    expect(p.source, 'N1TEST-7');
    expect(p.kind, PacketKind.position);
    expect(p.text, '!5003.88N/01956.70E>Spacer yapiyorum');
    expect(p.viaDigipeater, isTrue);
  });

  test('direct packet has no digipeater', () {
    expect(summarizePacket('N1TEST-7>APLOX1:!5003.88N/01956.70E>x').viaDigipeater, isFalse);
    expect(summarizePacket('N1TEST-7>APLOX1,WIDE1-1:!5003.88N/01956.70E>x').viaDigipeater, isFalse); // not yet repeated
  });

  test('message packet is shown as "-> addressee: text"', () {
    final p = summarizePacket('N1TEST-7>APLOX1::N0DEMO-9 :Merhaba, duyuyor musun?{12');
    expect(p.kind, PacketKind.message);
    expect(p.text, '→ N0DEMO-9: Merhaba, duyuyor musun?');
  });

  test('ack packet', () {
    final p = summarizePacket('N1TEST-7>APLOX1::N0DEMO-9 :ack12');
    expect(p.kind, PacketKind.message);
    expect(p.text, '→ N0DEMO-9: onay (ack 12)');
  });

  test('status, Mic-E and unknown', () {
    expect(summarizePacket('A1>B:>just a status').kind, PacketKind.status);
    expect(summarizePacket('A1>B:>just a status').text, 'just a status');
    expect(summarizePacket('A1>S3PS2V:`|>Fp wj/').kind, PacketKind.position);
    expect(summarizePacket('A1>B:Tsomething').kind, PacketKind.other);
  });

  test('malformed lines never throw', () {
    for (final s in ['', 'no colon here', '>:', 'A>B:', ':::']) {
      expect(() => summarizePacket(s), returnsNormally, reason: s);
    }
    expect(summarizePacket('no colon here').source, 'no colon here');
  });
}

// test/e2ee_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offgrid_sos/core/e2ee_service.dart';

/// เชื่อม [a]/[b] เข้าด้วยกันแบบ in-memory เพื่อจำลองการส่งข้อความ E2EE handshake
/// ไป-กลับระหว่างสองฝั่งในหน่วยความจำ (แทน transport จริง)
({Future<void> Function(String) aSend, Future<void> Function(String) bSend})
_wire(E2EEService a, String aId, E2EEService b, String bId) {
  late final Future<void> Function(String) aSend;
  late final Future<void> Function(String) bSend;
  aSend = (body) => b.handleMessage(aId, body, bSend);
  bSend = (body) => a.handleMessage(bId, body, aSend);
  return (aSend: aSend, bSend: bSend);
}

void main() {
  group('E2EEService X3DH handshake', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initiator and responder derive matching session keys', () async {
      final alice = E2EEService();
      final bob = E2EEService();
      await alice.init();
      await bob.init();

      final wired = _wire(alice, 'alice', bob, 'bob');
      await alice.initHandshake('bob', wired.aSend);

      expect(alice.hasSession('bob'), true);
      expect(bob.hasSession('alice'), true);

      final cipherFromAlice = await alice.encrypt('hello bob', 'bob');
      expect(await bob.decrypt(cipherFromAlice, 'alice'), 'hello bob');

      final cipherFromBob = await bob.encrypt('hi alice', 'alice');
      expect(await alice.decrypt(cipherFromBob, 'bob'), 'hi alice');
    });

    test('re-handshake after clearSession produces a usable new session', () async {
      final alice = E2EEService();
      final bob = E2EEService();
      await alice.init();
      await bob.init();

      final wired = _wire(alice, 'alice', bob, 'bob');
      await alice.initHandshake('bob', wired.aSend);
      expect(alice.hasSession('bob'), true);

      // จำลอง reconnect: เคลียร์ session แล้ว handshake ใหม่ — ephemeral keypair ต้องสดใหม่
      // ทุกครั้ง (forward secrecy) แต่ยัง handshake สำเร็จและคุยกันได้ตามปกติ
      alice.clearSession('bob');
      bob.clearSession('alice');
      expect(alice.hasSession('bob'), false);

      await alice.initHandshake('bob', wired.aSend);
      expect(alice.hasSession('bob'), true);
      expect(bob.hasSession('alice'), true);

      final cipher = await alice.encrypt('second session', 'bob');
      expect(await bob.decrypt(cipher, 'alice'), 'second session');
    });
  });
}

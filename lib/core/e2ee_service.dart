import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger.dart';

/// End-to-End Encryption service using X25519 key agreement + AES-256-GCM.
///
/// Protocol (X3DH-lite — gives forward secrecy on top of TOFU identity trust):
///   Initiator → Responder : `E2E_HELLO:<identity_pub_b64>:<ephemeral_pub_b64>`
///   Responder → Initiator : `E2E_ACK:<identity_pub_b64>:<ephemeral_pub_b64>`
///   After handshake       : `ENC:<base64_nonce>:<base64_ciphertext+mac>`
///
/// Each handshake generates a fresh, never-persisted ephemeral X25519 keypair.
/// The session key is derived from 4 combined ECDH terms (identity×identity,
/// ephemeral×ephemeral, and both identity×ephemeral cross terms) — mirroring
/// the shape of Signal's X3DH. Because the ephemeral private keys are never
/// written to disk and are discarded right after deriving the session key,
/// compromising the long-term identity key later does NOT let an attacker
/// recompute past session keys from captured traffic (forward secrecy).
///
/// Session keys live in memory only — cleared on app restart.
/// Private key seed is persisted in SharedPreferences so our public key
/// stays stable across sessions (peer can cache our identity key).
class E2EEService {
  static const _prefKey = 'e2ee_seed_v1';
  static const _trustedKeyPrefix = 'e2ee_trusted_v1_';
  static const _signPrefKey = 'e2ee_sign_seed_v1';
  static const _trustedSignKeyPrefix = 'e2ee_trusted_sign_v1_';

  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final _ed25519 = Ed25519();

  SimpleKeyPair? _myKeyPair;
  SimpleKeyPair? _mySigningKeyPair;
  final Map<String, SecretKey> _sessionKeys = {};
  final Set<String> _initiated = {};

  // ephemeral keypair ที่เราสร้างไว้ตอนเป็น initiator (ส่ง HELLO) รอจนกว่า ACK จะกลับมา
  // เพื่อใช้คำนวณ session key — ไม่ persist ที่ไหนเลย ทิ้งทันทีหลังใช้
  final Map<String, SimpleKeyPair> _pendingEphemeralKeys = {};

  // handshake ที่คีย์ประจำตัว (identity) ของ peer ไม่ตรงกับที่เคย trust ไว้ (TOFU mismatch)
  // เก็บทุกอย่างที่ต้องใช้คำนวณ session key ไว้รอ user ยืนยันผ่าน acceptNewKey()
  final Map<String, _PendingHandshake> _pendingUntrustedHandshakes = {};

  // Emits peerId when a peer reconnects with a different identity key than stored.
  final _keyMismatchController = StreamController<String>.broadcast();
  Stream<String> get onKeyMismatch => _keyMismatchController.stream;

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);

    if (stored != null) {
      final seed = base64Decode(stored);
      _myKeyPair = await _x25519.newKeyPairFromSeed(seed);
      Log.d('[E2EE] Loaded existing keypair from prefs');
    } else {
      _myKeyPair = await _x25519.newKeyPair();
      final seed = await _myKeyPair!.extractPrivateKeyBytes();
      await prefs.setString(_prefKey, base64Encode(seed));
      Log.d('[E2EE] Generated new keypair and saved seed');
    }

    final storedSignSeed = prefs.getString(_signPrefKey);
    if (storedSignSeed != null) {
      final seed = base64Decode(storedSignSeed);
      _mySigningKeyPair = await _ed25519.newKeyPairFromSeed(seed);
      Log.d('[E2EE] Loaded existing signing keypair from prefs');
    } else {
      _mySigningKeyPair = await _ed25519.newKeyPair();
      final seed = await _mySigningKeyPair!.extractPrivateKeyBytes();
      await prefs.setString(_signPrefKey, base64Encode(seed));
      Log.d('[E2EE] Generated new signing keypair and saved seed');
    }
  }

  // ---------------------------------------------------------------------------
  // Handshake
  // ---------------------------------------------------------------------------

  /// Send E2E_HELLO to a newly connected peer. No-op if already initiated.
  Future<void> initHandshake(
    String peerId,
    Future<void> Function(String body) send,
  ) async {
    if (_initiated.contains(peerId)) return;
    _initiated.add(peerId);

    // ephemeral keypair สดใหม่ทุก handshake — คือหัวใจของ forward secrecy
    final ephemeral = await _x25519.newKeyPair();
    _pendingEphemeralKeys[peerId] = ephemeral;

    final identityPubB64 = base64Encode(await _pubKeyBytes());
    final ephemeralPubB64 = base64Encode(
      (await ephemeral.extractPublicKey()).bytes,
    );
    await send('E2E_HELLO:$identityPubB64:$ephemeralPubB64');
    Log.d('[E2EE] Sent HELLO (+ephemeral) to $peerId');
  }

  /// Process an incoming E2EE protocol message.
  /// Returns true if the message was consumed (caller should not process further).
  Future<bool> handleMessage(
    String fromPeerId,
    String body,
    Future<void> Function(String body) send,
  ) async {
    if (body.startsWith('E2E_HELLO:')) {
      final parts = body.substring('E2E_HELLO:'.length).split(':');
      if (parts.length < 2) return true; // malformed — บริโภคทิ้งเงียบๆ
      final identityB64 = parts[0];
      final ephemeralB64 = parts[1];

      final trusted = await _checkAndStoreTrustedKey(fromPeerId, identityB64);

      // เราเป็นฝั่ง responder — สร้าง ephemeral keypair ของเราเองสดใหม่ทุกครั้ง (ไม่ persist)
      final myEphemeral = await _x25519.newKeyPair();

      if (trusted) {
        _sessionKeys[fromPeerId] = await _deriveSessionKeyX3DH(
          myEphemeral: myEphemeral,
          theirIdentity: _parsePublicKey(identityB64),
          theirEphemeral: _parsePublicKey(ephemeralB64),
        );
        Log.d(
          '[E2EE] Handshake HELLO from $fromPeerId — session established (forward-secret)',
        );
      } else {
        _pendingUntrustedHandshakes[fromPeerId] = _PendingHandshake(
          myEphemeral: myEphemeral,
          theirIdentityB64: identityB64,
          theirEphemeralB64: ephemeralB64,
        );
        Log.d(
          '[E2EE] Handshake HELLO from $fromPeerId — key mismatch, session ค้างรอ user ยืนยัน',
        );
      }

      // ตอบกลับด้วย identity + ephemeral ของเราเสมอ ไม่ว่า trust จะผ่านหรือไม่
      // เพื่อให้ initiator รู้ pubkey ปัจจุบันของเรา
      final myIdentityPubB64 = base64Encode(await _pubKeyBytes());
      final myEphemeralPubB64 = base64Encode(
        (await myEphemeral.extractPublicKey()).bytes,
      );
      await send('E2E_ACK:$myIdentityPubB64:$myEphemeralPubB64');
      return true;
    }

    if (body.startsWith('E2E_ACK:')) {
      if (_sessionKeys.containsKey(fromPeerId)) {
        _pendingEphemeralKeys.remove(
          fromPeerId,
        ); // ACK ซ้ำ/สาย — session มีอยู่แล้ว ทิ้ง ephemeral ที่ค้าง
        return true;
      }

      final parts = body.substring('E2E_ACK:'.length).split(':');
      if (parts.length < 2) return true;
      final identityB64 = parts[0];
      final ephemeralB64 = parts[1];

      final myEphemeral = _pendingEphemeralKeys.remove(fromPeerId);
      if (myEphemeral == null) {
        Log.d(
          '[E2EE] ได้รับ ACK จาก $fromPeerId แต่ไม่มี ephemeral ที่ค้างไว้ (ไม่ใช่ initiator ของ handshake นี้) — ข้าม',
        );
        return true;
      }

      final trusted = await _checkAndStoreTrustedKey(fromPeerId, identityB64);
      if (trusted) {
        _sessionKeys[fromPeerId] = await _deriveSessionKeyX3DH(
          myEphemeral: myEphemeral,
          theirIdentity: _parsePublicKey(identityB64),
          theirEphemeral: _parsePublicKey(ephemeralB64),
        );
        Log.d(
          '[E2EE] Handshake ACK from $fromPeerId — session established (forward-secret)',
        );
      } else {
        _pendingUntrustedHandshakes[fromPeerId] = _PendingHandshake(
          myEphemeral: myEphemeral,
          theirIdentityB64: identityB64,
          theirEphemeralB64: ephemeralB64,
        );
        Log.d(
          '[E2EE] Handshake ACK from $fromPeerId — key mismatch, session ค้างรอ user ยืนยัน',
        );
      }
      return true;
    }

    return false;
  }

  /// เรียกเมื่อ user ยืนยันยอมรับคีย์ใหม่ของ peer ที่ mismatch (หลังเห็น banner แล้วกดยืนยัน)
  /// อัปเดต trusted key ใน storage และ derive session key (forward-secret) ใหม่ให้ใช้งานได้
  Future<void> acceptNewKey(String peerId) async {
    final pending = _pendingUntrustedHandshakes.remove(peerId);
    if (pending == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_trustedKeyPrefix$peerId',
      pending.theirIdentityB64,
    );

    _sessionKeys[peerId] = await _deriveSessionKeyX3DH(
      myEphemeral: pending.myEphemeral,
      theirIdentity: _parsePublicKey(pending.theirIdentityB64),
      theirEphemeral: _parsePublicKey(pending.theirEphemeralB64),
    );
    Log.d(
      '[E2EE] User ยืนยันรับคีย์ใหม่ของ $peerId แล้ว — session อัปเดต (forward-secret)',
    );
  }

  /// เรียกเมื่อ user ปฏิเสธ/ปิด banner โดยไม่ยืนยันคีย์ใหม่ — ทิ้งคีย์ที่ค้างไว้
  /// session เดิม (ถ้ามี) จะยังใช้งานได้ต่อ ไม่ถูกแตะต้อง
  void rejectNewKey(String peerId) {
    _pendingUntrustedHandshakes.remove(peerId);
  }

  bool hasSession(String peerId) => _sessionKeys.containsKey(peerId);

  // ---------------------------------------------------------------------------
  // Mesh routing message signing (Ed25519) — ป้องกัน route/identity spoofing
  // ---------------------------------------------------------------------------

  /// Public key (base64) สำหรับใส่ในข้อความ mesh ที่เราเป็นผู้สร้าง (originator)
  Future<String> meshSigningPubKeyB64() async {
    final pub = await _mySigningKeyPair!.extractPublicKey();
    return base64Encode(pub.bytes);
  }

  /// เซ็น [canonicalData] ด้วยคีย์เซ็นของเราเอง คืนค่า signature แบบ base64
  Future<String> signMeshMessage(String canonicalData) async {
    final sig = await _ed25519.sign(
      utf8.encode(canonicalData),
      keyPair: _mySigningKeyPair!,
    );
    return base64Encode(sig.bytes);
  }

  /// ตรวจสอบข้อความ mesh ที่อ้างว่ามาจาก [fromDeviceId]:
  /// 1. TOFU-bind public key เข้ากับ deviceId ครั้งแรกที่เจอ
  /// 2. ถ้า deviceId เดิมส่ง public key อื่นมา (ปลอมตัว) → ปฏิเสธทันที
  /// 3. ตรวจลายเซ็นต่อ [canonicalData] จริงด้วย public key ที่ trust ไว้
  Future<bool> verifyMeshMessage(
    String fromDeviceId,
    String canonicalData,
    String? pubKeyB64,
    String? sigB64,
  ) async {
    if (pubKeyB64 == null ||
        sigB64 == null ||
        pubKeyB64.isEmpty ||
        sigB64.isEmpty) {
      return false;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedPubKeyB64 = prefs.getString(
        '$_trustedSignKeyPrefix$fromDeviceId',
      );

      if (storedPubKeyB64 == null) {
        await prefs.setString('$_trustedSignKeyPrefix$fromDeviceId', pubKeyB64);
      } else if (storedPubKeyB64 != pubKeyB64) {
        Log.d(
          '[E2EE] ❌ Mesh signing key mismatch สำหรับ $fromDeviceId — ปฏิเสธข้อความ (อาจถูกปลอมตัว)',
        );
        return false;
      }

      final signature = Signature(
        base64Decode(sigB64),
        publicKey: SimplePublicKey(
          base64Decode(pubKeyB64),
          type: KeyPairType.ed25519,
        ),
      );
      return await _ed25519.verify(
        utf8.encode(canonicalData),
        signature: signature,
      );
    } catch (e) {
      Log.d('[E2EE] Mesh signature verify error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Encrypt / Decrypt
  // ---------------------------------------------------------------------------

  /// Encrypt [plaintext] for [peerId].
  /// Returns `ENC:<nonce_b64>:<ciphertext+mac_b64>`.
  /// Throws [StateError] if no session key exists for this peer.
  Future<String> encrypt(String plaintext, String peerId) async {
    final key = _sessionKeys[peerId];
    if (key == null) throw StateError('[E2EE] No session key for $peerId');

    final nonce = _aesGcm.newNonce();
    final box = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );

    final nonceB64 = base64Encode(box.nonce);
    final dataB64 = base64Encode([...box.cipherText, ...box.mac.bytes]);
    return 'ENC:$nonceB64:$dataB64';
  }

  /// Decrypt a message body.
  /// If [body] starts with `ENC:` and we have a session key for [peerId],
  /// returns the plaintext. Otherwise returns [body] unchanged (graceful fallback).
  Future<String> decrypt(String body, String peerId) async {
    if (!body.startsWith('ENC:')) return body;

    final key = _sessionKeys[peerId];
    if (key == null) {
      Log.d('[E2EE] No session key for $peerId — returning ciphertext as-is');
      return body;
    }

    try {
      final parts = body.split(':');
      if (parts.length < 3) return body;

      final nonce = base64Decode(parts[1]);
      // parts[2] may contain '=' padding — rejoin in case body had extra colons
      final data = base64Decode(parts.sublist(2).join(':'));

      // AES-GCM MAC is always 16 bytes
      if (data.length < 16) return body;
      final cipherText = data.sublist(0, data.length - 16);
      final mac = Mac(data.sublist(data.length - 16));

      final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
      final plainBytes = await _aesGcm.decrypt(secretBox, secretKey: key);
      return utf8.decode(plainBytes);
    } catch (e) {
      Log.d('[E2EE] Decrypt failed for $peerId: $e');
      return body;
    }
  }

  // ---------------------------------------------------------------------------
  // Session management
  // ---------------------------------------------------------------------------

  void clearSession(String peerId) {
    _sessionKeys.remove(peerId);
    _initiated.remove(peerId);
    _pendingEphemeralKeys.remove(peerId);
    _pendingUntrustedHandshakes.remove(peerId);
    Log.d('[E2EE] Cleared session for $peerId');
  }

  void dispose() {
    _sessionKeys.clear();
    _initiated.clear();
    _pendingEphemeralKeys.clear();
    _pendingUntrustedHandshakes.clear();
    _keyMismatchController.close();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// TOFU: on first contact store the identity key (trusted). On re-contact
  /// with a different identity key, emit a mismatch event — caller is
  /// responsible for stashing the pending handshake and NOT deriving/
  /// overwriting the session key until the user calls [acceptNewKey].
  /// Returns true if the incoming key is trusted (safe to derive a session key).
  Future<bool> _checkAndStoreTrustedKey(
    String peerId,
    String incomingB64,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final storedB64 = prefs.getString('$_trustedKeyPrefix$peerId');

    if (storedB64 == null) {
      await prefs.setString('$_trustedKeyPrefix$peerId', incomingB64);
      Log.d('[E2EE] TOFU: stored trusted key for $peerId');
      return true;
    }

    if (storedB64 != incomingB64) {
      Log.d(
        '[E2EE] ⚠️ Key mismatch for $peerId — key changed since last session',
      );
      _keyMismatchController.add(peerId);
      return false;
    }

    return true;
  }

  Future<List<int>> _pubKeyBytes() async {
    final pub = await _myKeyPair!.extractPublicKey();
    return pub.bytes;
  }

  SimplePublicKey _parsePublicKey(String b64) {
    return SimplePublicKey(base64Decode(b64), type: KeyPairType.x25519);
  }

  /// X3DH-lite: รวม ECDH 4 เทอม (identity×identity, ephemeral×ephemeral,
  /// และ cross term ทั้งสองทาง) เป็น key material เดียวก่อนเข้า HKDF
  /// cross term ทั้งสองต้องเรียง byte order ให้เหมือนกันทั้งสองฝั่ง (ไม่งั้น initiator
  /// กับ responder จะคำนวณ session key ไม่ตรงกัน เพราะแต่ละฝั่งได้ค่าเดียวกันแต่คนละเทอม)
  Future<SecretKey> _deriveSessionKeyX3DH({
    required SimpleKeyPair myEphemeral,
    required SimplePublicKey theirIdentity,
    required SimplePublicKey theirEphemeral,
  }) async {
    final myIdentity = _myKeyPair!;

    final identityIdentity = await _x25519.sharedSecretKey(
      keyPair: myIdentity,
      remotePublicKey: theirIdentity,
    );
    final ephemeralEphemeral = await _x25519.sharedSecretKey(
      keyPair: myEphemeral,
      remotePublicKey: theirEphemeral,
    );
    final crossA = await _x25519.sharedSecretKey(
      keyPair: myIdentity,
      remotePublicKey: theirEphemeral,
    );
    final crossB = await _x25519.sharedSecretKey(
      keyPair: myEphemeral,
      remotePublicKey: theirIdentity,
    );

    final iiBytes = await identityIdentity.extractBytes();
    final eeBytes = await ephemeralEphemeral.extractBytes();
    final crossABytes = await crossA.extractBytes();
    final crossBBytes = await crossB.extractBytes();

    final crossSorted = _compareBytes(crossABytes, crossBBytes) <= 0
        ? [...crossABytes, ...crossBBytes]
        : [...crossBBytes, ...crossABytes];

    final combined = SecretKeyData([...iiBytes, ...eeBytes, ...crossSorted]);

    return _hkdf.deriveKey(
      secretKey: combined,
      nonce: utf8.encode('offgrid-sos-v2-x3dh'),
      info: utf8.encode('chat-e2ee'),
    );
  }

  int _compareBytes(List<int> a, List<int> b) {
    final len = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }
}

/// handshake ที่ identity key ของ peer ไม่ตรงกับที่ trust ไว้ — เก็บทุกอย่างที่ต้องใช้
/// derive session key รอ user ยืนยันผ่าน [E2EEService.acceptNewKey]
class _PendingHandshake {
  final SimpleKeyPair myEphemeral;
  final String theirIdentityB64;
  final String theirEphemeralB64;

  _PendingHandshake({
    required this.myEphemeral,
    required this.theirIdentityB64,
    required this.theirEphemeralB64,
  });
}

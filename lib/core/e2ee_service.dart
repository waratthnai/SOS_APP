import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger.dart';

/// End-to-End Encryption service using X25519 key agreement + AES-256-GCM.
///
/// Protocol:
///   Initiator → Responder : `E2E_HELLO:<base64_pubkey>`
///   Responder → Initiator : `E2E_ACK:<base64_pubkey>`
///   After handshake       : `ENC:<base64_nonce>:<base64_ciphertext+mac>`
///
/// Session keys live in memory only — cleared on app restart.
/// Private key seed is persisted in SharedPreferences so our public key
/// stays stable across sessions (peer can cache our identity key).
class E2EEService {
  static const _prefKey = 'e2ee_seed_v1';
  static const _trustedKeyPrefix = 'e2ee_trusted_v1_';

  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  SimpleKeyPair? _myKeyPair;
  final Map<String, SecretKey> _sessionKeys = {};
  final Set<String> _initiated = {};

  // Emits peerId when a peer reconnects with a different public key than stored.
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

    final pubBytes = await _pubKeyBytes();
    await send('E2E_HELLO:${base64Encode(pubBytes)}');
    Log.d('[E2EE] Sent HELLO to $peerId');
  }

  /// Process an incoming E2EE protocol message.
  /// Returns true if the message was consumed (caller should not process further).
  Future<bool> handleMessage(
    String fromPeerId,
    String body,
    Future<void> Function(String body) send,
  ) async {
    if (body.startsWith('E2E_HELLO:')) {
      final keyB64 = body.substring('E2E_HELLO:'.length);
      await _checkAndStoreTrustedKey(fromPeerId, keyB64);
      final theirPubKey = _parsePublicKey(keyB64);
      _sessionKeys[fromPeerId] = await _deriveKey(theirPubKey);
      Log.d('[E2EE] Handshake HELLO from $fromPeerId — session established');

      // Always respond with our public key so the initiator can derive the key too.
      final pubBytes = await _pubKeyBytes();
      await send('E2E_ACK:${base64Encode(pubBytes)}');
      return true;
    }

    if (body.startsWith('E2E_ACK:')) {
      if (!_sessionKeys.containsKey(fromPeerId)) {
        final keyB64 = body.substring('E2E_ACK:'.length);
        await _checkAndStoreTrustedKey(fromPeerId, keyB64);
        final theirPubKey = _parsePublicKey(keyB64);
        _sessionKeys[fromPeerId] = await _deriveKey(theirPubKey);
        Log.d('[E2EE] Handshake ACK from $fromPeerId — session established');
      }
      return true;
    }

    return false;
  }

  bool hasSession(String peerId) => _sessionKeys.containsKey(peerId);

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
    Log.d('[E2EE] Cleared session for $peerId');
  }

  void dispose() {
    _sessionKeys.clear();
    _initiated.clear();
    _keyMismatchController.close();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// TOFU: on first contact store the key; on re-contact emit mismatch if key changed.
  Future<void> _checkAndStoreTrustedKey(String peerId, String incomingB64) async {
    final prefs = await SharedPreferences.getInstance();
    final storedB64 = prefs.getString('$_trustedKeyPrefix$peerId');

    if (storedB64 == null) {
      await prefs.setString('$_trustedKeyPrefix$peerId', incomingB64);
      Log.d('[E2EE] TOFU: stored trusted key for $peerId');
      return;
    }

    if (storedB64 != incomingB64) {
      Log.d('[E2EE] ⚠️ Key mismatch for $peerId — key changed since last session');
      _keyMismatchController.add(peerId);
    }
  }

  Future<List<int>> _pubKeyBytes() async {
    final pub = await _myKeyPair!.extractPublicKey();
    return pub.bytes;
  }

  SimplePublicKey _parsePublicKey(String b64) {
    return SimplePublicKey(base64Decode(b64), type: KeyPairType.x25519);
  }

  Future<SecretKey> _deriveKey(SimplePublicKey theirPublicKey) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: _myKeyPair!,
      remotePublicKey: theirPublicKey,
    );
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('offgrid-sos-v1'),
      info: utf8.encode('chat-e2ee'),
    );
  }
}

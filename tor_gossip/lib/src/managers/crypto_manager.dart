import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:hex/hex.dart';
import '../envelopes/gossip_envelope.dart';

class CryptoManager {
  final _algorithm = Ed25519();
  SimpleKeyPair? _keyPair;

  /// Initialize with a new random keypair.
  /// In a production app, you should load this from SecureStorage!
  Future<void> init() async {
    _keyPair = await _algorithm.newKeyPair();
  }

  /// Returns our public key as a hex string
  Future<String> get publicKeyHex async {
    if (_keyPair == null) throw Exception("CryptoManager not initialized");
    final pub = await _keyPair!.extractPublicKey();
    return const HexEncoder().convert(pub.bytes);
  }

  /// Signs the core fields of an envelope (id + topic + payload + timestamp)
  Future<String> sign(String id, String topic, String payload, int timestamp) async {
    if (_keyPair == null) throw Exception("CryptoManager not initialized");

    // We sign the concatenation of the fields to ensure integrity
    final data = utf8.encode('$id$topic$payload$timestamp');
    final signature = await _algorithm.sign(data, keyPair: _keyPair!);

    return const HexEncoder().convert(signature.bytes);
  }

  /// Verifies that the signature matches the content and the public key
  Future<bool> verify(GossipEnvelope envelope) async {
    try {
      final data = utf8.encode(
        '${envelope.id}${envelope.topic}${envelope.payload}${envelope.timestamp}'
      );

      final pubKeyBytes = const HexDecoder().convert(envelope.senderPub);
      final sigBytes = const HexDecoder().convert(envelope.signature);

      final pubKey = SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519);
      final signature = Signature(sigBytes, publicKey: pubKey);

      return await _algorithm.verify(data, signature: signature);
    } catch (e) {
      print("🔐 Crypto Verify Error: $e");
      return false;
    }
  }
}
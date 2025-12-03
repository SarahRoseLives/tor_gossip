import 'dart:convert';

class GossipEnvelope {
  /// Unique ID (UUID v4)
  final String id;

  /// The .onion address of the sender (Return Address)
  final String origin;

  /// The channel this message belongs to
  final String topic;

  /// The actual data
  final String payload;

  /// Timestamp (ms epoch)
  final int timestamp;

  /// NEW: The sender's Ed25519 Public Key (Hex)
  final String senderPub;

  /// NEW: The Ed25519 Signature of the message content (Hex)
  final String signature;

  GossipEnvelope({
    required this.id,
    required this.origin,
    required this.topic,
    required this.payload,
    required this.timestamp,
    required this.senderPub,
    required this.signature,
  });

  factory GossipEnvelope.fromJson(Map<String, dynamic> json) {
    return GossipEnvelope(
      id: json['id'] as String,
      origin: json['origin'] as String,
      topic: json['topic'] as String,
      payload: json['payload'] as String,
      timestamp: json['timestamp'] as int,
      senderPub: json['senderPub'] as String? ?? '', // Fallback for old msgs
      signature: json['signature'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'origin': origin,
      'topic': topic,
      'payload': payload,
      'timestamp': timestamp,
      'senderPub': senderPub,
      'signature': signature,
    };
  }

  String toRawJson() => jsonEncode(toJson());

  factory GossipEnvelope.fromRawJson(String str) =>
      GossipEnvelope.fromJson(jsonDecode(str));
}
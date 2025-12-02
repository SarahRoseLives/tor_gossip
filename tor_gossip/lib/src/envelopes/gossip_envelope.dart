import 'dart:convert';

class GossipEnvelope {
  /// Unique ID (UUID v4) to prevent processing the same message twice.
  final String id;

  /// The .onion address of the sender (the "Return Address").
  final String origin;

  /// The channel this message belongs to (e.g., 'chat', 'bitcoin_tx').
  /// This allows you to run multiple apps on one gossip network.
  final String topic;

  /// The actual data. We store it as a String.
  /// Complex objects should be JSON-encoded before sending.
  final String payload;

  /// When this message was created (milliseconds since epoch).
  final int timestamp;

  GossipEnvelope({
    required this.id,
    required this.origin,
    required this.topic,
    required this.payload,
    required this.timestamp,
  });

  /// Factory to create a clean envelope from a JSON map (Incoming data)
  factory GossipEnvelope.fromJson(Map<String, dynamic> json) {
    return GossipEnvelope(
      id: json['id'] as String,
      origin: json['origin'] as String,
      topic: json['topic'] as String,
      payload: json['payload'] as String,
      timestamp: json['timestamp'] as int,
    );
  }

  /// Convert to JSON map for sending over the network (Outgoing data)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'origin': origin,
      'topic': topic,
      'payload': payload,
      'timestamp': timestamp,
    };
  }

  /// Helper to convert the whole object to a string for HTTP bodies
  String toRawJson() => jsonEncode(toJson());

  /// Helper to create from a raw string
  factory GossipEnvelope.fromRawJson(String str) =>
      GossipEnvelope.fromJson(jsonDecode(str));
}
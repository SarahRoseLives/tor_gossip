# Tor Gossip

A Dart library for decentralized, peer-to-peer gossip messaging over Tor hidden service addresses. Build censorship-resistant messaging and network-discovery tools on top of the Tor network.

## Features

- **Gossip Protocol**: Efficient fanout-based gossip; messages propagate to random subsets of peers.
- **Tor Native Integration**: Uses [tor_hidden_service](https://pub.dev/packages/tor_hidden_service) for onion address bootstrapping and HTTP hidden service exposure.
- **Cryptographic Message Envelope**: All messages are signed (Ed25519), origin-authenticated, and deduplicated.
- **Peer Discovery**: Dynamically discovers, validates, and prunes onion address peers.
- **Deduplication**: No repeated processing of already seen messages.
- **Easy Integration**: Just `publish` messages and the network will do the rest!

## Quick Start

### 1. Add the Dependency

```yaml
dependencies:
  tor_gossip: ^0.1.0
```

### 2. Import and Initialize

```dart
import 'package:tor_gossip/tor_gossip.dart';

final node = TorGossipNode(bootstrapPeers: [
  // Optionally add well-known .onion addresses here
]);

await node.start();
```

### 3. Send Messages

```dart
await node.publish("chat", "Hello, Tor world!");
```

### 4. Listen for Messages

```dart
node.onMessage.listen((GossipEnvelope envelope) {
  print('Received message: ${envelope.payload} from ${envelope.origin}');
});
```

### 5. Add Peers (Manually or via Gossip)

```dart
await node.pingPeer('exampleonionaddress.onion'); // Accepts .onion or http(s):// address
```

## Example Flutter App

The included `/example` directory contains a complete Flutter app for demo and testing:

- Scan and display your onion address as QR code.
- Scan peer QR addresses.
- Send and receive gossip messages.
- Auto-discovery of active peers.
- Live logs of all gossip activity.

> Launchable via `flutter run example/lib/main.dart` (requires [tor_hidden_service](https://pub.dev/packages/tor_hidden_service) native setup).

**Main widgets:**
- `GossipTestScreen` — Gossip test UI (chat, peers, logs)
- `QrScanScreen` — Scan a peer's onion address via QR

## Library Structure

```
lib/
  tor_gossip.dart              # Library entrypoint and exports
  src/
    tor_gossip_node.dart       # Main engine: networking, gossip routing, API
    envelopes/gossip_envelope.dart   # Message model: id, origin, topic, signature, payload
    managers/crypto_manager.dart     # Ed25519 signing & verification
    managers/dedup_manager.dart      # Message deduplication
    managers/peer_manager.dart       # Peer validation & management
    transport/tor_server.dart        # Shelf server for Tor traffic
example/                          # Example demo Flutter app
test/                             # Unit and widget tests
```

## API Overview

### `TorGossipNode`

- `start()` — Bootstraps Tor, initializes cryptography and the server.
- `publish(topic, payload)` — Publishes a signed message to the network.
- `pingPeer(onionAddress)` — Adds a peer and sends handshake gossip.
- `onMessage` — Stream of validated incoming messages.
- `onLog` — Stream of diagnostic logs.
- `knownPeers` — List of currently discovered peers.
- `onionAddress` — This node's Tor onion address.

### `GossipEnvelope`

Signed message object returned in `onMessage`/used for publishing.

| Field       | Type      | Description                             |
|-------------|-----------|-----------------------------------------|
| id          | String    | UUID4 of the message                    |
| origin      | String    | Sender's .onion address                 |
| topic       | String    | Message topic/channel                   |
| payload     | String    | Message data                            |
| timestamp   | int       | Epoch ms timestamp                      |
| senderPub   | String    | Sender's Ed25519 public key (hex)       |
| signature   | String    | Ed25519 signature (hex)                 |

### Example: Custom Network Integration

You can plug TorGossipNode into any Dart/Flutter app. See `lib/tor_gossip.dart` for exports.

## Security Notes

- All outbound gossip traffic is signed and verified with Ed25519 keys.
- Peer management drops nodes that fail or send invalid traffic.
- Does **not** store private keys outside memory (configure for long-term durability as needed).
- Designed for ephemeral/memory-only peer and key management; production usage may want to secure keys.

## Running Tests

```
flutter test
```
Or for logic tests:
```
dart test
```

## Dependencies

- [tor_hidden_service](https://pub.dev/packages/tor_hidden_service) *(Tor integration)*
- [cryptography](https://pub.dev/packages/cryptography) *(Ed25519 signing)*
- [shelf](https://pub.dev/packages/shelf), [shelf_router](https://pub.dev/packages/shelf_router) *(Local HTTP server)*
- [uuid](https://pub.dev/packages/uuid), [hex](https://pub.dev/packages/hex) *(Utility)*

## FAQ

- **Can I use this in production?**  
  This is an experimental library intended for research, prototype, and educational use. Review, extend, and audit the security as needed.

- **Does it work on mobile (Flutter Android/iOS)?**  
  Yes—but requires configuring Tor native libraries (see [tor_hidden_service](https://pub.dev/packages/tor_hidden_service)).

- **How do I add static peers to bootstrap the gossip network?**  
  Pass their onion addresses in `bootstrapPeers`, or via the UI in the example app.

## Contribution & License

Pull requests welcome! See `test/` for guidelines.  
Licensed under the MIT License.

---

**Tor Gossip** is maintained by [SarahRoseLives](https://github.com/SarahRoseLives).
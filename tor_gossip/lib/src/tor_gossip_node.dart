import 'dart:async';
import 'package:tor_hidden_service/tor_hidden_service.dart';
import 'package:uuid/uuid.dart';

import 'envelopes/gossip_envelope.dart';
import 'managers/dedup_manager.dart';
import 'managers/peer_manager.dart';
import 'managers/crypto_manager.dart'; // Import the new manager
import 'transport/tor_server.dart';

class TorGossipNode {
  final TorHiddenService _tor = TorHiddenService();
  final PeerManager _peerManager;
  final DedupManager _dedupManager = DedupManager();
  final CryptoManager _cryptoManager = CryptoManager(); // New
  final TorServer _server = TorServer();
  final Uuid _uuid = const Uuid();

  late TorOnionClient _onionClient;

  String? _myOnionAddress;
  bool _isStarted = false;
  final int _port;

  final StreamController<GossipEnvelope> _msgController =
      StreamController.broadcast();
  final StreamController<String> _logController = StreamController.broadcast();

  Stream<GossipEnvelope> get onMessage => _msgController.stream;
  Stream<String> get onLog => _logController.stream;
  String? get onionAddress => _myOnionAddress;
  List<String> get knownPeers => _peerManager.getAllPeers();

  TorGossipNode({
    int port = 8080,
    List<String> bootstrapPeers = const [],
  })  : _port = port,
        _peerManager = PeerManager(bootstrapPeers: bootstrapPeers) {
    _server.onMessageReceived = _handleIncomingMessage;
    _onionClient = _tor.getUnsecureTorClient();
  }

  Future<void> start() async {
    if (_isStarted) return;
    _log("🚀 Starting Tor Gossip Node...");

    // 1. Init Crypto
    await _cryptoManager.init();
    _log("🔐 Crypto Initialized.");

    // 2. Start Tor
    _tor.onLog.listen((log) => _log("TOR: $log"));
    await _tor.start();
    _log("✅ Tor Bootstrapped.");

    _myOnionAddress = await _tor.getOnionHostname();
    if (_myOnionAddress == null) throw Exception("Failed to get Onion Hostname");
    _log("🧅 My Address: $_myOnionAddress");

    // 3. Start Server
    await _server.start(_port);

    _isStarted = true;
  }

  Future<void> stop() async {
    await _server.stop();
    await _tor.stop();
    _isStarted = false;
    _log("🛑 Node Stopped.");
  }

  Future<void> publish(String topic, String payload) async {
    if (!_isStarted) throw Exception("Node not started");

    final id = _uuid.v4();
    final ts = DateTime.now().millisecondsSinceEpoch;

    // Sign the message
    final sig = await _cryptoManager.sign(id, topic, payload, ts);
    final myPub = await _cryptoManager.publicKeyHex;

    final envelope = GossipEnvelope(
      id: id,
      origin: _myOnionAddress!,
      topic: topic,
      payload: payload,
      timestamp: ts,
      senderPub: myPub,
      signature: sig,
    );

    _dedupManager.markSeen(envelope.id);
    _gossipToPeers(envelope);
  }

  Future<void> pingPeer(String peerOnion) async {
    if (!_isStarted) throw Exception("Node not started");

    _peerManager.addPeer(peerOnion);

    final id = _uuid.v4();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final topic = 'handshake';
    final payload = '';

    // Sign the ping too!
    final sig = await _cryptoManager.sign(id, topic, payload, ts);
    final myPub = await _cryptoManager.publicKeyHex;

    final envelope = GossipEnvelope(
      id: id,
      origin: _myOnionAddress!,
      topic: topic,
      payload: payload,
      timestamp: ts,
      senderPub: myPub,
      signature: sig,
    );

    _log("👋 Pinging peer $peerOnion...");
    await _sendToPeer(peerOnion, envelope);
  }

  Future<void> _handleIncomingMessage(GossipEnvelope envelope) async {
    if (_dedupManager.isDuplicate(envelope.id)) return;

    // 1. VERIFY SIGNATURE BEFORE PROCESSING
    final isValid = await _cryptoManager.verify(envelope);
    if (!isValid) {
      _log("⛔ Rejected forged message from ${envelope.origin}");
      return;
    }

    _dedupManager.markSeen(envelope.id);

    if (envelope.origin != _myOnionAddress) {
      bool isNew = _peerManager.addPeer(envelope.origin);
      if (isNew) _log("👋 Discovered new peer from message: ${envelope.origin}");
    }

    if (envelope.topic != 'handshake') {
      _msgController.add(envelope);
    } else {
      _log("🤝 Valid Handshake from ${envelope.origin.substring(0, 6)}...");
    }

    _gossipToPeers(envelope);
  }

  Future<void> _gossipToPeers(GossipEnvelope envelope) async {
    if (!_isStarted) return;
    final targets = _peerManager.getRandomPeers(3, exclude: {envelope.origin, _myOnionAddress ?? ''});
    if (targets.isEmpty) return;

    _log("✨ Gossiping msg ${envelope.id.substring(0, 4)} to ${targets.length} peers...");
    for (var peer in targets) {
      // Use unawaited to fire and forget
      _sendToPeer(peer, envelope).catchError((e) {
         // silent catch for fanout errors
      });
    }
  }

  Future<void> _sendToPeer(String peerOnion, GossipEnvelope envelope,
      {int retryCount = 0}) async {
    if (!_isStarted) return;
    if (retryCount >= 3) {
      _peerManager.reportFailure(peerOnion);
      _log("❌ Failed to reach $peerOnion after 3 retries.");
      return;
    }

    final cleanHost = _peerManager.sanitizeOnion(peerOnion);
    if (cleanHost == null) return;

    final url = 'http://$cleanHost/gossip';

    try {
      final response = await _onionClient.post(
        url,
        body: envelope.toRawJson(),
        headers: {
          'Content-Type': 'application/json',
          'Host': cleanHost,
        },
      );

      if (response.statusCode == 200) {
        _peerManager.reportSuccess(cleanHost);
        _log("✅ Sent to $cleanHost (200).");
      } else {
        _log("⚠️ Peer $cleanHost returned ${response.statusCode}.");
        await Future.delayed(const Duration(seconds: 5));
        await _sendToPeer(cleanHost, envelope, retryCount: retryCount + 1);
      }
    } catch (e) {
      _log("❌ Error sending to $cleanHost: $e");
      await Future.delayed(const Duration(seconds: 5));
      await _sendToPeer(cleanHost, envelope, retryCount: retryCount + 1);
    }
  }

  void addPeer(String onionAddress) {
    if (_peerManager.addPeer(onionAddress)) {
      _log("➕ Manually added peer: $onionAddress");
    }
  }

  void _log(String msg) {
    if (!_logController.isClosed) _logController.add(msg);
    print("[TorGossip] $msg");
  }
}
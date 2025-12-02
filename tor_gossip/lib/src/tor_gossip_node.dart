import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:tor_hidden_service/tor_hidden_service.dart';
import 'package:uuid/uuid.dart';

import 'envelopes/gossip_envelope.dart';
import 'managers/dedup_manager.dart';
import 'managers/peer_manager.dart';
import 'transport/tor_server.dart';

class TorGossipNode {
  final TorHiddenService _tor = TorHiddenService();
  final PeerManager _peerManager;
  final DedupManager _dedupManager = DedupManager();
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

  // 🌟 NEW: Expose the list of known peers to the UI
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
    _tor.onLog.listen((log) => _log("TOR: $log"));
    await _tor.start();
    _log("✅ Tor Bootstrapped.");

    _myOnionAddress = await _tor.getOnionHostname();
    if (_myOnionAddress == null) throw Exception("Failed to get Onion Hostname");
    _log("🧅 My Address: $_myOnionAddress");

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

    final envelope = GossipEnvelope(
      id: _uuid.v4(),
      origin: _myOnionAddress!,
      topic: topic,
      payload: payload,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    _dedupManager.markSeen(envelope.id);
    _gossipToPeers(envelope);
  }

  void addPeer(String onionAddress) {
    if (_peerManager.addPeer(onionAddress)) {
      _log("➕ Manually added peer: $onionAddress");
    }
  }

  Future<void> pingPeer(String peerOnion) async {
    if (!_isStarted) throw Exception("Node not started");

    _peerManager.addPeer(peerOnion);

    final envelope = GossipEnvelope(
      id: _uuid.v4(),
      origin: _myOnionAddress!,
      topic: 'handshake',
      payload: '',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    _log("👋 Pinging peer $peerOnion...");
    await _sendToPeer(peerOnion, envelope);
  }

  void _handleIncomingMessage(GossipEnvelope envelope) {
    if (_dedupManager.isDuplicate(envelope.id)) return;
    _dedupManager.markSeen(envelope.id);

    if (envelope.origin != _myOnionAddress) {
      bool isNew = _peerManager.addPeer(envelope.origin);
      if (isNew) _log("👋 Discovered new peer from message: ${envelope.origin}");
    }

    if (envelope.topic != 'handshake') {
      _msgController.add(envelope);
    } else {
      _log("🤝 Received Handshake Ping from ${envelope.origin.substring(0, 6)}...");
    }

    _gossipToPeers(envelope);
  }

  Future<void> _gossipToPeers(GossipEnvelope envelope) async {
    if (!_isStarted) return;
    final targets = _peerManager.getRandomPeers(3, exclude: {envelope.origin, _myOnionAddress ?? ''});
    if (targets.isEmpty) return; // Silent return to reduce log spam

    _log("✨ Gossiping msg ${envelope.id.substring(0, 4)} to ${targets.length} peers...");
    for (var peer in targets) {
      unawaited(_sendToPeer(peer, envelope));
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

    // Use http:// scheme for the new Client
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

  void _log(String msg) {
    if (!_logController.isClosed) _logController.add(msg);
    print("[TorGossip] $msg");
  }
}

void unawaited(Future<void> f) {}
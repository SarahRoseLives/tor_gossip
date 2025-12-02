import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tor_hidden_service/tor_hidden_service.dart';
import 'package:uuid/uuid.dart';

import 'envelopes/gossip_envelope.dart';
import 'managers/dedup_manager.dart';
import 'managers/peer_manager.dart';
import 'transport/tor_server.dart';

class TorGossipNode {
  // --- Components ---
  final TorHiddenService _tor = TorHiddenService();
  final PeerManager _peerManager;
  final DedupManager _dedupManager = DedupManager();

  // FIXED: Initialize without arguments. We assign the listener in the constructor.
  final TorServer _server = TorServer();

  final Uuid _uuid = const Uuid();

  // --- State ---
  String? _myOnionAddress;
  HttpClient? _torClient;
  bool _isStarted = false;
  final int _port;

  // --- Public Events ---
  final StreamController<GossipEnvelope> _msgController = StreamController.broadcast();
  final StreamController<String> _logController = StreamController.broadcast();

  /// Stream of incoming messages for the UI to listen to.
  Stream<GossipEnvelope> get onMessage => _msgController.stream;

  /// Stream of internal logs (Tor boot progress, errors, etc).
  Stream<String> get onLog => _logController.stream;

  /// Your generated Onion address (null until started).
  String? get onionAddress => _myOnionAddress;

  TorGossipNode({
    int port = 8080,
    List<String> bootstrapPeers = const [],
  })  : _port = port,
        _peerManager = PeerManager(bootstrapPeers: bootstrapPeers) {

    // FIXED: Assign the callback here, connecting the Server to the Engine.
    _server.onMessageReceived = _handleIncomingMessage;
  }

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  Future<void> start() async {
    if (_isStarted) return;
    _log("🚀 Starting Tor Gossip Node...");

    // 1. Listen to Tor Logs
    _tor.onLog.listen((log) => _log("TOR: $log"));

    // 2. Start Tor
    await _tor.start();
    _log("✅ Tor Bootstrapped.");

    // 3. Get our Address
    _myOnionAddress = await _tor.getOnionHostname();
    if (_myOnionAddress == null) throw Exception("Failed to get Onion Hostname");
    _log("🧅 My Address: $_myOnionAddress");

    // 4. Start Local Listener
    await _server.start(_port);

    // 5. Create the Outbound Client
    // We must trust bad certificates because Onion addresses use self-signed logic internally
    _torClient = _tor.getTorHttpClient();
    _torClient!.badCertificateCallback = (cert, host, port) => true;
    _torClient!.connectionTimeout = const Duration(seconds: 20);

    _isStarted = true;
  }

  Future<void> stop() async {
    await _server.stop();
    await _tor.stop();
    _isStarted = false;
    _log("🛑 Node Stopped.");
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  /// Sends a new message to the network.
  Future<void> publish(String topic, String payload) async {
    if (!_isStarted) throw Exception("Node not started");

    // 1. Create the envelope
    final envelope = GossipEnvelope(
      id: _uuid.v4(),
      origin: _myOnionAddress!,
      topic: topic,
      payload: payload,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    // 2. Mark as seen by us (so we don't process it if it echoes back)
    _dedupManager.markSeen(envelope.id);

    // 3. Gossip to peers
    _gossipToPeers(envelope);
  }

  /// Manually add a peer (Useful for testing/bootstrapping)
  void addPeer(String onionAddress) {
    if (_peerManager.addPeer(onionAddress)) {
      _log("➕ Manually added peer: $onionAddress");
    }
  }

  // ---------------------------------------------------------------------------
  // INTERNALS
  // ---------------------------------------------------------------------------

  /// The Core Logic: Processing a received envelope
  void _handleIncomingMessage(GossipEnvelope envelope) {
    // 1. Check Deduplication
    if (_dedupManager.isDuplicate(envelope.id)) {
      // We've seen this. Drop it.
      return;
    }

    // 2. Mark as seen
    _dedupManager.markSeen(envelope.id);

    // 3. Peer Discovery (Passive)
    // If we hear from a stranger, add them to our address book!
    if (envelope.origin != _myOnionAddress) {
      bool isNew = _peerManager.addPeer(envelope.origin);
      if (isNew) _log("👋 Discovered new peer from message: ${envelope.origin}");
    }

    // 4. Notify UI (The user needs to see this!)
    _msgController.add(envelope);

    // 5. Propagate (Rumor Mongering)
    // Forward this to other peers so the network stays in sync
    _gossipToPeers(envelope);
  }

  /// Sends the envelope to random peers (Fanout).
  Future<void> _gossipToPeers(GossipEnvelope envelope) async {
    if (_torClient == null) return;

    // 1. Pick 3 random peers (excluding the person who just sent it to us)
    final targets = _peerManager.getRandomPeers(3, exclude: {envelope.origin, _myOnionAddress ?? ''});

    if (targets.isEmpty) {
      _log("⚠️ No peers to gossip to.");
      return;
    }

    _log("✨ Gossiping msg ${envelope.id.substring(0, 4)} to ${targets.length} peers...");

    // 2. Fire and Forget (Don't await loop)
    for (var peer in targets) {
      _sendToPeer(peer, envelope);
    }
  }

  Future<void> _sendToPeer(String peerOnion, GossipEnvelope envelope) async {
    final url = Uri.parse("https://$peerOnion/gossip");

    try {
      final request = await _torClient!.postUrl(url);
      request.write(envelope.toRawJson());

      final response = await request.close();

      if (response.statusCode == 200) {
        _peerManager.reportSuccess(peerOnion);
      } else {
        _peerManager.reportFailure(peerOnion);
        _log("⚠️ Peer $peerOnion returned ${response.statusCode}");
      }
    } catch (e) {
      _peerManager.reportFailure(peerOnion);
      // Don't log verbose errors for timeouts, it's normal in Tor
      _log("❌ Failed to reach $peerOnion");
    }
  }

  void _log(String msg) {
    if (!_logController.isClosed) _logController.add(msg);
    print("[TorGossip] $msg");
  }
}
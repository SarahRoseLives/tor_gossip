import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tor_gossip/tor_gossip.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MaterialApp(
      home: GossipTestScreen(),
      debugShowCheckedModeBanner: false,
    ));

class GossipTestScreen extends StatefulWidget {
  const GossipTestScreen({super.key});

  @override
  State<GossipTestScreen> createState() => _GossipTestScreenState();
}

class _GossipTestScreenState extends State<GossipTestScreen> {
  final _node = TorGossipNode();

  // Controllers
  final _peerInputController = TextEditingController();
  final _msgInputController = TextEditingController();

  // State
  List<String> _logs = [];
  List<GossipEnvelope> _messages = [];
  List<String> _peers = [];
  bool _isReady = false;
  Timer? _peerRefreshTimer;

  @override
  void initState() {
    super.initState();

    // 1. Logs
    _node.onLog.listen((log) => setState(() => _logs.insert(0, log)));

    // 2. Messages
    _node.onMessage.listen((envelope) {
      setState(() {
        _logs.insert(0, "📩 MSG from ${envelope.origin.substring(0, 6)}...");
        _messages.insert(0, envelope);
        // Refresh peers when we get a message (discovery)
        _peers = _node.knownPeers;
      });
    });

    // 3. Periodic Peer Refresh (In case they are added via gossip)
    _peerRefreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_isReady) {
        setState(() => _peers = _node.knownPeers);
      }
    });

    // 4. Lifecycle cleanup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChannels.lifecycle.setMessageHandler((msg) {
        if (msg == AppLifecycleState.detached.toString() ||
            msg == AppLifecycleState.inactive.toString()) {
          _node.stop();
        }
        return Future.value(null);
      });
    });
  }

  @override
  void dispose() {
    _node.stop();
    _peerInputController.dispose();
    _msgInputController.dispose();
    _peerRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      await _node.start();
      setState(() {
        _isReady = true;
        _peers = _node.knownPeers;
      });
      _logs.insert(0, "✅ Node started. My onion: ${_node.onionAddress ?? 'unknown'}");
    } catch (e) {
      setState(() => _logs.insert(0, "❌ Error starting node: $e"));
    }
  }

  // --- Actions ---

  Future<void> _addAndPingPeer(String onionInput) async {
    var input = onionInput.trim();
    if (input.isEmpty) return;

    // Use http:// for the new client
    if (!input.startsWith('http')) {
      input = 'http://$input';
    }

    try {
      await _node.pingPeer(input);
      setState(() {
        _peerInputController.text = input;
        _peers = _node.knownPeers; // Update UI immediately
        _logs.insert(0, "➕ Added & pinged peer: ${input.replaceAll('http://', '')}");
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Peer added & pinged: ${input.substring(0, 15)}...")),
      );
    } catch (e) {
      setState(() => _logs.insert(0, "❌ Error pinging peer: $e"));
    }
  }

  void _onSendPressed() {
    final msg = _msgInputController.text.trim();
    if (msg.isEmpty) return;

    if (_peers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No peers to gossip to! Add one in the 'Peers' tab.")));
      return;
    }

    _node.publish("chat", msg);
    setState(() {
      _logs.insert(0, "📤 Published: $msg");
      _msgInputController.clear();
    });
  }

  Future<void> _scanQr() async {
    if (await Permission.camera.request().isGranted) {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const QrScanScreen()),
      );
      if (result != null && result is String) {
        _addAndPingPeer(result);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Camera permission required")));
    }
  }

  void _showMyQr() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: SizedBox(
          width: 250,
          height: 250,
          child: QrImageView(
            data: _node.onionAddress ?? "Error",
            version: QrVersions.auto,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _node.onionAddress ?? ""));
              Navigator.pop(context);
            },
            child: const Text("Copy Text"),
          )
        ],
      ),
    );
  }

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return Scaffold(
        appBar: AppBar(title: const Text("Tor Gossip Bootstrap")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 80, color: Colors.purple),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _start,
                child: const Text("BOOTSTRAP TOR NODE"),
              ),
              const SizedBox(height: 20),
              Expanded(child: _buildLogList()),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Tor Gossip Network"),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.chat), text: "Chat"),
              Tab(icon: Icon(Icons.people), text: "Peers"),
              Tab(icon: Icon(Icons.terminal), text: "Logs"),
            ],
          ),
          actions: [
            IconButton(icon: const Icon(Icons.qr_code), onPressed: _showMyQr),
          ],
        ),
        body: TabBarView(
          children: [
            _buildChatTab(),
            _buildPeersTab(),
            _buildLogList(),
          ],
        ),
      ),
    );
  }

  Widget _buildChatTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.green[50],
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("My Onion Address:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    SelectableText(
                      _node.onionAddress ?? "Unknown",
                      style: const TextStyle(fontSize: 12, fontFamily: 'Courier')
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final m = _messages[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(m.payload),
                  subtitle: Text("From: ${m.origin.substring(0, 15)}...", style: const TextStyle(fontSize: 10, fontFamily: 'Courier')),
                  trailing: Text(
                    DateTime.fromMillisecondsSinceEpoch(m.timestamp).toString().substring(11, 16),
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgInputController,
                  decoration: const InputDecoration(
                    labelText: "Broadcast Message",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.blue),
                iconSize: 32,
                onPressed: _onSendPressed,
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPeersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: _scanQr),
              Expanded(
                child: TextField(
                  controller: _peerInputController,
                  decoration: const InputDecoration(
                    labelText: "Add Peer (.onion)",
                    hintText: "Paste .onion address",
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_link, color: Colors.green),
                onPressed: () => _addAndPingPeer(_peerInputController.text),
              ),
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text("Active Peers (${_peers.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
          ),
        ),
        Expanded(
          child: _peers.isEmpty
              ? const Center(child: Text("No peers yet. Scan QR or Add manually."))
              : ListView.builder(
                  itemCount: _peers.length,
                  itemBuilder: (context, index) {
                    final peer = _peers[index];
                    return ListTile(
                      leading: const Icon(Icons.dns),
                      title: Text(peer, style: const TextStyle(fontFamily: 'Courier', fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.network_ping, size: 20, color: Colors.orange),
                        onPressed: () => _addAndPingPeer(peer),
                        tooltip: "Ping this peer",
                      ),
                      onTap: () {
                         Clipboard.setData(ClipboardData(text: peer));
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Address Copied")));
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLogList() {
    return Container(
      color: Colors.black,
      child: ListView.builder(
        itemCount: _logs.length,
        padding: const EdgeInsets.all(8),
        itemBuilder: (context, index) {
          return Text(
            _logs[index],
            style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'Courier'),
          );
        },
      ),
    );
  }
}

// --- Simple Scanner Screen ---
class QrScanScreen extends StatelessWidget {
  const QrScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan Peer QR")),
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              Navigator.pop(context, barcode.rawValue);
              break;
            }
          }
        },
      ),
    );
  }
}
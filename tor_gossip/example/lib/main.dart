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

// 1. Add WidgetsBindingObserver to properly handle lifecycle changes
class _GossipTestScreenState extends State<GossipTestScreen> with WidgetsBindingObserver {
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

  // 2. Track subscriptions so we can cancel them to prevent memory leaks
  StreamSubscription? _logSub;
  StreamSubscription? _msgSub;

  @override
  void initState() {
    super.initState();
    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // 3. Store subscriptions
    _logSub = _node.onLog.listen((log) {
      // 4. Check 'mounted' before calling setState
      if (mounted) {
        setState(() => _logs.insert(0, log));
      }
    });

    _msgSub = _node.onMessage.listen((envelope) {
      if (mounted) {
        setState(() {
          _logs.insert(0, "📩 MSG from ${envelope.origin.substring(0, 6)}...");
          _messages.insert(0, envelope);
          _peers = _node.knownPeers;
        });
      }
    });

    _peerRefreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_isReady && mounted) {
        setState(() => _peers = _node.knownPeers);
      }
    });
  }

  // 5. Proper Lifecycle Management
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ⚠️ CRITICAL FIX: Only stop Tor if the app is PAUSED (backgrounded) or DETACHED.
    // 'inactive' happens when you switch to the Camera/QR Scanner or ask for permissions.
    // If we stop on 'inactive', the node dies while you are scanning.
    if (state == AppLifecycleState.detached) {
      _node.stop();
    }
  }

  @override
  void dispose() {
    // 6. Clean up everything
    WidgetsBinding.instance.removeObserver(this);
    _logSub?.cancel();
    _msgSub?.cancel();
    _peerRefreshTimer?.cancel();
    _peerInputController.dispose();
    _msgInputController.dispose();
    _node.stop();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      await _node.start();
      if (mounted) {
        setState(() {
          _isReady = true;
          _peers = _node.knownPeers;
        });
        _logs.insert(0, "✅ Node started. My onion: ${_node.onionAddress ?? 'unknown'}");
      }
    } catch (e) {
      if (mounted) setState(() => _logs.insert(0, "❌ Error starting node: $e"));
    }
  }

  // --- Actions ---

  Future<void> _addAndPingPeer(String onionInput) async {
    var input = onionInput.trim();
    if (input.isEmpty) return;

    if (!input.startsWith('http')) {
      input = 'http://$input';
    }

    try {
      // Don't await the ping blocking the UI, let it happen
      await _node.pingPeer(input);

      if (mounted) {
        setState(() {
          _peerInputController.text = input;
          _peers = _node.knownPeers;
          _logs.insert(0, "➕ Added & pinged peer: ${input.replaceAll('http://', '')}");
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Peer added & pinged: ${input.substring(0, 15)}...")),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _logs.insert(0, "❌ Error pinging peer: $e"));
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
    if (mounted) {
      setState(() {
        _logs.insert(0, "📤 Published: $msg");
        _msgInputController.clear();
      });
    }
  }

  Future<void> _scanQr() async {
    // Permission request might trigger 'AppLifecycleState.inactive'
    if (await Permission.camera.request().isGranted) {
      if (!mounted) return;

      final result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const QrScanScreen()),
      );

      if (result != null && result is String) {
        _addAndPingPeer(result);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Camera permission required")));
      }
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
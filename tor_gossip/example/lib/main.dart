import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tor_gossip/tor_gossip.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MaterialApp(home: GossipTestScreen()));

class GossipTestScreen extends StatefulWidget {
  const GossipTestScreen({super.key});

  @override
  State<GossipTestScreen> createState() => _GossipTestScreenState();
}

class _GossipTestScreenState extends State<GossipTestScreen> {
  final _node = TorGossipNode();
  final _peerInputController = TextEditingController();
  final _msgInputController = TextEditingController();

  List<String> _logs = [];
  List<GossipEnvelope> _messages = [];
  bool _isReady = false;

  @override
  void initState() {
    super.initState();

    // Subscribe to engine logs and display them in the UI
    _node.onLog.listen((log) => setState(() => _logs.insert(0, log)));

    // Listen to messages (only non-handshake messages hit this stream)
    _node.onMessage.listen((envelope) {
      setState(() {
        _logs.insert(0, "📩 MSG from ${envelope.origin.substring(0, 6)}...");
        _messages.insert(0, envelope); // Insert at 0 to show newest first
      });
    });

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
    super.dispose();
  }

  Future<void> _start() async {
    try {
      await _node.start();
      setState(() => _isReady = true);
      _logs.insert(0, "✅ Node started. My onion: ${_node.onionAddress ?? 'unknown'}");
    } catch (e) {
      setState(() => _logs.insert(0, "❌ Error starting node: $e"));
    }
  }

  // Normalize user input.
  // 🌟 UPDATE: Defaults to http:// because the new client handles the tunnel automatically.
  Future<void> _addAndPingPeer(String onionInput) async {
    var input = onionInput.trim();
    if (input.isEmpty) return;

    if (!input.startsWith('http')) {
      input = 'http://$input'; // Default to HTTP for standard onion services
    }

    try {
      await _node.pingPeer(input);
      setState(() {
        _peerInputController.text = input;
        _logs.insert(0, "➕ Added & pinged peer: ${input.replaceAll('http://', '')}");
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Peer pinged: ${input.replaceFirst('http://', '').substring(0, 10)}...")),
      );
    } catch (e) {
      setState(() => _logs.insert(0, "❌ Error pinging peer: $e"));
    }
  }

  void _onSendPressed() {
    final peerText = _peerInputController.text.trim();
    final msg = _msgInputController.text;
    if (peerText.isEmpty || msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please set peer and message")));
      return;
    }

    _addAndPingPeer(peerText).then((_) {
      _node.addPeer(peerText);
      _node.publish("chat", msg);
      setState(() {
        _logs.insert(0, "📤 Published: $msg");
        _msgInputController.clear();
      });
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

  Future<void> _diagnosePeer() async {
    final raw = _peerInputController.text.trim();
    if (!raw.contains('.onion')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a .onion address first")));
      return;
    }

    setState(() => _logs.insert(0, "🔎 Diagnosing ${raw} ..."));

    try {
      // 🌟 UPDATE: Default to http://
      final target = raw.startsWith('http') ? raw : 'http://$raw';
      await _node.pingPeer(target);
      setState(() => _logs.insert(0, "🔎 Ping sent to $target (via TorOnionClient)"));
    } catch (e) {
      setState(() => _logs.insert(0, "❌ Diagnose failed: $e"));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Tor Gossip + QR")),
      body: Column(
        children: [
          if (!_isReady)
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: ElevatedButton(
                  onPressed: _start, child: const Text("BOOTSTRAP TOR NODE")),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.green[50],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("My Status: ONLINE",
                            style:
                                TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                        SelectableText(_node.onionAddress != null
                            ? "${_node.onionAddress!.substring(0, 15)}..."
                            : "Loading..."),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code, size: 32),
                    onPressed: _showMyQr,
                    tooltip: "Show My QR",
                  ),
                ],
              ),
            ),

          const Divider(),

          if (_isReady)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner, size: 30, color: Colors.blue),
                    onPressed: _scanQr,
                    tooltip: "Scan Peer QR",
                  ),
                  Expanded(
                    child: TextField(
                      controller: _peerInputController,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                          labelText: "Target Peer Onion",
                          hintText: "Scan or Paste .onion",
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.bug_report, color: Colors.orange),
                    onPressed: _diagnosePeer,
                    tooltip: "Diagnose Peer",
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.green),
                    onPressed: _onSendPressed,
                  )
                ],
              ),
            ),

          if (_isReady)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _msgInputController,
                decoration: const InputDecoration(labelText: "Type message..."),
              ),
            ),

          const Divider(),

          Expanded(
            child: ListView.builder(
              itemCount: _messages.length + _logs.length,
              itemBuilder: (context, index) {
                if (index < _messages.length) {
                  final m = _messages[index];
                  return ListTile(
                    tileColor: Colors.blue[50],
                    title: Text(m.payload),
                    subtitle: Text("From: ${m.origin.substring(0,10)}..."),
                    leading: const Icon(Icons.chat),
                  );
                }
                final logIndex = index - _messages.length;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text(_logs[logIndex],
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

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
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
    _node.onLog.listen((log) => setState(() => _logs.add(log)));
    _node.onMessage.listen((envelope) {
      setState(() {
        _logs.add("📩 MSG from ${envelope.origin.substring(0, 6)}...");
        _messages.add(envelope);
      });
    });
  }

  Future<void> _start() async {
    try {
      await _node.start();
      setState(() => _isReady = true);
    } catch (e) {
      setState(() => _logs.add("❌ Error: $e"));
    }
  }

  void _addPeer(String onion) {
    if (onion.contains(".onion")) {
      // Use the method we added to TorGossipNode
      _node.addPeer(onion);
      _peerInputController.text = onion;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Peer Added: ${onion.substring(0, 10)}...")),
      );
    }
  }

  Future<void> _scanQr() async {
    // Request permission first
    if (await Permission.camera.request().isGranted) {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const QrScanScreen()),
      );
      if (result != null && result is String) {
        _addPeer(result);
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
                  onPressed: _start,
                  child: const Text("BOOTSTRAP TOR NODE")
              ),
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
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                        Text(_node.onionAddress != null
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

          // --- Input / Scan Area ---
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
                        contentPadding: EdgeInsets.symmetric(horizontal: 8)
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.green),
                    onPressed: () {
                      final msg = _msgInputController.text;
                      if (msg.isNotEmpty) {
                         // Manually add peer from box before sending to ensure they are in the list
                         _node.addPeer(_peerInputController.text);
                         _node.publish("chat", msg);
                         _logs.add("📤 Sent: $msg");
                         _msgInputController.clear();
                      }
                    },
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

          // --- Logs ---
          Expanded(
            child: ListView.builder(
              reverse: true, // Show newest at bottom (if we inverted list logic) or top
              itemCount: _messages.length + _logs.length,
              itemBuilder: (context, index) {
                // Quick hack to merge lists for display
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
                // Show logs in reverse order (newest first)
                final log = _logs[(_logs.length - 1) - logIndex];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text(log, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                );
              },
            ),
          ),
        ],
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
              break; // Only scan one
            }
          }
        },
      ),
    );
  }
}
import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../envelopes/gossip_envelope.dart';

class TorServer {
  HttpServer? _server;

  /// The callback function to run when a valid message arrives.
  /// This is public and nullable so the main Node can assign it after initialization.
  Function(GossipEnvelope envelope)? onMessageReceived;

  TorServer();

  /// Starts the local HTTP server to listen for Tor traffic.
  /// [port] should match the internal port defined in your Tor config (usually 8080).
  Future<void> start(int port) async {
    final router = Router();

    // The main endpoint peers will hit: POST http://[your_onion]/gossip
    router.post('/gossip', _handleGossip);

    // A health check endpoint (optional, good for debugging)
    router.get('/health', (Request req) => Response.ok('Onion Alive'));

    // Create the pipeline with logging
    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router);

    // Bind to localhost.
    // SECURITY NOTE: We bind to '127.0.0.1' so only the Tor process
    // (running on the same device) can talk to us.
    // FIX: 'shared: true' prevents "Address already in use" errors during Hot Restart.
    _server = await shelf_io.serve(
      handler,
      '127.0.0.1',
      port,
      shared: true,
    );

    print('🧅 TorServer listening on localhost:$port');
  }

  /// Stops the server
  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  /// Handles incoming gossip packets
  Future<Response> _handleGossip(Request request) async {
    try {
      // 1. Read the body
      final content = await request.readAsString();

      if (content.isEmpty) {
        return Response.badRequest(body: 'Empty payload');
      }

      // 2. Parse into Envelope
      final envelope = GossipEnvelope.fromRawJson(content);

      // 3. Pass up to the Logic Layer (GossipEngine)
      if (onMessageReceived != null) {
        onMessageReceived!(envelope);
      } else {
        print("⚠️ Message received, but no listener attached!");
      }

      return Response.ok('{"status":"received"}');
    } catch (e) {
      print('❌ Malformed Gossip Packet: $e');
      return Response.badRequest(body: 'Invalid Envelope format');
    }
  }
}
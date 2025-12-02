import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../envelopes/gossip_envelope.dart';

class TorServer {
  HttpServer? _server;

  /// The callback function to run when a valid message arrives.
  Function(GossipEnvelope envelope)? onMessageReceived;

  TorServer();

  /// Starts the local HTTP server to listen for Tor traffic.
  /// [port] should match the internal port defined in your Tor config (usually 8080).
  Future<void> start(int port) async {
    final router = Router();

    // The main endpoint peers will hit: POST http://[your_onion]/gossip
    router.post('/gossip', _handleGossip);

    // A health check endpoint
    router.get('/health', (Request req) => Response.ok('Onion Alive'));

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router);

    // ⚠️ CRITICAL UPDATE: Bind to InternetAddress.anyIPv4 (0.0.0.0).
    // The native Tor process (running in a separate thread/namespace) needs
    // to reach this server. Binding to 'localhost' often fails on Android.
    _server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      port,
      shared: true,
    );

    print('🧅 TorServer listening on 0.0.0.0:$port');
  }

  /// Stops the server
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Handles incoming gossip packets
  Future<Response> _handleGossip(Request request) async {
    try {
      final content = await request.readAsString();

      if (content.isEmpty) {
        return Response.badRequest(body: 'Empty payload');
      }

      final envelope = GossipEnvelope.fromRawJson(content);

      if (onMessageReceived != null) {
        onMessageReceived!(envelope);
      } else {
        print("⚠️ Message received, but no listener attached!");
      }

      return Response.ok('{"status":"received"}', headers: {
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8'
      });
    } catch (e) {
      print('❌ Malformed Gossip Packet: $e');
      return Response.badRequest(body: 'Invalid Envelope format');
    }
  }
}
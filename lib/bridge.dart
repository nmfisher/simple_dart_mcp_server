import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:simple_dart_mcp_server/simple_dart_mcp_server.dart';
import 'package:simple_dart_mcp_server/src/client/client.dart';
import 'package:web_socket_channel/io.dart';

class StdioWebSocketBridge {
  
  late McpClient serverClient;
  late WebSocketTransport serverTransport;

  bool _isRunning = false;

  final Completer<void> _initialized = Completer<void>();

  Future<void> initialize({
    required String serverAddress,
    required int serverPort,
  }) async {
    try {
      stderr.writeln("Connecting to MCP server at ws://$serverAddress:$serverPort...");
      final socket = await WebSocket.connect('ws://$serverAddress:$serverPort');
      final channel = IOWebSocketChannel(socket);
      serverTransport = WebSocketTransport(channel);
      serverClient = McpClient(serverTransport);

     stderr.writeln("Websocket connected.");

      _isRunning = true;
      _initialized.complete();
    } catch (e) {
      stderr.writeln('Bridge initialization error: $e');
      _initialized.completeError(e);
      await close();
      rethrow;
    }
  }

  Future<void> start() async {
    await _initialized.future;

    if (!_isRunning) {
      throw Exception('Bridge not initialized properly.');
    }

    try {
      serverTransport.incoming.listen((String message) {
        // stderr.writeln("Raw response from mixreel : $message");
        stdout.writeln(message);
      });

      stdin
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((String line) async {
        try {
          // stderr.writeln("Raw input from client : $line");
          await serverTransport.send(line);
        } catch (e) {
          stderr.writeln('Error forwarding stdin to WebSocket: $e');
        }
      });

      // stderr.writeln('Bridge is running - forwarding stdin ↔ WebSocket');

      while (_isRunning) {
        await Future.delayed(Duration(seconds: 1));
      }
    } catch (e, st) {
      stderr.writeln('Bridge error: $e');
      stderr.writeln(st);
      await close();
      rethrow;
    }
  }

  // Close all connections
  Future<void> close() async {
    _isRunning = false;
    try {
      await serverClient.close();
      stderr.writeln('Server connection closed');
    } catch (e) {
      stderr.writeln('Error closing server connection: $e');
    }

    stderr.writeln('Bridge shutdown complete');
  }
}

void main(List<String> args) async {
  final serverAddress = args.isNotEmpty ? args[0] : 'localhost';
  final serverPort = args.length > 1 ? int.parse(args[1]) : 7337;

  final bridge = StdioWebSocketBridge();

  ProcessSignal.sigint.watch().listen((_) async {
    stderr.writeln('Received SIGINT, shutting down...');
    await bridge.close();
    exit(0);
  });

  try {
    await bridge.initialize(
      serverAddress: serverAddress,
      serverPort: serverPort,
    );

    await bridge.start();
  } catch (e) {
    stderr.writeln('Fatal error: $e');
    await bridge.close();
    exit(1);
  }
}

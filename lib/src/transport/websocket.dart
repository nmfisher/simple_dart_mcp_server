import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

import 'transport.dart';

/// Transport implementation that uses WebSocket connection.
class WebSocketTransport implements Transport {
  final WebSocketChannel _channel;
  final StreamController<String> _incomingController = StreamController<String>.broadcast();
  late final StreamSubscription<dynamic> _socketSubscription;
  bool _closed = false;

  @override
  Stream<String> get incoming => _incomingController.stream;

  /// Creates a new WebSocket transport
  ///
  /// Requires a [WebSocketChannel] to communicate with.
  WebSocketTransport(this._channel) {
    _socketSubscription = _channel.stream.listen(
      (dynamic message) {
        if (message != null && message is String && message.isNotEmpty) {
          _incomingController.add(message);
        }
      },
      onError: (error) {
        _incomingController.addError(
          TransportException('Error reading from WebSocket', error),
        );
      },
      onDone: () {
        close();
      },
      cancelOnError: false,
    );
  }

  /// Creates a new WebSocket transport by connecting to the specified URL
  ///
  /// Use this factory constructor to connect to a WebSocket server.
  factory WebSocketTransport.connect(Uri uri) {
    final channel = WebSocketChannel.connect(uri);
    return WebSocketTransport(channel);
  }

  @override
  Future<void> send(String message) async {
    if (_closed) {
      throw TransportException('Transport is closed');
    }

    try {
      _channel.sink.add(message);
    } catch (e) {
      throw TransportException('Error sending message to WebSocket', e);
    }
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closed) return;
    _closed = true;

    await _socketSubscription.cancel();
    await _channel.sink.close(code ?? status.normalClosure, reason);
    await _incomingController.close();
  }
}
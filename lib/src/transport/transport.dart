import 'dart:async';

/// Base class for MCP transport implementations.
abstract class Transport {
  /// Stream of incoming messages.
  Stream<String> get incoming;

  /// Send a message through the transport.
  Future<void> send(String message);

  /// Close the transport.
  Future<void> close();
}

/// Exception thrown when there's an error in transport operations.
class TransportException implements Exception {
  final String message;
  final dynamic cause;

  const TransportException(this.message, [this.cause]);

  @override
  String toString() {
    if (cause != null) {
      return 'TransportException: $message (Cause: $cause)';
    }

    return 'TransportException: $message';
  }
}

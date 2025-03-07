import 'dart:async';
import 'dart:convert';

import '../transport/transport_layer.dart';

/// Base class for MCP clients.
class McpClient {
  final Transport _transport;
  final _requestCompleters = <dynamic, Completer<dynamic>>{};
  final _notificationHandlers = <String, List<Function(dynamic)>>{};
  int _nextRequestId = 1;
  bool _initialized = false;
  bool _closed = false;

  static const String _protocolVersion = "2024-11-05";

  McpClient(this._transport) {
    _transport.incoming.listen(
      _handleMessage,
      onError: (error) {
        // Reject all pending requests with the error.
        for (final completer in _requestCompleters.values) {
          completer.completeError(error);
        }
        _requestCompleters.clear();
      },
      cancelOnError: true,
    );
  }

  /// Initialize the client with the given capabilities.
  Future<Map<String, dynamic>> initialize({
    required Map<String, dynamic> capabilities,
    required Map<String, String> clientInfo,
  }) async {
    if (_initialized) {
      throw StateError('Client is already initialized');
    }

    final result = await sendRequest<Map<String, dynamic>>(
      'initialize',
      {
        'protocolVersion': _protocolVersion,
        'capabilities': capabilities,
        'clientInfo': clientInfo,
      },
    );

    _initialized = true;

    return result;
  }

  /// Send a notification to the server.
  Future<void> sendNotification(String method, [Map<String, dynamic>? params]) async {
    if (_closed) {
      throw StateError('Client is closed');
    }

    final notification = {
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    };

    await _transport.send(jsonEncode(notification));
  }

  /// Send a request to the server and wait for the response.
  Future<T> sendRequest<T>(String method, [Map<String, dynamic>? params]) async {
    if (_closed) {
      throw StateError('Client is closed');
    }

    final id = _nextRequestId++;
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    final completer = Completer<T>();
    _requestCompleters[id] = completer;

    try {
      await _transport.send(jsonEncode(request));
    } catch (e) {
      _requestCompleters.remove(id);
      rethrow;
    }

    return completer.future;
  }

  /// Register a handler for notifications of a specific method.
  void onNotification(String method, Function(dynamic) handler) {
    _notificationHandlers.putIfAbsent(method, () => []).add(handler);
  }

  /// Close the client and its transport.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    // Cancel all pending requests.
    for (final completer in _requestCompleters.values) {
      completer.completeError(StateError('Client closed'));
    }
    _requestCompleters.clear();

    await _transport.close();
  }

  /// Handle an incoming message from the transport.
  void _handleMessage(String message) {
    final json = jsonDecode(message) as Map<String, dynamic>;

    if (json.containsKey('method')) {
      if (json.containsKey('id')) {
        // This is a request from the server.
        _handleRequest(json);
      } else {
        // This is a notification from the server.
        _handleNotification(json);
      }
    } else if (json.containsKey('result') || json.containsKey('error')) {
      // This is a response to one of our requests.
      _handleResponse(json);
    }
  }

  /// Handle a request from the server.
  void _handleRequest(Map<String, dynamic> json) {
    // TODO: Implement request handling.
  }

  /// Handle a notification from the server.
  void _handleNotification(Map<String, dynamic> json) {
    final method = json['method'] as String;
    final params = json['params'];
    
    final handlers = _notificationHandlers[method];
    if (handlers != null) {
      for (final handler in handlers) {
        handler(params);
      }
    }
  }

  /// Handle a response from the server.
  void _handleResponse(Map<String, dynamic> json) {
    final id = json['id'];
    final completer = _requestCompleters.remove(id);
    if (completer == null) {
      return;
    }

    if (json.containsKey('error')) {
      final error = _createErrorFromJson(json['error'] as Map<String, dynamic>);
      completer.completeError(error);
    } else {
      completer.complete(json['result']);
    }
  }
  
  /// Create an error object from JSON error data
  Exception _createErrorFromJson(Map<String, dynamic> errorJson) {
    final code = errorJson['code'];
    final message = errorJson['message'];
    final data = errorJson['data'];
    
    return Exception('RPC error $code: $message${data != null ? " - $data" : ""}');
  }
}
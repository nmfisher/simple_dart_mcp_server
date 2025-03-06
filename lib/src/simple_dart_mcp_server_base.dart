import 'dart:async';
import 'dart:convert';

import 'package:simple_dart_mcp_server/src/prompt.dart';
import 'package:simple_dart_mcp_server/src/resource.dart';
import 'package:simple_dart_mcp_server/src/tool.dart';
import 'package:simple_dart_mcp_server/src/transport/transport.dart';

class MCPServer {
  static const String JSONRPC_VERSION = "2.0";
  static const String PROTOCOL_VERSION = "2024-11-05";

  // Transport layer
  final Transport _transport;
  late final StreamSubscription<String> _transportSubscription;

  // State
  bool _initialized = false;
  final _tools = <Tool>[];
  final _resources = <Resource>[];
  final _prompts = <Prompt>[];
  final _resourceSubscriptions = <String, Set<String>>{};

  // Server info
  final Map<String, dynamic> _serverInfo = {
    "name": "simple-dart-mcp-server",
    "version": "0.1.0",
  };

  MCPServer(this._transport);

  /// Start the server using the provided transport
  Future<void> start() async {
    print("Starting MCP server...");

    // Listen for incoming messages from the transport
    _transportSubscription = _transport.incoming.listen(
      (String message) async {
        try {
          final Map<String, dynamic> parsed = jsonDecode(message);
          await _handleMessage(parsed);
        } catch (e) {
          await _sendError(null, -32700, "Parse error: ${e.toString()}");
        }
      },
      onError: (error) {
        print("Transport error: $error");
      },
      onDone: () {
        print("Transport connection closed");
      },
    );
  }

  /// Stop the server and clean up resources
  Future<void> stop() async {
    await _transportSubscription.cancel();
    await _transport.close();
  }

  /// Handle an incoming message
  Future<void> _handleMessage(Map<String, dynamic> message) async {
    if (message['jsonrpc'] != JSONRPC_VERSION) {
      await _sendError(
        message['id'],
        -32600,
        "Invalid Request: incorrect jsonrpc version",
      );
      return;
    }

    final String method = message['method'];
    final dynamic id = message['id'];
    final params = message['params'] as Map<String, dynamic>?;

    // Handle notifications (messages without IDs)
    if (id == null) {
      await _handleNotification(method, params);
      return;
    }

    // Handle requests (messages with IDs)
    try {
      switch (method) {
        case 'initialize':
          await _handleInitialize(id, params!);
          break;
        case 'ping':
          await _sendResponse(id, {});
          break;
        case 'tools/list':
          await _handleToolsList(id, params);
          break;
        case 'tools/call':
          await _handleToolsCall(id, params!);
          break;
        case 'resources/list':
          await _handleResourcesList(id, params);
          break;
        case 'resources/read':
          await _handleResourcesRead(id, params!);
          break;
        case 'resources/subscribe':
          await _handleResourcesSubscribe(id, params!);
          break;
        case 'resources/unsubscribe':
          await _handleResourcesUnsubscribe(id, params!);
          break;
        case 'prompts/list':
          await _handlePromptsList(id, params);
          break;
        case 'prompts/get':
          await _handlePromptsGet(id, params!);
          break;
        default:
          await _sendError(id, -32601, "Method not found: $method");
      }
    } catch (e) {
      await _sendError(id, -32603, "Internal error: ${e.toString()}");
    }
  }

  /// Handle a notification message (no response expected)
  Future<void> _handleNotification(
    String method,
    Map<String, dynamic>? params,
  ) async {
    switch (method) {
      case 'notifications/initialized':
        _initialized = true;
        print("Client initialized");
        break;
      default:
        print("Unhandled notification: $method");
    }
  }

  /// Handle initialize request
  Future<void> _handleInitialize(
    dynamic id,
    Map<String, dynamic> params,
  ) async {
    final clientInfo = params['clientInfo'];
    print(
      "Client initializing: ${clientInfo['name']} ${clientInfo['version']}",
    );

    // Respond with server capabilities
    await _sendResponse(id, {
      'protocolVersion': PROTOCOL_VERSION,
      'serverInfo': _serverInfo,
      'capabilities': {
        'tools': {'listChanged': true},
        'resources': {'subscribe': true, 'listChanged': true},
        'prompts': {'listChanged': true},
        'logging': {},
      },
      'instructions': 'This server provides basic calculator tools.',
    });
  }

  /// Handle tools/list request
  Future<void> _handleToolsList(
    dynamic id,
    Map<String, dynamic>? params,
  ) async {
    await _sendResponse(id, {
      'tools': _tools.map((tool) => tool.toJson()).toList(),
    });
  }

  /// Handle tools/call request
  Future<void> _handleToolsCall(dynamic id, Map<String, dynamic> params) async {
    final String toolName = params['name'];
    final Map<String, dynamic> args = params['arguments'] ?? {};

    final tool = _tools.firstWhere(
      (tool) => tool.name == toolName,
      orElse: () => throw Exception("Tool not found: $toolName"),
    );

    final result = await tool.execute(args);
    await _sendResponse(id, result);
  }

  /// Send a JSON-RPC response
  Future<void> _sendResponse(dynamic id, Map<String, dynamic> result) async {
    final response = {'jsonrpc': JSONRPC_VERSION, 'id': id, 'result': result};

    await _transport.send(jsonEncode(response));
  }

  /// Send a JSON-RPC error
  Future<void> _sendError(
    dynamic id,
    int code,
    String message, [
    dynamic data,
  ]) async {
    final response = {
      'jsonrpc': JSONRPC_VERSION,
      'id': id,
      'error': {
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      },
    };

    await _transport.send(jsonEncode(response));
  }

  /// Send a logging message
  Future<void> _sendLogMessage(String level, String message) async {
    final notification = {
      'jsonrpc': JSONRPC_VERSION,
      'method': 'notifications/message',
      'params': {'level': level, 'data': message},
    };

    await _transport.send(jsonEncode(notification));
  }

  MCPServer tool(Tool tool) {
    _tools.add(tool);
    return this;
  }

  MCPServer prompt(Prompt prompt) {
    _prompts.add(prompt);
    return this;
  }

  Future<void> _handlePromptsList(
    dynamic id,
    Map<String, dynamic>? params,
  ) async {
    await _sendResponse(id, {
      'prompts': _prompts.map((prompt) => prompt.toJson()).toList(),
    });
  }

  /// Handle prompts/get request
  Future<void> _handlePromptsGet(
    dynamic id,
    Map<String, dynamic> params,
  ) async {
    final String name = params['name'];
    final Map<String, String>? args =
        params['arguments']?.cast<String, String>();

    try {
      final prompt = _prompts.firstWhere(
        (prompt) => prompt.name == name,
        orElse: () => throw Exception('Prompt not found: $name'),
      );

      // Validate required arguments
      for (final arg in prompt.arguments ?? []) {
        if (arg.required == true &&
            (args == null || !args.containsKey(arg.name))) {
          throw Exception('Missing required argument: ${arg.name}');
        }
      }

      final messages = await _generatePromptMessages(name, args ?? {});

      await _sendResponse(id, {
        'description': prompt.description,
        'messages': messages,
      });
    } catch (e) {
      await _sendError(id, -32000, 'Error generating prompt: ${e.toString()}');
    }
  }

  /// Generate messages for a prompt template
  Future<List<Map<String, dynamic>>> _generatePromptMessages(
    String name,
    Map<String, String> args,
  ) async {
    if (name == 'analyze-data') {
      final data = args['data'] ?? '';
      final format = args['format'] ?? 'text';

      return [
        {
          'role': 'user',
          'content': {
            'type': 'text',
            'text':
                'Please analyze this data and provide insights:\n\n$data\n\nProvide the analysis in $format format.',
          },
        },
      ];
    } else if (name == 'explain-code') {
      final code = args['code'] ?? '';
      final language = args['language'] ?? '';
      final detail = args['detail'] ?? 'intermediate';

      return [
        {
          'role': 'user',
          'content': {
            'type': 'text',
            'text':
                'Please explain this $language code with a $detail level of detail:\n\n```$language\n$code\n```',
          },
        },
      ];
    } else {
      throw Exception('Unknown prompt: $name');
    }
  }

  /// Register available resources
  MCPServer resource(Resource resource) {
    this._resources.add(resource);
    return this;
  }

  /// Handle resources/list request
  Future<void> _handleResourcesList(
    dynamic id,
    Map<String, dynamic>? params,
  ) async {
    await _sendResponse(id, {
      'resources': _resources.map((resource) => resource.toJson()).toList(),
    });
  }

  /// Handle resources/read request
  Future<void> _handleResourcesRead(
    dynamic id,
    Map<String, dynamic> params,
  ) async {
    final String uri = params['uri'];

    try {
      final content = await _readResourceContent(uri);
      await _sendResponse(id, {
        'contents': [content],
      });
    } catch (e) {
      await _sendError(id, -32000, "Error reading resource: ${e.toString()}");
    }
  }

  /// Handle resources/subscribe request
  Future<void> _handleResourcesSubscribe(
    dynamic id,
    Map<String, dynamic> params,
  ) async {
    final String uri = params['uri'];
    final String clientId =
        id.toString(); // Using the request ID as a client identifier

    _resourceSubscriptions.putIfAbsent(uri, () => {}).add(clientId);

    await _sendResponse(id, {});
    await _sendLogMessage(
      'info',
      'Client $clientId subscribed to resource $uri',
    );
  }

  /// Handle resources/unsubscribe request
  Future<void> _handleResourcesUnsubscribe(
    dynamic id,
    Map<String, dynamic> params,
  ) async {
    final String uri = params['uri'];
    final String clientId = id.toString();

    _resourceSubscriptions[uri]?.remove(clientId);

    await _sendResponse(id, {});
    await _sendLogMessage(
      'info',
      'Client $clientId unsubscribed from resource $uri',
    );
  }

  /// Notify subscribers that a resource has been updated
  Future<void> _notifyResourceUpdate(String uri) async {
    final subscribers = _resourceSubscriptions[uri] ?? {};

    for (final clientId in subscribers) {
      final notification = {
        'jsonrpc': JSONRPC_VERSION,
        'method': 'notifications/resources/updated',
        'params': {'uri': uri},
      };

      await _transport.send(jsonEncode(notification));
    }
  }

  /// Read the content of a resource
  Future<Map<String, dynamic>> _readResourceContent(String uri) async {
    if (uri == 'system://info') {
      // Platform dependent code moved to implementation
      final systemInfo = await _getSystemInfo();

      return {
        'uri': uri,
        'mimeType': 'text/plain',
        'text': systemInfo.entries
            .map((e) => '${e.key}: ${e.value}')
            .join('\n'),
      };
    } else if (uri == 'notes://list') {
      final notes = [
        {
          'id': 1,
          'title': 'Welcome to MCP',
          'content': 'This is a sample note resource in the Dart MCP server.',
        },
        {
          'id': 2,
          'title': 'MCP Features',
          'content':
              'This server demonstrates basic tools and resources capabilities.',
        },
      ];

      return {
        'uri': uri,
        'mimeType': 'application/json',
        'text': jsonEncode(notes),
      };
    } else {
      throw Exception('Resource not found: $uri');
    }
  }

  Future<Map<String, dynamic>> _getSystemInfo() async {

    return {
      'platform': 'Implementation dependent',
      'version': 'Implementation dependent',
      'dart': 'Implementation dependent',
      'cpuCount': 'Implementation dependent',
      'hostname': 'Implementation dependent',
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}


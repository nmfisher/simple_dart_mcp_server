import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'transport.dart';

/// Transport implementation that uses standard input/output streams.
class StdioTransport implements Transport {
  final StreamController<String> _incomingController =
      StreamController<String>();
  late final StreamSubscription<String> _stdinSubscription;
  final IOSink? _customStdin;
  final Stream<List<int>>? _customStdout;
  bool _closed = false;

  @override
  Stream<String> get incoming => _incomingController.stream;

  /// Creates a new stdio transport
  ///
  /// If [customStdin] and [customStdout] are not provided, uses the standard system streams.
  /// When connecting to a Process, pass process.stdin as customStdin and process.stdout as customStdout.
  StdioTransport({IOSink? customStdin, Stream<List<int>>? customStdout})
      : _customStdin = customStdin,
        _customStdout = customStdout {
    final input = _customStdout ?? stdin;
    _stdinSubscription =
        input.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (String line) {
        if (line.isNotEmpty) {
          _incomingController.add(line);
        }
      },
      onError: (error) {
        _incomingController.addError(
          TransportException('Error reading from stdin', error),
        );
      },
      cancelOnError: true,
    );
  }

  @override
  Future<void> send(String message) async {
    if (_closed) {
      throw TransportException('Transport is closed');
    }

    try {
      final output = _customStdin ?? stdout;
      output.writeln(message);
      await output.flush();
    } catch (e) {
      throw TransportException('Error writing to stdout', e);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    await _stdinSubscription.cancel();
    await _incomingController.close();
    await _customStdin?.close();
  }
}

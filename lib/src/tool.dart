/// Base class for a tool
abstract class Tool {
  String get name;
  String get description;
  Map<String, dynamic> get inputSchema;

  Future<Map<String, dynamic>> execute(Map<String, dynamic> args);

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'inputSchema': inputSchema,
    };
  }
}

/// Calculator tool
class CalculatorTool extends Tool {
  @override
  String get name => 'calculate';

  @override
  String get description => 'Perform basic arithmetic operations';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'operation': {
        'type': 'string',
        'enum': ['add', 'subtract', 'multiply', 'divide'],
      },
      'a': {'type': 'number'},
      'b': {'type': 'number'},
    },
    'required': ['operation', 'a', 'b'],
  };

  @override
  Future<Map<String, dynamic>> execute(Map<String, dynamic> args) async {
    throw UnimplementedError();
  }
}


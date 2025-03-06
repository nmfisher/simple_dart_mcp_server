/// PromptArgument class for defining parameters to prompt templates
class PromptArgument {
  final String name;
  final String? description;
  final bool? required;

  PromptArgument({required this.name, this.description, this.required});

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      if (required != null) 'required': required,
    };
  }
}

/// Prompt class for defining prompt templates
class Prompt {
  final String name;
  final String? description;
  final List<PromptArgument>? arguments;

  Prompt({required this.name, this.description, this.arguments});

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      if (arguments != null && arguments!.isNotEmpty)
        'arguments': arguments!.map((arg) => arg.toJson()).toList(),
    };
  }
}
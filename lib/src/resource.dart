
/// Resource class for holding metadata about available resources
class Resource {
  final String uri;
  final String name;
  final String? description;
  final String? mimeType;

  Resource({
    required this.uri,
    required this.name,
    this.description,
    this.mimeType,
  });

  Map<String, dynamic> toJson() {
    return {
      'uri': uri,
      'name': name,
      if (description != null) 'description': description,
      if (mimeType != null) 'mimeType': mimeType,
    };
  }
}
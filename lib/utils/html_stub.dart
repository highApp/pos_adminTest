// Stub for dart:html on non-web platforms
// This file provides empty implementations to allow compilation on mobile

class Blob {
  final List<dynamic> data;
  final String type;
  Blob(this.data, this.type);
}

class Url {
  static String createObjectUrlFromBlob(Blob blob) => '';
  static void revokeObjectUrl(String url) {}
}

class CssStyleDeclaration {
  String display = '';
}

class AnchorElement {
  String? href;
  String? download;
  CssStyleDeclaration style = CssStyleDeclaration();
  Element? parent;
  AnchorElement({this.href});
  void setAttribute(String name, String value) {}
  void click() {}
  void remove() {}
}

class Element {
  Element? parent;
}

class Document {
  BodyElement? get body => null;
}

// Create document instance for html.document access
final _documentInstance = Document();
Document get document => _documentInstance;

class BodyElement {
  void append(AnchorElement element) {}
  void removeChild(AnchorElement element) {}
}


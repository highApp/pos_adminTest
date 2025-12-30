// Stub for dart:js on non-web platforms
// This file provides empty implementations to allow compilation on mobile
library js_stub;

// Re-export types that match dart:js API
class JsObject {
  dynamic callMethod(String method, List<dynamic> args) => null;
  dynamic operator [](String key) => null;
  void operator []=(String key, dynamic value) {}
  bool hasProperty(String key) => false;
}

class JsFunction extends JsObject {
  dynamic apply(List<dynamic> args, {dynamic thisArg}) => null;
}

class JsArray<T> {
  JsArray.from(List<T> list);
}

// Context object that matches dart:js context
class JsContext {
  dynamic callMethod(String method, List<dynamic> args) => null;
  dynamic operator [](String key) => null;
  void operator []=(String key, dynamic value) {}
  bool hasProperty(String key) => false;
}

final JsContext context = JsContext();

Function allowInterop(Function f) => f;


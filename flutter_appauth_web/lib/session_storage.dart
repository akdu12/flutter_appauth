import 'dart:html' as html;

import 'package:flutter_appauth_platform_interface/flutter_appauth_platform_interface.dart';

class LocalStorage {
  void save(String key, String value) {
    html.window.localStorage[key] = value;
  }

  void remove(String key) {
    html.window.localStorage.remove(key);
  }

  String getAndRemove(String key) {
    final value = html.window.localStorage[key];
    html.window.localStorage.remove(key);
    return value;
  }

  String get(String key) {
    return html.window.localStorage[key];
  }
}

extension Boolean on String {
  bool toBoolean() {
    if (this == null) {
      return null;
    }
    return this == "true";
  }
}

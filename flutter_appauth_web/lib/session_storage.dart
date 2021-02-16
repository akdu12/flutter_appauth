import 'dart:html' as html;

import 'package:flutter_appauth_platform_interface/flutter_appauth_platform_interface.dart';

class SessionStorage {
  void save(String key, String value) {
    html.window.sessionStorage[key] = value;
  }

  void remove(String key) {
    html.window.sessionStorage.remove(key);
  }

  String getAndRemove(String key) {
    final value = html.window.sessionStorage[key];
    html.window.sessionStorage.remove(key);
    return value;
  }

  String get(String key) {
    return html.window.sessionStorage[key];
  }

  void saveAuthRequest(AuthorizationRequest request) {
    save("client_id", request.clientId);
    save("redirect_uri", request.redirectUrl);

    if (request.loginHint != null) save("loginHint", request.loginHint);
    if (request.discoveryUrl != null)
      save("discoveryUrl", request.discoveryUrl);
    if (request.serviceConfiguration != null) {
      save("authorizationEndpoint",
          request.serviceConfiguration.authorizationEndpoint);
      save("tokenEndpoint", request.serviceConfiguration.tokenEndpoint);
    }
    if (request.issuer != null) save("issuer", request.issuer);
    if (request.allowInsecureConnections != null)
      save("allowInsecureConnections",
          request.allowInsecureConnections.toString());
    if (request.preferEphemeralSession != null)
      save("preferEphemeralSession", request.preferEphemeralSession.toString());
    if (request.scopes != null && request.scopes.isNotEmpty)
      save("scopes", request.scopes.join(" "));
    if (request.promptValues != null && request.promptValues.isNotEmpty)
      save("promptValues", request.promptValues.join(" "));
  }

  AuthorizationTokenRequest retrieveAuthRequest() {
    final clientId = getAndRemove("client_id");
    if (clientId == null) {
      return null;
    }
    AuthorizationServiceConfiguration serviceConfiguration;
    final authorizationEndpoint = getAndRemove("authorizationEndpoint");
    final tokenEndpoint = getAndRemove("tokenEndpoint");
    if (tokenEndpoint != null || authorizationEndpoint != null) {
      serviceConfiguration = AuthorizationServiceConfiguration(
          authorizationEndpoint, tokenEndpoint);
    }

    return AuthorizationTokenRequest(clientId, getAndRemove("redirect_uri"),
        clientSecret: getAndRemove("client_secret"),
        loginHint: getAndRemove("loginHint"),
        discoveryUrl: getAndRemove("discoveryUrl"),
        issuer: getAndRemove("issuer"),
        serviceConfiguration: serviceConfiguration,
        scopes: getAndRemove("scopes")?.split(" "),
        promptValues: getAndRemove("promptValues")?.split(" "),
        allowInsecureConnections:
            getAndRemove("allowInsecureConnections").toBoolean(),
        preferEphemeralSession:
            getAndRemove("preferEphemeralSession").toBoolean());
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

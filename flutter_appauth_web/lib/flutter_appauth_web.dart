library flutter_appauth_web;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_appauth_platform_interface/flutter_appauth_platform_interface.dart';
import 'package:flutter_appauth_web/htmt_utils.dart';
import 'package:flutter_appauth_web/session_storage.dart';
import 'package:flutter_appauth_web/web_client.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:pointycastle/digests/sha256.dart';

/// A Calculator.
class AppAuthWebPlugin extends FlutterAppAuthPlatform {
  static const String _charset =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  static const String _AUTHORIZE_ERROR_MESSAGE_FORMAT =
      "Failed to authorize: [error: %1, description: %2]";

  static const String _AUTHORIZE_AND_EXCHANGE_CODE_ERROR_CODE =
      "authorize_and_exchange_code_failed";
  static const String _AUTHORIZE_ERROR_CODE = "authorize_failed";

  static const String _CODE_VERIFIER_STORAGE = "auth_code_verifier";

  static final WebClient _webClient = WebClient();
  static final SessionStorage _sessionStorage = SessionStorage();

  static registerWith(Registrar registrar) {
    FlutterAppAuthPlatform.instance = AppAuthWebPlugin();
    saveAuthorizationCode();
  }

  @override
  Future<AuthorizationTokenResponse> authorizeAndExchangeCode(
      AuthorizationTokenRequest request) async {
    final authResult = await authorize(AuthorizationRequest(
        request.clientId, request.redirectUrl,
        loginHint: request.loginHint,
        scopes: request.scopes,
        serviceConfiguration: request.serviceConfiguration,
        additionalParameters: request.additionalParameters,
        allowInsecureConnections: request.allowInsecureConnections,
        discoveryUrl: request.discoveryUrl,
        issuer: request.issuer,
        preferEphemeralSession: request.preferEphemeralSession,
        promptValues: request.promptValues));

    if (authResult == null) return null;

    final tokenResponse = await requestToken(TokenRequest(
        request.clientId, request.redirectUrl,
        clientSecret: request.clientSecret,
        serviceConfiguration: request.serviceConfiguration,
        allowInsecureConnections: request.allowInsecureConnections,
        authorizationCode: authResult.authorizationCode,
        codeVerifier: authResult.codeVerifier,
        discoveryUrl: request.discoveryUrl,
        grantType: "authorization_code",
        issuer: request.issuer));

    return AuthorizationTokenResponse(
        tokenResponse.accessToken,
        tokenResponse.refreshToken,
        tokenResponse.accessTokenExpirationDateTime,
        tokenResponse.idToken,
        tokenResponse.tokenType,
        authResult.authorizationAdditionalParameters,
        tokenResponse.tokenAdditionalParameters);
  }

  @override
  Future<AuthorizationResponse> authorize(AuthorizationRequest request) async {
    final serviceConfiguration = await getConfiguration(
        request.serviceConfiguration, request.discoveryUrl, request.issuer);

    request.serviceConfiguration =
        serviceConfiguration; //Fill in the values from the discovery doc if needed for future calls.

    final codeVerifier = List.generate(
        128, (i) => _charset[Random.secure().nextInt(_charset.length)]).join();

    final codeChallenge = base64Url
        .encode(
            SHA256Digest().process(Uint8List.fromList(codeVerifier.codeUnits)))
        .replaceAll('=', '');

    var responseType = "code";

    var authUri =
        "${serviceConfiguration.authorizationEndpoint}?client_id=${request.clientId}&redirect_uri=${Uri.encodeQueryComponent(request.redirectUrl)}&response_type=$responseType&scope=${Uri.encodeQueryComponent(request.scopes?.join(' ') ?? "")}&code_challenge_method=S256&code_challenge=$codeChallenge";

    if (request.loginHint != null)
      authUri += "&login_hint=${Uri.encodeQueryComponent(request.loginHint)}";

    if (request.promptValues != null)
      request.promptValues.forEach((element) {
        authUri += "&prompt=$element";
      });
    if (request.additionalParameters != null)
      request.additionalParameters
          .forEach((key, value) => authUri += "&$key=$value");

    String loginResult;
    try {
      if (request.promptValues != null &&
          request.promptValues.contains("none")) {
        //Do this in an iframe instead of a popup because this is a silent renew
        loginResult = await openIframe(authUri, 'auth');
      } else {
        _sessionStorage.save(_CODE_VERIFIER_STORAGE, codeVerifier);
        _sessionStorage.saveAuthRequest(request);
        //redirectTo(authUri);
        loginResult = await openPopUp(authUri, 'auth', 640, 600, true);
        print(_sessionStorage.get("auth_code"));
        return null;
      }
    } on StateError catch (err) {
      throw StateError(_AUTHORIZE_ERROR_MESSAGE_FORMAT
          .replaceAll("%1", _AUTHORIZE_AND_EXCHANGE_CODE_ERROR_CODE)
          .replaceAll("%2", err.message));
    }

    return retrieveAuthResponse(loginResult, codeVerifier);
  }

  @override
  Future<TokenResponse> token(TokenRequest request) {
    return requestToken(request);
  }

  static Future<TokenResponse> requestToken(TokenRequest request) async {
    final serviceConfiguration = await getConfiguration(
        request.serviceConfiguration, request.discoveryUrl, request.issuer);

    request.serviceConfiguration =
        serviceConfiguration; //Fill in the values from the discovery doc if needed for future calls

    var body = {
      "client_id": request.clientId,
      "grant_type": request.grantType,
      "redirect_uri": request.redirectUrl
    };

    if (request.clientSecret != null)
      body["client_secret"] = request.clientSecret;

    if (request.authorizationCode != null)
      body["code"] = request.authorizationCode;
    if (request.codeVerifier != null)
      body["code_verifier"] = request.codeVerifier;
    if (request.refreshToken != null)
      body["refresh_token"] = request.refreshToken;
    if (request.scopes != null && request.scopes.isNotEmpty)
      body["scopes"] = request.scopes.join(" ");

    if (request.additionalParameters != null)
      body.addAll(request.additionalParameters);

    final Map<String, dynamic> jsonResponse =
        await _webClient.post(serviceConfiguration.tokenEndpoint, body);

    return TokenResponse(
        jsonResponse["access_token"].toString(),
        jsonResponse["refresh_token"]?.toString(),
        DateTime.now().add(new Duration(seconds: jsonResponse["expires_in"])),
        jsonResponse["id_token"].toString(),
        jsonResponse["token_type"].toString(),
        jsonResponse);
  }

  static void saveAuthorizationCode() {
    final url = getFullUrl();
    var resultUri = Uri.parse(url);
    var authCode = resultUri.queryParameters['code'];
    if (authCode == null || authCode.isEmpty) {
      _sessionStorage.save("auth_code", authCode);
    }
  }

  static Future<AuthorizationTokenResponse> checkRedirectionResult() async {
    final authUrl = getFullUrl();
    final request = _sessionStorage.retrieveAuthRequest();
    if (request == null) {
      return null;
    }

    final codeVerifier = _sessionStorage.getAndRemove(_CODE_VERIFIER_STORAGE);
    final authResult = retrieveAuthResponse(authUrl, codeVerifier);

    final tokenResponse = await requestToken(TokenRequest(
        request.clientId, request.redirectUrl,
        clientSecret: request.clientSecret,
        scopes: request.scopes,
        serviceConfiguration: request.serviceConfiguration,
        additionalParameters: request.additionalParameters,
        allowInsecureConnections: request.allowInsecureConnections,
        authorizationCode: authResult.authorizationCode,
        codeVerifier: authResult.codeVerifier,
        discoveryUrl: request.discoveryUrl,
        grantType: "authorization_code",
        issuer: request.issuer));

    return AuthorizationTokenResponse(
        tokenResponse.accessToken,
        tokenResponse.refreshToken,
        tokenResponse.accessTokenExpirationDateTime,
        tokenResponse.idToken,
        tokenResponse.tokenType,
        authResult.authorizationAdditionalParameters,
        tokenResponse.tokenAdditionalParameters);
  }

  //returns null if full login is required
  static AuthorizationResponse retrieveAuthResponse(
      String loginResult, String codeVerifier) {
    var resultUri = Uri.parse(loginResult.toString());

    final error = resultUri.queryParameters['error'];

    if (error != null && error.isNotEmpty)
      throw ArgumentError(_AUTHORIZE_ERROR_MESSAGE_FORMAT
          .replaceAll("%1", _AUTHORIZE_ERROR_CODE)
          .replaceAll("%2", error));

    var authCode = resultUri.queryParameters['code'];
    if (authCode == null || authCode.isEmpty)
      throw ArgumentError(_AUTHORIZE_ERROR_MESSAGE_FORMAT
          .replaceAll("%1", _AUTHORIZE_ERROR_CODE)
          .replaceAll("%2", 'Login request returned no code'));

    return AuthorizationResponse(
        authCode, codeVerifier, resultUri.queryParameters);
  }

  static Future<AuthorizationTokenResponse> exchangeCode(
      AuthorizationResponse authResult,
      String clientId,
      String redirectUrl,
      String tokenEndpoint,
      {String clientSecret}) async {
    if (authResult.authorizationCode == null ||
        authResult.authorizationCode.isEmpty)
      throw ArgumentError(_AUTHORIZE_ERROR_MESSAGE_FORMAT
          .replaceAll("%1", _AUTHORIZE_AND_EXCHANGE_CODE_ERROR_CODE)
          .replaceAll("%2", 'Login request returned no code'));

    final body = {
      "client_id": clientId,
      "redirect_uri": redirectUrl,
      "grant_type": "authorization_code",
      "code_verifier": authResult.codeVerifier,
      "code": authResult.authorizationCode
    };

    if (clientSecret != null) {
      body["client_secret"] = clientSecret;
    }
    final Map<String, dynamic> jsonResponse =
        await _webClient.post(tokenEndpoint, body);

    return AuthorizationTokenResponse(
        jsonResponse["access_token"].toString(),
        jsonResponse["refresh_token"] != null
            ? jsonResponse["refresh_token"].toString()
            : null,
        DateTime.now().add(new Duration(seconds: jsonResponse["expires_in"])),
        jsonResponse["id_token"].toString(),
        jsonResponse["token_type"].toString(),
        authResult.authorizationAdditionalParameters,
        jsonResponse);
  }

  //to-do Cache this based on the url
  static Future<AuthorizationServiceConfiguration> getConfiguration(
      AuthorizationServiceConfiguration serviceConfiguration,
      String discoveryUrl,
      String issuer) async {
    if ((discoveryUrl == null || discoveryUrl == '') &&
        (issuer == null || issuer == '') &&
        serviceConfiguration == null)
      throw ArgumentError(
          'You must specify either a discoveryUrl, issuer, or serviceConfiguration');

    if (serviceConfiguration != null) return serviceConfiguration;

    //Handle lookup here.
    if (discoveryUrl == null || discoveryUrl == '')
      discoveryUrl = "$issuer/.well-known/openid-configuration";

    final Map<String, dynamic> jsonResponse =
        await _webClient.get(discoveryUrl);
    return AuthorizationServiceConfiguration(
        jsonResponse["authorization_endpoint"].toString(),
        jsonResponse["token_endpoint"].toString());
  }
}

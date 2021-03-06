library flutter_appauth_web;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_appauth_platform_interface/flutter_appauth_platform_interface.dart';
import 'package:flutter_appauth_web/htmt_helper.dart';
import 'package:flutter_appauth_web/local_storage.dart';
import 'package:flutter_appauth_web/web_client.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:crypto/crypto.dart';

class AppAuthWebPlugin extends FlutterAppAuthPlatform {
  static const String _charset =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  static const String _AUTHORIZE_ERROR_MESSAGE_FORMAT =
      "Failed to authorize: [error: %1, description: %2]";

  static const String _AUTHORIZE_AND_EXCHANGE_CODE_ERROR_CODE =
      "authorize_and_exchange_code_failed";
  static const String _AUTHORIZE_ERROR_CODE = "authorize_failed";

  static const String _CODE_VERIFIER_STORAGE = "auth_code_verifier";
  static const String AUTH_REDIRECT_URL = "auth_redirect_url";

  static final WebClient _webClient = WebClient();
  static final LocalStorage _localStorage = LocalStorage();

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
        allowInsecureConnections: request.allowInsecureConnections ?? false,
        discoveryUrl: request.discoveryUrl,
        issuer: request.issuer,
        preferEphemeralSession: request.preferEphemeralSession ?? false,
        promptValues: request.promptValues));

    final tokenResponse = await requestToken(TokenRequest(
        request.clientId, request.redirectUrl,
        clientSecret: request.clientSecret,
        serviceConfiguration: request.serviceConfiguration,
        allowInsecureConnections: request.allowInsecureConnections ?? false,
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
            sha256.convert(Uint8List.fromList(codeVerifier.codeUnits)).bytes)
        .replaceAll('=', '');

    var responseType = "code";

    var authUri =
        "${serviceConfiguration.authorizationEndpoint}?client_id=${request.clientId}&redirect_uri=${Uri.encodeQueryComponent(request.redirectUrl)}&response_type=$responseType&scope=${Uri.encodeQueryComponent(request.scopes?.join(' ') ?? "")}&code_challenge_method=S256&code_challenge=$codeChallenge";

    if (request.loginHint != null)
      authUri += "&login_hint=${Uri.encodeQueryComponent(request.loginHint!)}";

    if (request.promptValues != null)
      request.promptValues!.forEach((element) {
        authUri += "&prompt=$element";
      });
    if (request.additionalParameters != null)
      request.additionalParameters!
          .forEach((key, value) => authUri += "&$key=$value");

    String loginResult;
    try {
      if (request.promptValues != null &&
          request.promptValues!.contains("none")) {
        //Do this in an iframe instead of a popup because this is a silent renew
        loginResult = await openIframe(authUri, 'auth');
      } else {
        _localStorage.save(_CODE_VERIFIER_STORAGE, codeVerifier);
        //redirectTo(authUri);
        await openPopUp(authUri, 'auth', 640, 600, true);
        if (_localStorage.get(AUTH_REDIRECT_URL) == null) {
          throw StateError(_AUTHORIZE_ERROR_MESSAGE_FORMAT
              .replaceAll("%1", _AUTHORIZE_AND_EXCHANGE_CODE_ERROR_CODE)
              .replaceAll("%2", "enable to find Auth redirect code"));
        }

        return retrieveAuthResponse(
            _localStorage.getAndRemove(AUTH_REDIRECT_URL)!, codeVerifier);
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
    late Map<String, String> headers;

    request.serviceConfiguration =
        serviceConfiguration; //Fill in the values from the discovery doc if needed for future calls

    var body = {
      "grant_type": request.grantType,
      "redirect_uri": request.redirectUrl
    };

    if (request.clientSecret != null) {
      String basicAuth = 'Basic ' +
          base64Encode(
              utf8.encode('${request.clientId}:${request.clientSecret}'));
      headers = {'authorization': basicAuth};
    } else {
      body["client_id"] = request.clientId;
    }

    if (request.authorizationCode != null)
      body["code"] = request.authorizationCode;
    if (request.codeVerifier != null)
      body["code_verifier"] = request.codeVerifier;
    if (request.refreshToken != null)
      body["refresh_token"] = request.refreshToken;
    if (request.scopes != null && request.scopes!.isNotEmpty)
      body["scopes"] = request.scopes!.join(" ");

    if (request.additionalParameters != null)
      body.addAll(request.additionalParameters!);

    final Map<String, dynamic> jsonResponse = await _webClient
        .post(serviceConfiguration.tokenEndpoint, body, headers: headers);

    return TokenResponse(
        jsonResponse["access_token"].toString(),
        jsonResponse["refresh_token"]?.toString(),
        DateTime.now().add(new Duration(seconds: jsonResponse["expires_in"])),
        jsonResponse["id_token"].toString(),
        jsonResponse["token_type"].toString(),
        jsonResponse);
  }

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
      {String? clientSecret}) async {
    if (authResult.authorizationCode == null ||
        authResult.authorizationCode!.isEmpty)
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

  static void saveAuthorizationCode() {
    final url = getFullUrl();
    var resultUri = Uri.parse(url);
    var authCode = resultUri.queryParameters['code'];
    if (authCode != null && authCode.isNotEmpty) {
      _localStorage.save(AUTH_REDIRECT_URL, url);
      closeCurrentPopUp();
    }
  }

  //TODO Cache this based on the url
  static Future<AuthorizationServiceConfiguration> getConfiguration(
      AuthorizationServiceConfiguration? serviceConfiguration,
      String? discoveryUrl,
      String? issuer) async {
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

import 'dart:convert';

import 'package:http/http.dart' as http;

class WebClient {
  static const String ERROR_MESSAGE = "[statusCode: %1, description: %2]";

  Future<dynamic> post(String url, Map<String, dynamic> body,
      {bool authenticated = true}) async {
    try {
      final response = await http.post(
        url,
        body: body,
      );

      final Map<String, dynamic> jsonResponse = jsonDecode(response.body);

      if (response.statusCode != 200) {
        print(jsonResponse["error"].toString());
        throw Exception(ERROR_MESSAGE
            .replaceFirst("%1", response.statusCode.toString())
            .replaceAll("%2",
                jsonResponse["error"]?.toString() ?? response.reasonPhrase));
      }
      return jsonResponse;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> get(
    String url,
  ) async {
    try {
      final response = await http.get(
        url,
      );
      final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw Exception(ERROR_MESSAGE
            .replaceFirst("%1", response.statusCode.toString())
            .replaceAll("%2",
                jsonResponse["error"]?.toString() ?? response.reasonPhrase));
      }
      return jsonResponse;
    } catch (e) {
      rethrow;
    }
  }
}

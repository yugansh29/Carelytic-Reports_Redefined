import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => statusCode == null ? message : 'HTTP $statusCode: $message';
}

class ApiService {
  static const String _hostOverride = String.fromEnvironment('API_HOST');
  static const String _schemeOverride = String.fromEnvironment('API_SCHEME');
  static const String _portOverride = String.fromEnvironment('API_PORT');
  static const String _authToken = String.fromEnvironment('API_BEARER_TOKEN');
  static const int _maxRetries = 2;

  /// When set (e.g. in tests with [http.MockClient]), all requests use this client instead of the default.
  static http.Client? httpClient;

  static Future<http.Response> _viaClient(
    Future<http.Response> Function(http.Client client) send,
  ) async {
    if (httpClient != null) {
      return send(httpClient!);
    }
    final client = http.Client();
    try {
      return await send(client);
    } finally {
      client.close();
    }
  }

  static String get _apiScheme => _schemeOverride.isNotEmpty ? _schemeOverride : 'http';
  static int get _apiPort => int.tryParse(_portOverride) ?? 8001;

  static String get _apiHost {
    if (_hostOverride.isNotEmpty) return _hostOverride;
    if (kIsWeb) return 'localhost';

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        // Android emulator maps host localhost via 10.0.2.2
        return '10.0.2.2';
      case TargetPlatform.iOS:
        return '127.0.0.1';
      default:
        return '127.0.0.1';
    }
  }

  static String get baseUrl => '$_apiScheme://$_apiHost:$_apiPort/api';

  static Map<String, String> _jsonHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  static Future<http.Response> _sendWithRetry(Future<http.Response> Function() request) async {
    Object? lastErr;
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final response = await request();
        if (response.statusCode == HttpStatus.tooManyRequests || response.statusCode >= 500) {
          if (attempt < _maxRetries - 1) continue;
        }
        return response;
      } catch (err) {
        lastErr = err;
        if (attempt == _maxRetries - 1) break;
      }
    }
    throw ApiException('Network request failed: $lastErr');
  }

  static dynamic _decodeBody(http.Response response) {
    if (response.body.isEmpty) return {};
    return jsonDecode(response.body);
  }

  static Never _throwForStatus(http.Response response) {
    dynamic payload;
    try {
      payload = _decodeBody(response);
    } catch (_) {
      payload = null;
    }

    final message = payload is Map<String, dynamic>
        ? (payload['detail']?.toString() ?? payload['message']?.toString() ?? 'Request failed')
        : 'Request failed';
    throw ApiException(message, statusCode: response.statusCode);
  }

  // ── EHR ───────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> fetchEhr(String patientId) async {
    final uri = Uri.parse('$baseUrl/ehr/$patientId');
    final headers = _jsonHeaders();
    final res = await _sendWithRetry(
      () => _viaClient((c) => c.get(uri, headers: headers).timeout(const Duration(seconds: 10))),
    );
    if (res.statusCode == 200) {
      final data = _decodeBody(res);
      if (data is Map<String, dynamic>) return data;
      throw const ApiException('Unexpected EHR payload format');
    }
    _throwForStatus(res);
  }
  // ── Transcription (Deprecated - Now running on device) ──

  // ── SOAP Generation ───────────────────────────────────────────
  static Future<Map<String, dynamic>> generateSoap(
      String transcript, Map<String, dynamic> patientContext) async {
    final uri = Uri.parse('$baseUrl/generate-soap');
    final headers = _jsonHeaders();
    final body = jsonEncode({'transcript_text': transcript, 'patient_context': patientContext});
    final res = await _sendWithRetry(
      () => _viaClient((c) => c.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 60))),
    );
    if (res.statusCode == 200) {
      final data = _decodeBody(res);
      if (data is Map<String, dynamic>) return data;
      throw const ApiException('Unexpected SOAP payload format');
    }
    _throwForStatus(res);
  }

  // ── Suggested Questions ───────────────────────────────────────
  static Future<List<String>> suggestQuestions(String buffer, String chiefComplaint) async {
    try {
      final uri = Uri.parse('$baseUrl/suggest-questions');
      final headers = _jsonHeaders();
      final body = jsonEncode({'transcript_buffer': buffer, 'chief_complaint': chiefComplaint});
      final res = await _sendWithRetry(
        () => _viaClient((c) => c.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 30))),
      );
      if (res.statusCode == 200) {
        final data = _decodeBody(res);
        final List<dynamic> q = data['questions'] ?? [];
        return q.map((e) => e.toString()).toList();
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw ApiException('Unauthorized request', statusCode: res.statusCode);
      }
    } catch (e) {
      debugPrint('Questions err: $e');
    }
    return [];
  }

  // ── Patient Summary ───────────────────────────────────────────
  static Future<Map<String, dynamic>> getPatientSummary(Map<String, dynamic> soapJson) async {
    final uri = Uri.parse('$baseUrl/patient-summary');
    final headers = _jsonHeaders();
    final body = jsonEncode({'soap_json': soapJson});
    final res = await _sendWithRetry(
      () => _viaClient((c) => c.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 60))),
    );
    if (res.statusCode == 200) {
      final data = _decodeBody(res);
      if (data is Map<String, dynamic>) return data;
      throw const ApiException('Unexpected summary payload format');
    }
    _throwForStatus(res);
  }
}

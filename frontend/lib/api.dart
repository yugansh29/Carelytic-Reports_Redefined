import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiService {
  // Use 127.0.0.1 instead of localhost to avoid IPv6 resolution blocks on some environments
  static const String baseUrl = 'http://127.0.0.1:8000/api';

  static Future<Map<String, dynamic>> fetchEhr(String patientId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/ehr/$patientId'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("EHR fetch err: $e");
    }
    return {};
  }

  static Future<Map<String, dynamic>> transcribeAudio(Uint8List audioBytes) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/transcribe'));
      // Adding actual audio bytes as file
      request.files.add(http.MultipartFile.fromBytes('file', audioBytes, filename: 'audio.wav'));
      var res = await request.send();
      if (res.statusCode == 200) {
        var str = await res.stream.bytesToString();
        return jsonDecode(str);
      }
    } catch (e) {
      print("Transcribe err: $e");
    }
    return {"transcript": "Patient: My back has been hurting for 3 weeks... (Offline Mock)", "is_fallback": true};
  }

  static Future<Map<String, dynamic>> generateSoap(String transcript, Map<String, dynamic> patientContext) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/generate-soap'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"transcript_text": transcript, "patient_context": patientContext})
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("SOAP err: $e");
    }
    return {"subjective": "Error generating system unavailable.", "is_fallback": true};
  }

  static Future<List<String>> suggestQuestions(String buffer, String chiefComplaint) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/suggest-questions'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"transcript_buffer": buffer, "chief_complaint": chiefComplaint})
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<dynamic> q = data['questions'] ?? [];
        return q.map((e) => e.toString()).toList();
      }
    } catch (e) {
      print("Questions err: $e");
    }
    return [];
  }

  static Future<Map<String, dynamic>> getPatientSummary(Map<String, dynamic> soapJson) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/patient-summary'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"soap_json": soapJson})
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Summary err: $e");
    }
    return {"summary": "Error generating summary.", "is_fallback": true};
  }
}

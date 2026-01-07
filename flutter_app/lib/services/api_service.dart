import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../models/analysis_result.dart';
import '../models/history_record.dart';
import '../models/user.dart';

import '../models/doctor.dart';
import '../models/chat_user.dart';
import '../models/chat_message.dart';
import '../models/patient.dart';
import '../models/patient.dart';

class ApiService {
  static const String _baseUrlKey = 'api_base_url';
  // Default for Android Emulator
  static const String _defaultBaseUrl = 'http://127.0.0.1:5000'; 
  
  // Shared state to track alerts that have already been shown to the user on this device
  static final Set<String> shownAlertIds = {};

  void markAlertAsShown(String alertId) {
    shownAlertIds.add(alertId);
  }

  void clearShownAlerts() {
    shownAlertIds.clear();
  }

  Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey) ?? _defaultBaseUrl;
  }

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url);
  }

  Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final baseUrl = await getBaseUrl();
    return await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }

  Future<http.Response> get(String endpoint) async {
    final baseUrl = await getBaseUrl();
    return await http.get(Uri.parse('$baseUrl$endpoint'));
  }

  Future<bool> testConnection() async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http.get(Uri.parse('$baseUrl/health'));
      return response.statusCode == 200;
    } catch (e) {
      print('Connection test failed: $e');
      return false;
    }
  }

  Future<Stream<String>> streamVideoAnalysis(XFile file, String patientId, String patientName) async {
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse('$baseUrl/stream_video_analysis');
    final request = http.MultipartRequest('POST', uri);
    
    final bytes = await file.readAsBytes();
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: file.name,
      contentType: MediaType('video', 'mp4'),
    ));
    request.fields['patientId'] = patientId;
    request.fields['patientName'] = patientName;

    try {
      final streamedResponse = await request.send();
      
      if (streamedResponse.statusCode == 200) {
        return streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());
      } else {
        throw Exception('Failed to start stream: ${streamedResponse.reasonPhrase}');
      }
    } catch (e) {
      print('Error streaming analysis: $e');
      rethrow;
    }
  }
  Future<Stream<String>> streamRtspAnalysis(String url, String patientId, String patientName) async {
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse('$baseUrl/stream_rtsp_analysis');
    
    try {
      final request = http.Request('POST', uri);
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'url': url,
        'patientId': patientId,
        'patientName': patientName,
      });

      final streamedResponse = await http.Client().send(request);
      
      if (streamedResponse.statusCode == 200) {
        return streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());
      } else {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception('Failed to start RTSP stream: $errorBody');
      }
    } catch (e) {
      print('Error streaming RTSP analysis: $e');
      rethrow;
    }
  }




  Future<Map<String, dynamic>> predictVideoInterval(XFile file, double startTime, double endTime) async {
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse('$baseUrl/predict_video_interval');
    final request = http.MultipartRequest('POST', uri);
    
    final bytes = await file.readAsBytes();
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: 'video_interval.mp4',
      contentType: MediaType('video', 'mp4'),
    ));
    request.fields['start_time'] = startTime.toString();
    request.fields['end_time'] = endTime.toString();

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to analyze interval: ${response.body}');
      }
    } catch (e) {
      print('Error predicting interval: $e');
      rethrow;
    }
  }

  Future<AnalysisResult> predict(XFile file, bool isVideo) async {
    final baseUrl = await getBaseUrl();
    final endpoint = isVideo ? '/predict_video_frames' : '/predict';
    final uri = Uri.parse('$baseUrl$endpoint');

    var request = http.MultipartRequest('POST', uri);
    
    final mimeType = isVideo ? MediaType('video', 'mp4') : MediaType('image', 'jpeg');
    
    final bytes = await file.readAsBytes();
    request.files.add(http.MultipartFile.fromBytes(
      'file', 
      bytes,
      filename: file.name,
      contentType: mimeType,
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return AnalysisResult.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to analyze file: ${response.statusCode} ${response.body}');
    }
  }

  Future<List<HistoryRecord>> getHistory() async {
    final baseUrl = await getBaseUrl();
    
    try {
      final historyResponse = await http.get(Uri.parse('$baseUrl/api/history'));
      final alertsResponse = await http.get(Uri.parse('$baseUrl/api/alerts'));

      List<HistoryRecord> records = [];

      if (historyResponse.statusCode == 200) {
        final List<dynamic> historyJson = jsonDecode(historyResponse.body);
        records.addAll(historyJson.map((e) => HistoryRecord.fromJson(e)));
      }

      if (alertsResponse.statusCode == 200) {
        final Map<String, dynamic> alertsJson = jsonDecode(alertsResponse.body);
        if (alertsJson['alerts'] != null) {
          final List<dynamic> alertsList = alertsJson['alerts'];
          records.addAll(alertsList.map((e) => HistoryRecord.fromJson({...e, 'isAlert': true})));
        }
      }

      // Sort by timestamp descending
      records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      return records;
    } catch (e) {
      print('Error fetching history: $e');
      throw Exception('Failed to fetch history');
    }
  }
  
  Future<bool> saveHistory(Map<String, dynamic> data) async {
     final baseUrl = await getBaseUrl();
     
     // Ensure patient object is present for backend compatibility
     if (data.containsKey('patientId') && !data.containsKey('patient')) {
       data['patient'] = {
         'id': data['patientId'],
         'name': data['patientName'],
       };
     }

     try {
       final response = await http.post(
         Uri.parse('$baseUrl/api/history'),
         headers: {'Content-Type': 'application/json'},
         body: jsonEncode(data),
       );
       return response.statusCode == 200;
     } catch (e) {
       print('Error saving history: $e');
       return false;
     }
  }

  Future<bool> saveAlert(Map<String, dynamic> data) async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/alert'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error saving alert: $e');
      return false;
    }
  }

  Future<bool> acknowledgeAlert(String alertId, String userName) async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/alert/acknowledge'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': alertId,
          'acknowledgedBy': userName,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error acknowledging alert: $e');
      return false;
    }
  }
  Future<Map<String, dynamic>?> login(String username, String password, String role) async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'role': role,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Login error: $e');
      return null;
    }
  }

  Future<List<HistoryRecord>> getPendingAlerts() async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/alerts?status=pending'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['alerts'] != null) {
          final List<dynamic> alerts = data['alerts'];
          return alerts.map((e) => HistoryRecord.fromJson({...e, 'isAlert': true})).toList();
        }
      }
      return [];
    } catch (e) {
      print('Error fetching pending alerts: $e');
      return [];
    }
  }

  Future<String?> getAlertStatus(String alertId) async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/alerts'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> alerts = data['alerts'] ?? [];
        final alert = alerts.firstWhere((a) => a['id'] == alertId, orElse: () => null);
        return alert?['status'];
      }
      return null;
    } catch (e) {
      print('Error checking alert status: $e');
      return null;
    }
  }

  Future<List<User>> getNurses() async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/nurses'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => User.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching nurses: $e');
      return [];
    }
  }

  Future<bool> addNurse(Map<String, dynamic> nurseData) async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nurses'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(nurseData),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error adding nurse: $e');
      return false;
    }
  }

  Future<bool> deleteNurse(String username) async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.delete(Uri.parse('$baseUrl/api/nurses/$username'));
      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting nurse: $e');
      return false;
    }
  }

  Future<List<Doctor>> getDoctors() async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/doctors'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        return data.map((e) => Doctor.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching doctors: $e');
      return [];
    }
  }

  // --- CHAT METHODS ---

  Future<List<ChatUser>> getChatUsers(String currentUsername) async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/chat/users?current_user=$currentUsername'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => ChatUser.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching chat users: $e');
      return [];
    }
  }

  Future<void> sendHeartbeat(String username) async {
    final baseUrl = await getBaseUrl();
    try {
      await http.post(
        Uri.parse('$baseUrl/api/heartbeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username}),
      );
    } catch (e) {
      print('Heartbeat error: $e');
    }
  }

  Future<List<ChatMessage>> getChatHistory(String sender, String recipient) async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/chat/history/$recipient?sender=$sender'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => ChatMessage.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching chat history: $e');
      return [];
    }
  }

  Future<bool> sendMessage(String sender, String recipient, String text, {String type = 'text', String? mediaUrl}) async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/chat/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sender': sender,
          'recipient': recipient,
          'text': text,
          'type': type,
          'media_url': mediaUrl,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error sending message: $e');
      return false;
    }
  }

  Future<String?> uploadChatMedia(XFile file, {required bool isVideo}) async {
    final baseUrl = await getBaseUrl();
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/chat/upload_media'));
      
      final bytes = await file.readAsBytes();
      
      // Determine content type
      final contentType = isVideo 
          ? MediaType('video', 'mp4') 
          : MediaType('image', 'jpeg');
      
      request.files.add(http.MultipartFile.fromBytes(
        'file', 
        bytes,
        filename: file.name.isNotEmpty ? file.name : (isVideo ? 'video.mp4' : 'image.jpg'),
        contentType: contentType,
      ));

      final response = await request.send();
      if (response.statusCode == 200) {
        final resStr = await response.stream.bytesToString();
        final data = jsonDecode(resStr);
        return data['media_url'];
      }
      return null;
    } catch (e) {
      print('Error uploading chat media: $e');
      return null;
    }
  }

  // Legacy support for audio (can refactor to use uploadChatMedia eventually)
  Future<String?> uploadChatAudio(XFile file) async {
    final baseUrl = await getBaseUrl();
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/chat/upload_audio'));
      
      final bytes = await file.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'file', // Changed to 'file' to match backend generic handler, though backend supports 'audio' too via legacy
        bytes,
        filename: file.name.isNotEmpty ? file.name : 'audio_message.m4a',
        contentType: MediaType('audio', 'mp4'),
      ));

      final response = await request.send();
      if (response.statusCode == 200) {
        final resStr = await response.stream.bytesToString();
        final data = jsonDecode(resStr);
        return data['media_url'];
      }
      return null;
    } catch (e) {
      print('Error uploading chat audio: $e');
      return null;
    }
  }

  // --- DUTY BROADCAST METHODS ---

  Future<bool> broadcastDutyStatus(String nurseName) async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/duty/broadcast'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'nurseName': nurseName}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error broadcasting duty status: $e');
      return false;
    }
  }

  Future<List<dynamic>> getDutyBroadcasts() async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/duty/broadcasts'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      print('Error fetching duty broadcasts: $e');
      return [];
    }
  }

  // --- PATIENT MANAGEMENT METHODS ---

  Future<List<Patient>> getPatients() async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/patients'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((p) => Patient.fromJson(p)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching patients: $e');
      return [];
    }
  }

  Future<bool> savePatient(Patient patient) async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/patients'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(patient.toJson()),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error saving patient: $e');
      return false;
    }
  }

  Future<bool> deletePatient(String id) async {
    final baseUrl = await getBaseUrl();
    try {
      final response = await http.delete(Uri.parse('$baseUrl/api/patients/$id'));
      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting patient: $e');
      return false;
    }
  }
}

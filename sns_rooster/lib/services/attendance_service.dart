import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sns_rooster/providers/auth_provider.dart';
import '../config/api_config.dart';

class AttendanceService {
  final AuthProvider authProvider;

  AttendanceService(this.authProvider);

  Future<Map<String, dynamic>> checkIn(String userId, {String? notes}) async {
    final token = authProvider.token;
    if (token == null) {
      throw Exception('No valid token found');
    }
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final url = '${ApiConfig.baseUrl}/attendance/check-in';
    final body = json.encode({
      'userId': userId,
      if (notes != null) 'notes': notes,
    });
    print('DEBUG: Sending userId in checkIn API call: $userId');
    print('DEBUG: Authorization header for API call: Bearer $token');
    final response = await http.post(Uri.parse(url), headers: headers, body: body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to check in: ${response.statusCode} ${response.body}');
    }
  }

  Future<Map<String, dynamic>> checkOut(String userId, {String? notes}) async {
    final token = authProvider.token;
    if (token == null) {
      throw Exception('No valid token found');
    }
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final url = '${ApiConfig.baseUrl}/attendance/check-out';
    final body = json.encode({
      'userId': userId,
      if (notes != null) 'notes': notes,
    });
    print('DEBUG: Sending userId in checkOut API call: $userId');
    print('DEBUG: Authorization header for API call: Bearer $token');
    final response = await http.patch(Uri.parse(url), headers: headers, body: body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to check out: ${response.statusCode} ${response.body}');
    }
  }

  Future<List<Map<String, dynamic>>> getAttendanceHistory(String userId,
      {DateTime? startDate, DateTime? endDate}) async {
    final token = authProvider.token;
    if (token == null) {
      throw Exception('No valid token found');
    }
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    String url = '${ApiConfig.baseUrl}/attendance/user/$userId';
    final queryParams = <String, String>{};
    if (startDate != null) queryParams['startDate'] = startDate.toIso8601String();
    if (endDate != null) queryParams['endDate'] = endDate.toIso8601String();
    if (queryParams.isNotEmpty) {
      url += '?${Uri(queryParameters: queryParams).query}';
    }
    final response = await http.get(Uri.parse(url), headers: headers);
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch attendance: ${response.statusCode} ${response.body}');
    }
  }

  Future<Map<String, dynamic>?> getCurrentAttendance(String userId) async {
    final token = authProvider.token;
    if (token == null) {
      throw Exception('No valid token found');
    }
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final url = '${ApiConfig.baseUrl}/attendance/current/$userId';
    final response = await http.get(Uri.parse(url), headers: headers);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw Exception('Failed to fetch current attendance: ${response.statusCode} ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getAttendanceSummary(String userId,
      {DateTime? startDate, DateTime? endDate}) async {
    final token = authProvider.token;
    if (token == null) {
      throw Exception('No valid token found');
    }
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    String url = '${ApiConfig.baseUrl}/attendance/summary/$userId';
    final queryParams = <String, String>{};
    if (startDate != null) queryParams['start'] = startDate.toIso8601String();
    if (endDate != null) queryParams['end'] = endDate.toIso8601String();
    if (queryParams.isNotEmpty) {
      url += '?${Uri(queryParameters: queryParams).query}';
    }
    final response = await http.get(Uri.parse(url), headers: headers);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch attendance summary: ${response.statusCode} ${response.body}');
    }
  }

  Future<String> getAttendanceStatus(String userId) async {
    final token = authProvider.token;
    if (token == null) {
      throw Exception('No valid token found');
    }
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final url = '${ApiConfig.baseUrl}/attendance/status/$userId';
    final response = await http.get(Uri.parse(url), headers: headers);
    print('DEBUG: Response from attendance status endpoint: ${response.body}');
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('DEBUG: Parsed attendance status data: $data');
      return data['status'] as String;
    } else {
      print('DEBUG: Failed to fetch attendance status: ${response.statusCode} ${response.body}');
      throw Exception('Failed to fetch attendance status: \${response.statusCode} \${response.body}');
    }
  }
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'api_service.dart';

class AuthService {
  static const String _userKey = 'currentUser';
  final ApiService _apiService = ApiService();
  
  Future<User?> login(String username, String password, String role) async {
    final response = await _apiService.login(username, password, role);

    if (response != null && response['status'] == 'success') {
      final userData = response['user'];
      final user = User(
        username: userData['username'],
        role: userData['role'],
        name: userData['name'],
      );
      await _saveUser(user);
      return user;
    }
    return null;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString(_userKey);
    if (userStr != null) {
      try {
        final user = User.fromJson(jsonDecode(userStr));
        final baseUrl = await _apiService.getBaseUrl();
        // Notify backend of logout
        await _apiService.post('/api/logout', {'username': user.username});
      } catch (e) {
        print('Error during backend logout: $e');
      }
    }
    await prefs.remove(_userKey);
  }

  Future<User?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString(_userKey);
    if (userStr != null) {
      return User.fromJson(jsonDecode(userStr));
    }
    return null;
  }

  Future<void> _saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../network/api_config.dart';
import 'student_auth_store.dart';

class StudentAuthService {
  const StudentAuthService({
    required this.baseUri,
    required this.store,
    http.Client? client,
  }) : _client = client;

  final Uri baseUri;
  final StudentAuthStore store;
  final http.Client? _client;

  Future<StudentLoginResult> login({
    required String rollNumber,
    required String password,
  }) async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            baseUri.resolve('/api/v1/student/auth/login'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'roll_number': rollNumber,
              'password': password,
            }),
          )
          .timeout(apiRequestTimeout);
      if (response.statusCode != 200) {
        throw StateError(_messageFrom(response.body));
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final session = StudentAuthSession(
        accessToken: json['access_token'] as String,
        studentId: json['id'] as String,
        rollNumber: json['roll_number'] as String,
      );
      await store.save(session);
      return StudentLoginResult(
        session: session,
        mustChangePassword: json['must_change_password'] as bool? ?? false,
      );
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            baseUri.resolve('/api/v1/student/auth/password'),
            headers: {
              'content-type': 'application/json',
              ...await store.authorizationHeaders(),
            },
            body: jsonEncode({
              'current_password': currentPassword,
              'new_password': newPassword,
            }),
          )
          .timeout(apiRequestTimeout);
      if (response.statusCode != 200) {
        throw StateError(_messageFrom(response.body));
      }
      await store.clear();
    } finally {
      if (_client == null) client.close();
    }
  }

  String _messageFrom(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>?;
      return error?['message'] as String? ?? 'Sign in could not be completed.';
    } catch (_) {
      return 'Sign in could not be completed.';
    }
  }
}

class StudentLoginResult {
  const StudentLoginResult({
    required this.session,
    required this.mustChangePassword,
  });

  final StudentAuthSession session;
  final bool mustChangePassword;
}

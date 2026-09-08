import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StudentAuthSession {
  const StudentAuthSession({
    required this.accessToken,
    required this.studentId,
    required this.rollNumber,
  });

  final String accessToken;
  final String studentId;
  final String rollNumber;

  Map<String, String> get authorizationHeader => {
        'Authorization': 'Bearer $accessToken',
      };
}

/// Stores only the opaque server session. Attendance private keys are stored
/// separately and never travel in an API request or device-transfer QR.
class StudentAuthStore {
  StudentAuthStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.unlocked_this_device,
                synchronizable: false,
                accountName: 'in.ac.kiit.attendance.student-session',
              ),
            );

  static const _key = 'student_auth_session_v1';
  final FlutterSecureStorage _storage;

  Future<void> save(StudentAuthSession session) => _storage.write(
        key: _key,
        value: jsonEncode({
          'access_token': session.accessToken,
          'student_id': session.studentId,
          'roll_number': session.rollNumber,
        }),
      );

  Future<StudentAuthSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final token = json['access_token'];
      final studentId = json['student_id'];
      final roll = json['roll_number'];
      if (token is! String || studentId is! String || roll is! String) {
        return null;
      }
      return StudentAuthSession(
        accessToken: token,
        studentId: studentId,
        rollNumber: roll,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> authorizationHeaders() async {
    final session = await read();
    return session?.authorizationHeader ?? const {};
  }

  Future<void> clear() => _storage.delete(key: _key);
}

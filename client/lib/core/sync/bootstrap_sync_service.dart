import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/local_database.dart';
import '../network/api_config.dart';
import '../security/student_auth_store.dart';
import 'bootstrap_models.dart';

class BootstrapSyncService {
  const BootstrapSyncService({
    required this.database,
    required this.baseUri,
    this.authStore,
    http.Client? client,
  }) : _client = client;

  final LocalAttendanceDatabase database;
  final Uri baseUri;
  final StudentAuthStore? authStore;
  final http.Client? _client;

  Future<void> sync() async {
    final client = _client ?? http.Client();
    final authHeaders = await authStore?.authorizationHeaders() ?? const {};
    final student = database.getCurrentStudent();
    final response = await client.get(
      baseUri.resolve('/api/v1/sync/bootstrap'),
      headers: {
        ...authHeaders,
        if (student != null) 'X-Student-Id': student.id,
      },
    ).timeout(apiRequestTimeout);
    if (response.statusCode != 200) {
      throw StateError('bootstrap sync failed: ${response.statusCode}');
    }
    final payload = BootstrapSyncPayload.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    database.applyBootstrap(payload);
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/local_database.dart';
import '../network/api_config.dart';
import 'device_api_models.dart';
import 'device_crypto.dart';
import 'student_auth_store.dart';

class DeviceRegistrationService {
  const DeviceRegistrationService(
      {required this.database,
      required this.keyStore,
      required this.baseUri,
      this.authStore,
      http.Client? client})
      : _client = client;

  final LocalAttendanceDatabase database;
  final DeviceKeyStore keyStore;
  final Uri baseUri;
  final StudentAuthStore? authStore;
  final http.Client? _client;

  Future<DeviceRegistration> enroll(
      {required String studentId,
      required String platform,
      String displayLabel = 'Attendance Device',
      Map<String, dynamic> deviceProfile = const {}}) async {
    final client = _client ?? http.Client();
    try {
      final challenge = await _challenge(
          client, '/api/v1/devices/enrollment/challenge', studentId);
      final payload = await _signedEnrollmentPayload(
          studentId: studentId, challenge: challenge);
      final response = await client
          .post(
            baseUri.resolve('/api/v1/devices/enrollment/complete'),
            headers: {
              'content-type': 'application/json',
              ...await _studentHeaders(studentId)
            },
            body: jsonEncode({
              ...payload,
              'platform': platform,
              'display_label': displayLabel,
              'device_profile': deviceProfile,
              'key_protection': 'PLATFORM_STORED'
            }),
          )
          .timeout(apiRequestTimeout);
      _throwOnError(response);
      final registration =
          DeviceRegistration.fromJson(_responseObject(response));
      database.saveDeviceProjection(_projectionFromRegistration(registration));
      return registration;
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<DeviceRegistration?> currentDevice({required String studentId}) async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(baseUri.resolve('/api/v1/devices/current'),
              headers: await _studentHeaders(studentId))
          .timeout(apiRequestTimeout);
      _throwOnError(response);
      if (response.body.trim() == 'null') return null;
      final registration =
          DeviceRegistration.fromJson(_responseObject(response));
      database.saveDeviceProjection(_projectionFromRegistration(registration));
      return registration;
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<void> requestReplacement(
      {required String studentId,
      required String platform,
      String reason = 'App reinstalled or local credential unavailable',
      String displayLabel = 'Replacement Attendance Device',
      Map<String, dynamic> deviceProfile = const {}}) async {
    final client = _client ?? http.Client();
    try {
      final challenge = await _challenge(
          client, '/api/v1/devices/replacement/challenge', studentId);
      final payload = await _signedEnrollmentPayload(
          studentId: studentId, challenge: challenge);
      final response = await client
          .post(
            baseUri.resolve('/api/v1/devices/replacement-requests'),
            headers: {
              'content-type': 'application/json',
              ...await _studentHeaders(studentId)
            },
            body: jsonEncode({
              ...payload,
              'platform': platform,
              'reason': reason,
              'display_label': displayLabel,
              'device_profile': deviceProfile,
              'key_protection': 'PLATFORM_STORED'
            }),
          )
          .timeout(apiRequestTimeout);
      _throwOnError(response);
      if (_responseObject(response)['status'] != 'PENDING') {
        throw StateError('Replacement request was not queued for ICT review.');
      }
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<DeviceRegistration> consumeReplacementActivation(
      {required String studentId, required String qrPayload}) async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            baseUri.resolve('/api/v1/devices/replacement-activation/consume'),
            headers: {
              'content-type': 'application/json',
              ...await _studentHeaders(studentId),
            },
            body: jsonEncode({'qr_payload': qrPayload}),
          )
          .timeout(apiRequestTimeout);
      _throwOnError(response);
      final registration =
          DeviceRegistration.fromJson(_responseObject(response));
      database.saveDeviceProjection(_projectionFromRegistration(registration));
      return registration;
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<void> verify(
      {required String studentId, required String deviceRegistrationId}) async {
    final projection = database.getDeviceProjection();
    final signer = await keyStore.loadSigner();
    if (projection == null || signer == null) {
      throw StateError('Local device credential is unavailable.');
    }
    final client = _client ?? http.Client();
    try {
      final challengeResponse = await client
          .post(
            baseUri.resolve('/api/v1/devices/verification/challenge'),
            headers: {
              'content-type': 'application/json',
              ...await _studentHeaders(studentId)
            },
            body: jsonEncode({'device_registration_id': deviceRegistrationId}),
          )
          .timeout(apiRequestTimeout);
      _throwOnError(challengeResponse);
      final challenge =
          DeviceChallenge.fromJson(_responseObject(challengeResponse));
      final signature = await signer.sign(canonicalVerificationPayload(
          studentId: studentId,
          deviceRegistrationId: deviceRegistrationId,
          challengeId: challenge.challengeId,
          challenge: challenge.challenge,
          issuedAt: challenge.issuedAt,
          publicKeyFingerprint: projection.keyFingerprint));
      final response = await client
          .post(
            baseUri.resolve('/api/v1/devices/verification/complete'),
            headers: {
              'content-type': 'application/json',
              ...await _studentHeaders(studentId)
            },
            body: jsonEncode({
              'challenge_id': challenge.challengeId,
              'device_registration_id': deviceRegistrationId,
              'signature': signature
            }),
          )
          .timeout(apiRequestTimeout);
      _throwOnError(response);
      database.saveDeviceProjection(DeviceRegistrationProjection(
          deviceRegistrationId: projection.deviceRegistrationId,
          studentId: projection.studentId,
          status: projection.status,
          keyFingerprint: projection.keyFingerprint,
          platform: projection.platform,
          displayLabel: projection.displayLabel,
          lastVerifiedAt: DateTime.now().toUtc().toIso8601String(),
          serverVersion: projection.serverVersion));
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<DeviceChallenge> _challenge(
      http.Client client, String path, String studentId) async {
    final response = await client
        .post(baseUri.resolve(path), headers: await _studentHeaders(studentId))
        .timeout(apiRequestTimeout);
    _throwOnError(response);
    return DeviceChallenge.fromJson(_responseObject(response));
  }

  Future<Map<String, String>> _signedEnrollmentPayload(
      {required String studentId, required DeviceChallenge challenge}) async {
    final signer = await keyStore.generateSigner();
    final publicKey = await signer.publicKey();
    final fingerprint = await signer.keyFingerprint();
    final signature = await signer.sign(canonicalEnrollmentPayload(
        studentId: studentId,
        challengeId: challenge.challengeId,
        challenge: challenge.challenge,
        issuedAt: challenge.issuedAt,
        publicKeyFingerprint: fingerprint));
    return {
      'challenge_id': challenge.challengeId,
      'public_key': publicKey,
      'public_key_algorithm': supportedDeviceAlgorithm,
      'signature': signature
    };
  }

  DeviceRegistrationProjection _projectionFromRegistration(
          DeviceRegistration registration) =>
      DeviceRegistrationProjection(
          deviceRegistrationId: registration.id,
          studentId: registration.studentId,
          status: registration.status,
          keyFingerprint: registration.keyFingerprint,
          platform: registration.platform,
          displayLabel: registration.displayLabel,
          lastVerifiedAt: registration.lastSeenAt,
          serverVersion: 1);
  Future<Map<String, String>> _studentHeaders(String studentId) async {
    final headers = await authStore?.authorizationHeaders() ?? const {};
    return {
      ...headers,
      if (headers.isEmpty) 'X-Student-Id': studentId,
    };
  }

  Map<String, dynamic> _responseObject(http.Response response) {
    final parsed = jsonDecode(response.body);
    if (parsed is! Map<String, dynamic>) {
      throw const DeviceApiException(
          code: 'MALFORMED_DEVICE_RESPONSE',
          message: 'The device service returned an invalid response.',
          statusCode: 502);
    }
    return parsed;
  }

  void _throwOnError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    Map<String, dynamic> decoded = const {};
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) decoded = parsed;
    } catch (_) {}
    final error = decoded['error'] as Map<String, dynamic>? ?? const {};
    throw DeviceApiException(
        code: error['code'] as String? ?? 'DEVICE_API_ERROR',
        message:
            error['message'] as String? ?? 'Device service request failed.',
        statusCode: response.statusCode);
  }
}

class DeviceApiException implements Exception {
  const DeviceApiException(
      {required this.code, required this.message, required this.statusCode});
  final String code;
  final String message;
  final int statusCode;
  @override
  String toString() => '$code: $message';
}

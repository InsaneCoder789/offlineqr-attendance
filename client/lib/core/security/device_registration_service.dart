import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/local_database.dart';
import '../network/api_config.dart';
import 'device_api_models.dart';
import 'device_crypto.dart';

class DeviceRegistrationService {
  const DeviceRegistrationService({
    required this.database,
    required this.keyStore,
    required this.baseUri,
    http.Client? client,
  }) : _client = client;

  final LocalAttendanceDatabase database;
  final DeviceKeyStore keyStore;
  final Uri baseUri;
  final http.Client? _client;

  Future<DeviceRegistration> enroll({
    required String studentId,
    required String platform,
    String displayLabel = 'Development Device',
  }) async {
    final client = _client ?? http.Client();
    final challengeResponse = await client
        .post(
          baseUri.resolve('/api/v1/devices/enrollment/challenge'),
          headers: _studentHeaders(studentId),
        )
        .timeout(apiRequestTimeout);
    _throwOnError(challengeResponse);
    final challenge = DeviceChallenge.fromJson(
      jsonDecode(challengeResponse.body) as Map<String, dynamic>,
    );

    final signer = await keyStore.generateSigner();
    final publicKey = await signer.publicKey();
    final fingerprint = await signer.keyFingerprint();
    final signature = await signer.sign(
      canonicalEnrollmentPayload(
        studentId: studentId,
        challengeId: challenge.challengeId,
        challenge: challenge.challenge,
        issuedAt: challenge.issuedAt,
        publicKeyFingerprint: fingerprint,
      ),
    );
    final response = await client
        .post(
          baseUri.resolve('/api/v1/devices/enrollment/complete'),
          headers: {
            'content-type': 'application/json',
            ..._studentHeaders(studentId)
          },
          body: jsonEncode({
            'challenge_id': challenge.challengeId,
            'public_key': publicKey,
            'public_key_algorithm': supportedDeviceAlgorithm,
            'signature': signature,
            'platform': platform,
            'display_label': displayLabel,
            'key_protection': 'SOFTWARE_PROTECTED',
          }),
        )
        .timeout(apiRequestTimeout);
    _throwOnError(response);
    final registration = DeviceRegistration.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    database.saveDeviceProjection(_projectionFromRegistration(registration));
    return registration;
  }

  Future<DeviceRegistration?> currentDevice({required String studentId}) async {
    final client = _client ?? http.Client();
    final response = await client
        .get(
          baseUri.resolve('/api/v1/devices/current'),
          headers: _studentHeaders(studentId),
        )
        .timeout(apiRequestTimeout);
    _throwOnError(response);
    if (response.body == 'null') {
      return null;
    }
    final registration = DeviceRegistration.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    database.saveDeviceProjection(_projectionFromRegistration(registration));
    return registration;
  }

  Future<DeviceRegistration> requestReplacement({
    required String studentId,
    required String platform,
    String reason = 'App reinstalled or local credential unavailable',
    String displayLabel = 'Relinked Device',
  }) async {
    final client = _client ?? http.Client();
    final challengeResponse = await client
        .post(
          baseUri.resolve('/api/v1/devices/replacement/challenge'),
          headers: _studentHeaders(studentId),
        )
        .timeout(apiRequestTimeout);
    _throwOnError(challengeResponse);
    final challenge = DeviceChallenge.fromJson(
      jsonDecode(challengeResponse.body) as Map<String, dynamic>,
    );

    final signer = await keyStore.generateSigner();
    final publicKey = await signer.publicKey();
    final fingerprint = await signer.keyFingerprint();
    final signature = await signer.sign(
      canonicalEnrollmentPayload(
        studentId: studentId,
        challengeId: challenge.challengeId,
        challenge: challenge.challenge,
        issuedAt: challenge.issuedAt,
        publicKeyFingerprint: fingerprint,
      ),
    );
    final response = await client
        .post(
          baseUri.resolve('/api/v1/devices/replacement-requests'),
          headers: {
            'content-type': 'application/json',
            ..._studentHeaders(studentId)
          },
          body: jsonEncode({
            'challenge_id': challenge.challengeId,
            'public_key': publicKey,
            'public_key_algorithm': supportedDeviceAlgorithm,
            'signature': signature,
            'platform': platform,
            'reason': reason,
            'display_label': displayLabel,
            'key_protection': 'SOFTWARE_PROTECTED',
          }),
        )
        .timeout(apiRequestTimeout);
    _throwOnError(response);
    final replacement = jsonDecode(response.body) as Map<String, dynamic>;
    final approvalResponse = await client
        .post(
          baseUri.resolve(
            '/api/v1/devices/replacement-requests/${replacement['id']}/approve',
          ),
          headers: _studentHeaders(studentId),
        )
        .timeout(apiRequestTimeout);
    _throwOnError(approvalResponse);
    final registration = await currentDevice(studentId: studentId);
    if (registration == null) {
      throw StateError(
          'Replacement approved, but no active device was returned.');
    }
    return registration;
  }

  Future<void> verify({
    required String studentId,
    required String deviceRegistrationId,
  }) async {
    final client = _client ?? http.Client();
    final projection = database.getDeviceProjection();
    final signer = await keyStore.loadSigner();
    if (projection == null || signer == null) {
      throw StateError('Local device credential is unavailable.');
    }
    final challengeResponse = await client
        .post(
          baseUri.resolve('/api/v1/devices/verification/challenge'),
          headers: {
            'content-type': 'application/json',
            ..._studentHeaders(studentId)
          },
          body: jsonEncode({'device_registration_id': deviceRegistrationId}),
        )
        .timeout(apiRequestTimeout);
    _throwOnError(challengeResponse);
    final challenge = DeviceChallenge.fromJson(
      jsonDecode(challengeResponse.body) as Map<String, dynamic>,
    );
    final signature = await signer.sign(
      canonicalVerificationPayload(
        studentId: studentId,
        deviceRegistrationId: deviceRegistrationId,
        challengeId: challenge.challengeId,
        challenge: challenge.challenge,
        issuedAt: challenge.issuedAt,
        publicKeyFingerprint: projection.keyFingerprint,
      ),
    );
    final response = await client
        .post(
          baseUri.resolve('/api/v1/devices/verification/complete'),
          headers: {
            'content-type': 'application/json',
            ..._studentHeaders(studentId)
          },
          body: jsonEncode({
            'challenge_id': challenge.challengeId,
            'device_registration_id': deviceRegistrationId,
            'signature': signature,
          }),
        )
        .timeout(apiRequestTimeout);
    _throwOnError(response);
    database.saveDeviceProjection(
      DeviceRegistrationProjection(
        deviceRegistrationId: projection.deviceRegistrationId,
        studentId: projection.studentId,
        status: projection.status,
        keyFingerprint: projection.keyFingerprint,
        platform: projection.platform,
        displayLabel: projection.displayLabel,
        lastVerifiedAt: DateTime.now().toUtc().toIso8601String(),
        serverVersion: projection.serverVersion,
      ),
    );
  }

  DeviceRegistrationProjection _projectionFromRegistration(
    DeviceRegistration registration,
  ) {
    return DeviceRegistrationProjection(
      deviceRegistrationId: registration.id,
      studentId: registration.studentId,
      status: registration.status,
      keyFingerprint: registration.keyFingerprint,
      platform: registration.platform,
      displayLabel: registration.displayLabel,
      lastVerifiedAt: registration.lastSeenAt,
      serverVersion: 1,
    );
  }

  Map<String, String> _studentHeaders(String studentId) => {
        'X-Student-Id': studentId,
      };

  void _throwOnError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final error = decoded['error'] as Map<String, dynamic>? ?? {};
    throw DeviceApiException(
      code: error['code'] as String? ?? 'DEVICE_API_ERROR',
      message: error['message'] as String? ?? response.body,
      statusCode: response.statusCode,
    );
  }
}

class DeviceApiException implements Exception {
  const DeviceApiException({
    required this.code,
    required this.message,
    required this.statusCode,
  });

  final String code;
  final String message;
  final int statusCode;

  @override
  String toString() => '$code: $message';
}

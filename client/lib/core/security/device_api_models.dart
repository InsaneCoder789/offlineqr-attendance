class DeviceChallenge {
  const DeviceChallenge({
    required this.challengeId,
    required this.challenge,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String challengeId;
  final String challenge;
  final String issuedAt;
  final String expiresAt;

  factory DeviceChallenge.fromJson(Map<String, dynamic> json) {
    return DeviceChallenge(
      challengeId: json['challenge_id'] as String,
      challenge: json['challenge'] as String,
      issuedAt: json['issued_at'] as String,
      expiresAt: json['expires_at'] as String,
    );
  }
}

class DeviceRegistration {
  const DeviceRegistration({
    required this.id,
    required this.studentId,
    required this.keyFingerprint,
    required this.platform,
    required this.displayLabel,
    required this.status,
    required this.registeredAt,
    required this.lastSeenAt,
  });

  final String id;
  final String studentId;
  final String keyFingerprint;
  final String platform;
  final String? displayLabel;
  final String status;
  final String? registeredAt;
  final String? lastSeenAt;

  factory DeviceRegistration.fromJson(Map<String, dynamic> json) {
    return DeviceRegistration(
      id: json['id'] as String,
      studentId: json['student_id'] as String,
      keyFingerprint: json['key_fingerprint'] as String,
      platform: json['platform'] as String,
      displayLabel: json['display_label'] as String?,
      status: json['status'] as String,
      registeredAt: json['registered_at'] as String?,
      lastSeenAt: json['last_seen_at'] as String?,
    );
  }
}

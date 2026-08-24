import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'encoding.dart';

const supportedDeviceAlgorithm = 'Ed25519';

String canonicalEnrollmentPayload({
  required String studentId,
  required String challengeId,
  required String challenge,
  required String issuedAt,
  required String publicKeyFingerprint,
}) {
  return [
    'DEVICE_ENROLLMENT_V1',
    'student_id:$studentId',
    'challenge_id:$challengeId',
    'challenge:$challenge',
    'issued_at:$issuedAt',
    'public_key_fingerprint:$publicKeyFingerprint',
  ].join('\n');
}

String canonicalVerificationPayload({
  required String studentId,
  required String deviceRegistrationId,
  required String challengeId,
  required String challenge,
  required String issuedAt,
  required String publicKeyFingerprint,
}) {
  return [
    'DEVICE_VERIFICATION_V1',
    'student_id:$studentId',
    'device_registration_id:$deviceRegistrationId',
    'challenge_id:$challengeId',
    'challenge:$challenge',
    'issued_at:$issuedAt',
    'public_key_fingerprint:$publicKeyFingerprint',
  ].join('\n');
}

Future<String> publicKeyFingerprint(String publicKeyB64Url) async {
  final digest = await Sha256().hash(base64UrlNoPaddingDecode(publicKeyB64Url));
  return digest.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

class DeviceSigner {
  DeviceSigner(this._keyPair);

  final SimpleKeyPair _keyPair;
  final Ed25519 _algorithm = Ed25519();

  Future<String> publicKey() async {
    final publicKey = await _keyPair.extractPublicKey();
    return base64UrlNoPadding(publicKey.bytes);
  }

  Future<String> keyFingerprint() async {
    return publicKeyFingerprint(await publicKey());
  }

  Future<String> sign(String canonicalPayload) async {
    final signature = await _algorithm.sign(
      utf8.encode(canonicalPayload),
      keyPair: _keyPair,
    );
    return base64UrlNoPadding(signature.bytes);
  }

  Future<bool> verify(String canonicalPayload, String signatureB64Url) async {
    final public = await _keyPair.extractPublicKey();
    return _algorithm.verify(
      utf8.encode(canonicalPayload),
      signature: Signature(
        base64UrlNoPaddingDecode(signatureB64Url),
        publicKey: public,
      ),
    );
  }
}

abstract class DeviceKeyStore {
  Future<DeviceSigner?> loadSigner();

  Future<DeviceSigner> generateSigner();

  Future<bool> isAvailable();
}

class InMemoryDeviceKeyStore implements DeviceKeyStore {
  InMemoryDeviceKeyStore({List<int>? seed}) : _seed = seed;

  List<int>? _seed;
  final Ed25519 _algorithm = Ed25519();

  @override
  Future<DeviceSigner> generateSigner() async {
    _seed ??= List<int>.generate(
            32, (index) => DateTime.now().microsecondsSinceEpoch + index)
        .map((value) => value & 0xff)
        .toList();
    return DeviceSigner(await _algorithm.newKeyPairFromSeed(_seed!));
  }

  @override
  Future<bool> isAvailable() async => _seed != null;

  @override
  Future<DeviceSigner?> loadSigner() async {
    if (_seed == null) {
      return null;
    }
    return DeviceSigner(await _algorithm.newKeyPairFromSeed(_seed!));
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/security/device_crypto.dart';
import 'package:client/core/security/encoding.dart';

void main() {
  test('Dart signs and verifies shared Ed25519 vector', () async {
    final vector = jsonDecode(
      File('../shared/fixtures/device_enrollment_ed25519_vector.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;

    final keyPair = await Ed25519().newKeyPairFromSeed(
      base64UrlNoPaddingDecode(vector['seed_b64url'] as String),
    );
    final signer = DeviceSigner(keyPair);

    expect(await signer.publicKey(), vector['public_key']);
    expect(await signer.keyFingerprint(), vector['key_fingerprint']);
    expect(
      await signer.sign(vector['canonical_payload'] as String),
      vector['signature'],
    );
    expect(
      await signer.verify(
        vector['canonical_payload'] as String,
        vector['signature'] as String,
      ),
      isTrue,
    );
    expect(
      await signer.verify(
        '${vector['canonical_payload']}tampered',
        vector['signature'] as String,
      ),
      isFalse,
    );
  });
}

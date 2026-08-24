import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_crypto.dart';
import 'encoding.dart';

class SecureStorageDeviceKeyStore implements DeviceKeyStore {
  SecureStorageDeviceKeyStore({
    FlutterSecureStorage? storage,
    String storageKey = 'attendance_device_ed25519_seed_v1',
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _storageKey = storageKey;

  final FlutterSecureStorage _storage;
  final String _storageKey;
  final Ed25519 _algorithm = Ed25519();

  @override
  Future<DeviceSigner> generateSigner() async {
    final existing = await loadSigner();
    if (existing != null) {
      return existing;
    }
    final random = Random.secure();
    final seed = List<int>.generate(32, (_) => random.nextInt(256));
    await _storage.write(key: _storageKey, value: base64UrlNoPadding(seed));
    return DeviceSigner(await _algorithm.newKeyPairFromSeed(seed));
  }

  @override
  Future<bool> isAvailable() async =>
      await _storage.read(key: _storageKey) != null;

  Future<String?> exportSeed() => _storage.read(key: _storageKey);

  Future<void> importSeed(String encodedSeed) async {
    await _storage.write(key: _storageKey, value: encodedSeed);
  }

  Future<void> deleteSeed() => _storage.delete(key: _storageKey);

  @override
  Future<DeviceSigner?> loadSigner() async {
    final encoded = await _storage.read(key: _storageKey);
    if (encoded == null) {
      return null;
    }
    return DeviceSigner(
      await _algorithm.newKeyPairFromSeed(base64UrlNoPaddingDecode(encoded)),
    );
  }
}

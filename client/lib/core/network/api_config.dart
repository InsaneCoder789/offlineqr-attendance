import 'dart:io';

import 'package:flutter/foundation.dart';

const _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
const apiRequestTimeout = Duration(seconds: 8);

Uri apiBaseUri() {
  final baseUri = Uri.parse(
    _configuredApiBaseUrl.isNotEmpty
        ? _configuredApiBaseUrl
        : Platform.isAndroid
            ? 'http://10.0.2.2:8000'
            : 'http://127.0.0.1:8000',
  );
  if (!baseUri.hasScheme || baseUri.host.isEmpty) {
    throw StateError('API_BASE_URL must be an absolute HTTP(S) URL.');
  }
  if (baseUri.scheme != 'http' && baseUri.scheme != 'https') {
    throw StateError('API_BASE_URL must use HTTP or HTTPS.');
  }
  if (kReleaseMode && baseUri.scheme != 'https') {
    throw StateError('Release builds require an HTTPS API_BASE_URL.');
  }
  return baseUri;
}

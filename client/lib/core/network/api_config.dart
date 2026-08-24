import 'dart:io';

const _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
const apiRequestTimeout = Duration(seconds: 8);

Uri apiBaseUri() {
  if (_configuredApiBaseUrl.isNotEmpty) {
    return Uri.parse(_configuredApiBaseUrl);
  }
  return Uri.parse(
    Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000',
  );
}

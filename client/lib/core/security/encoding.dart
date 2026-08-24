import 'dart:convert';
import 'dart:typed_data';

String base64UrlNoPadding(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}

Uint8List base64UrlNoPaddingDecode(String value) {
  final padding = '=' * ((4 - value.length % 4) % 4);
  return base64Url.decode(value + padding);
}

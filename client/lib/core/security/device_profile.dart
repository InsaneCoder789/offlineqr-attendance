import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Collects a deliberately narrow device profile. No MAC address, IMEI, ad ID,
/// serial number, or location is requested or persisted by the attendance app.
class DeviceProfileCollector {
  const DeviceProfileCollector();

  Future<Map<String, dynamic>> collect() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final device = await info.androidInfo;
      return {
        'manufacturer': device.manufacturer,
        'model': device.model,
        'os_version': device.version.release,
        'os_api_level': device.version.sdkInt,
        'app_version': '1.0.0+1',
        'is_physical_device': device.isPhysicalDevice,
        'is_emulator': !device.isPhysicalDevice,
      };
    }
    if (Platform.isIOS) {
      final device = await info.iosInfo;
      return {
        'manufacturer': 'Apple',
        'model': device.utsname.machine,
        'os_version': device.systemVersion,
        'app_version': '1.0.0+1',
        'is_physical_device': device.isPhysicalDevice,
        'is_emulator': !device.isPhysicalDevice,
      };
    }
    return {
      'manufacturer': Platform.operatingSystem,
      'model': 'Unsupported attendance platform',
      'os_version': Platform.operatingSystemVersion,
      'app_version': '1.0.0+1',
      'is_physical_device': false,
      'is_emulator': true,
    };
  }
}

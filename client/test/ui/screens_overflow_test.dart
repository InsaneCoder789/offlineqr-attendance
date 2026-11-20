// Layout stress matrix for the secondary screens (login, profile, device,
// transfer, portals): no overflow or build exceptions at any size/scale.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/database/local_database.dart';
import 'package:client/core/network/api_config.dart';
import 'package:client/core/security/device_registration_service.dart';
import 'package:client/core/security/secure_device_key_store.dart';
import 'package:client/core/security/student_auth_store.dart';
import 'package:client/features/device_security/device_screen.dart';
import 'package:client/features/device_security/device_transfer_page.dart';
import 'package:client/features/student_auth/student_login_page.dart';
import 'package:client/features/student_portals/student_portals_page.dart';
import 'package:client/features/student_profile/student_profile_page.dart';
import 'package:client/ui/product_components.dart';
import 'package:client/ui/product_theme.dart';

import '../support/bootstrap_fixture.dart';

const _sizes = <String, Size>{
  'small-320x568': Size(320, 568),
  'se-375x667': Size(375, 667),
  'android-360x640': Size(360, 640),
  'iphone-390x844': Size(390, 844),
  'pixel-412x915': Size(412, 915),
  'max-430x932': Size(430, 932),
  'tall-360x800': Size(360, 800),
  'fold-closed-280x653': Size(280, 653),
  'tablet-768x1024': Size(768, 1024),
  'landscape-844x390': Size(844, 390),
  'landscape-667x375': Size(667, 375),
  'desktop-1280x800': Size(1280, 800),
};
const _scales = <double>[0.85, 1.0, 1.3, 2.0];

void main() {
  final screens = <String, Widget Function(LocalAttendanceDatabase)>{
    'login': (db) => StudentLoginPage(
          database: db,
          onLoginComplete: () {},
          authStore: StudentAuthStore(),
        ),
    'profile': (db) => StudentProfilePage(database: db),
    'device': (db) => DeviceScreen(database: db),
    'transfer': (db) => DeviceTransferPage(
          database: db,
          keyStore: SecureStorageDeviceKeyStore(),
          service: DeviceRegistrationService(
            database: db,
            keyStore: SecureStorageDeviceKeyStore(),
            baseUri: apiBaseUri(),
            authStore: StudentAuthStore(),
          ),
        ),
    'portals': (db) => const StudentPortalsPage(),
    'empty-state': (db) => const Scaffold(
          body: SizedBox(
            height: 200,
            child: CuteEmptyState(
              title: 'Nothing here yet',
              message: 'Your classes will appear after the next sync.',
            ),
          ),
        ),
  };
  for (final screen in screens.entries) {
    for (final size in _sizes.entries) {
      for (final scale in _scales) {
        testWidgets('${screen.key}: ${size.key} @${scale}x', (tester) async {
          final db = LocalAttendanceDatabase.inMemory();
          addTearDown(db.close);
          db.applyBootstrap(sampleBootstrapPayload());
          tester.view.physicalSize = size.value * 2;
          tester.view.devicePixelRatio = 2;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                  size: size.value, textScaler: TextScaler.linear(scale)),
              child: MaterialApp(
                theme: buildProductTheme(),
                home: screen.value(db),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

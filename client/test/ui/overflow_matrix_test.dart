// Layout stress matrix: every tab of the student shell at many device sizes,
// text scales and themes. Fails on any RenderFlex overflow or build exception.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/database/local_database.dart';
import 'package:client/core/security/device_crypto.dart';
import 'package:client/features/student_shell/student_home.dart';
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
const _tabs = <String>['Timetable', 'Attendance', 'Scan', 'Portals'];

void main() {
  for (final entry in _sizes.entries) {
    for (final scale in _scales) {
      testWidgets('no overflow: ${entry.key} @${scale}x', (tester) async {
        final db = LocalAttendanceDatabase.inMemory();
        addTearDown(db.close);
        db.applyBootstrap(sampleBootstrapPayload());
        tester.view.physicalSize = entry.value * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: entry.value, textScaler: TextScaler.linear(scale)),
            child: MaterialApp(
              theme: buildProductTheme(),
              home: StudentHome(database: db, keyStore: InMemoryDeviceKeyStore()),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: 'initial tab');
        for (final tab in _tabs) {
          final finder = find.text(tab);
          if (finder.evaluate().isEmpty) continue;
          await tester.tap(finder.last, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull, reason: 'tab $tab');
        }
        // Scan history page.
        await tester.tap(find.text('Scan').last, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 400));
        final seeAll = find.text('See all');
        if (seeAll.evaluate().isNotEmpty) {
          await tester.tap(seeAll.first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull, reason: 'scan history');
          Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
          await tester.pump(const Duration(milliseconds: 400));
        }
        // Drill into a course detail page from the Attendance tab.
        await tester.tap(find.text('Attendance').last, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 400));
        final course = find.text('DAA');
        if (course.evaluate().isNotEmpty) {
          await tester.ensureVisible(course.first);
          await tester.tap(course.first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull, reason: "course detail");
        }
      });
    }
  }
}

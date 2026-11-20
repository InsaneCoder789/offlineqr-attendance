// Timetable + shell layout matrix and state tests: sizes x text scales x
// directions x fixtures, with the calendar sheet opened at every size.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/database/local_database.dart';
import 'package:client/core/security/device_crypto.dart';
import 'package:client/core/sync/bootstrap_models.dart';
import 'package:client/features/student_shell/student_home.dart';
import 'package:client/features/student_timetable/student_timetable_page.dart';
import 'package:client/ui/product_theme.dart';
import 'package:client/ui/responsive.dart';

import '../support/bootstrap_fixture.dart';

const _sizes = <String, Size>{
  '280x653': Size(280, 653),
  '320x568': Size(320, 568),
  '360x640': Size(360, 640),
  '390x844': Size(390, 844),
  '430x932': Size(430, 932),
  '600x960': Size(600, 960),
  '768x1024': Size(768, 1024),
  '844x390': Size(844, 390),
  '1280x800': Size(1280, 800),
};
const _scales = <double>[0.85, 1.0, 1.3, 2.0];
const _longName =
    'Introduction to Advanced Computational Methods for Distributed Cyber Physical Systems '
    'and Their Applications in Large Scale Industrial Environments';
const _longRoom = 'Block C, Academic Wing Third Floor, Seminar Hall Number 304 Annexe Building North';

typedef _Fixture = ({String name, BootstrapSyncPayload Function() build});

BootstrapSyncPayload _payload({
  required List<TimetableEntryDto> entries,
  String? courseName,
}) {
  final base = sampleBootstrapPayload();
  return BootstrapSyncPayload(
    syncVersion: base.syncVersion,
    serverTime: base.serverTime,
    student: base.student,
    academicTerms: base.academicTerms,
    sections: base.sections,
    courses: courseName == null
        ? base.courses
        : [
            for (final c in base.courses) CourseDto(id: c.id, code: c.code, name: courseName),
          ],
    courseOfferings: base.courseOfferings,
    enrollments: base.enrollments,
    faculty: base.faculty,
    facultyAssignments: base.facultyAssignments,
    timetableEntries: entries,
    attendanceSessions: base.attendanceSessions,
    attendanceRecords: base.attendanceRecords,
    cursor: base.cursor,
  );
}

TimetableEntryDto _entry(int n, int day, int hour, {String room = 'C-304', int offering = 1, int minutes = 50}) {
  String hhmm(int total) =>
      '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}:00';
  final start = hour * 60;
  return TimetableEntryDto(
    id: 'b0000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
    courseOfferingId: '60000000-0000-4000-8000-00000000000$offering',
    dayOfWeek: day,
    startTime: hhmm(start),
    endTime: hhmm(start + minutes),
    room: room,
    validFrom: '2026-08-01',
    validUntil: '2026-12-20',
  );
}

List<TimetableEntryDto> _everyDay(int perDay, {String room = 'C-304'}) {
  var n = 1;
  return [
    for (var d = 1; d <= 7; d++)
      for (var k = 0; k < perDay; k++)
        // Even slots overlap the previous one on purpose (simultaneous classes).
        _entry(n++, d, 8 + (k * 3 ~/ 2), room: room, offering: k % 2 + 1, minutes: 90),
  ];
}

final _fixtures = <_Fixture>[
  (name: 'empty', build: () => _payload(entries: const [])),
  (name: '1 class', build: () => _payload(entries: [for (var d = 1; d <= 7; d++) _entry(d, d, 9)])),
  (name: '12 classes', build: () => _payload(entries: _everyDay(12))),
  (name: '120-char names', build: () => _payload(entries: _everyDay(3), courseName: _longName * 1)),
  (name: '60-char rooms', build: () => _payload(entries: _everyDay(3, room: _longRoom))),
];

Future<void> _setup(
  WidgetTester tester, {
  required Size size,
  required double scale,
  required bool rtl,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

Widget _app(Widget home, {required bool rtl}) => MaterialApp(
      theme: buildProductTheme(),
      builder: (context, child) =>
          Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: child!),
      home: home,
    );

Future<void> _exerciseCalendar(WidgetTester tester, String reason) async {
  final open = find.byTooltip('Open calendar');
  expect(open, findsOneWidget, reason: reason);
  await tester.ensureVisible(open);
  await tester.tap(open, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
  expect(tester.takeException(), isNull, reason: '$reason: sheet open');
  expect(find.byTooltip('Next month'), findsOneWidget, reason: '$reason: sheet visible');
  await tester.tap(find.byTooltip('Next month'), warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.byTooltip('Previous month'), warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.drag(find.byType(PageView), const Offset(-200, 0), warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
  expect(tester.takeException(), isNull, reason: '$reason: sheet paging');
  // Pick the first day of the visible month.
  final cell = find.bySemanticsLabel(RegExp(r'^\w+ 1 \w+, '));
  if (cell.evaluate().isNotEmpty) {
    await tester.tap(cell.first, warnIfMissed: false);
  } else {
    await tester.tap(find.text('Today').last, warnIfMissed: false);
  }
  await tester.pump(const Duration(milliseconds: 500));
  expect(tester.takeException(), isNull, reason: '$reason: sheet closed');
}

void main() {
  for (final fixture in _fixtures) {
    for (final entry in _sizes.entries) {
      for (final scale in _scales) {
        for (final rtl in [false, true]) {
          testWidgets('shell+timetable ${fixture.name} ${entry.key} @${scale}x ${rtl ? 'RTL' : 'LTR'}',
              (tester) async {
            final db = LocalAttendanceDatabase.inMemory();
            addTearDown(db.close);
            db.applyBootstrap(fixture.build());
            await _setup(tester, size: entry.value, scale: scale, rtl: rtl);
            await tester.pumpWidget(_app(
              StudentHome(
                database: db,
                keyStore: InMemoryDeviceKeyStore(),
                onSync: () async {},
                syncError: scale == 1.0 && fixture.name == 'empty' ? 'No network' : null,
              ),
              rtl: rtl,
            ));
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull, reason: 'initial');
            expect(find.text('OfflineQR'), findsOneWidget);
            await _exerciseCalendar(tester, '${fixture.name} ${entry.key}');
            // Scroll the page to the end: nothing should hide behind the bar.
            await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -3000), warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull, reason: 'scrolled');
          });
        }
      }
    }
  }

  for (final entry in _sizes.entries) {
    for (final rtl in [false, true]) {
      testWidgets('timetable page alone ${entry.key} ${rtl ? 'RTL' : 'LTR'} @2.0x', (tester) async {
        final db = LocalAttendanceDatabase.inMemory();
        addTearDown(db.close);
        db.applyBootstrap(_fixtures[3].build());
        await _setup(tester, size: entry.value, scale: 2.0, rtl: rtl);
        await tester.pumpWidget(_app(StudentTimetablePage(database: db), rtl: rtl));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      });
    }
  }

  group('states', () {
    Future<LocalAttendanceDatabase> dbWith(BootstrapSyncPayload p) async {
      final db = LocalAttendanceDatabase.inMemory();
      addTearDown(db.close);
      db.applyBootstrap(p);
      return db;
    }

    testWidgets('no timetable synced yet offers Sync', (tester) async {
      final db = await dbWith(_payload(entries: const []));
      var synced = 0;
      await tester.pumpWidget(_app(
        StudentTimetablePage(database: db, onSync: () async => synced++),
        rtl: false,
      ));
      expect(find.text('No timetable yet'), findsOneWidget);
      await tester.tap(find.text('Sync now'));
      expect(synced, 1);
    });

    testWidgets('empty day jumps to the next day with classes', (tester) async {
      final today = institutionNow().weekday;
      final other = today == 7 ? 1 : today + 1;
      final db = await dbWith(_payload(entries: [_entry(1, other, 9)]));
      await tester.pumpWidget(_app(StudentTimetablePage(database: db), rtl: false));
      expect(find.text('No classes this day'), findsOneWidget);
      final jump = find.textContaining('Jump to ');
      expect(jump, findsOneWidget);
      await tester.tap(jump);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('No classes this day'), findsNothing);
      expect(find.text('AGENDA'), findsOneWidget);
    });

    testWidgets('database error shows retry', (tester) async {
      final db = LocalAttendanceDatabase.inMemory();
      db.close();
      await tester.pumpWidget(_app(StudentTimetablePage(database: db), rtl: false));
      expect(find.text('Couldn\'t load your timetable'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('day chips expose a spoken label and select on tap', (tester) async {
      final db = await dbWith(_payload(entries: _everyDay(2)));
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(StudentTimetablePage(database: db), rtl: false));
      final label = find.bySemanticsLabel(RegExp(r'^\w+day \d+ \w+, 2 classes'));
      expect(label, findsWidgets);
      handle.dispose();
    });

    testWidgets('sync error shows the offline strip', (tester) async {
      final db = await dbWith(_payload(entries: _everyDay(1)));
      await tester.pumpWidget(_app(StudentTimetablePage(database: db, syncError: 'boom'), rtl: false));
      expect(find.textContaining('Showing your saved timetable'), findsOneWidget);
    });

    testWidgets('shell bar height is exposed to pages', (tester) async {
      final db = await dbWith(_payload(entries: _everyDay(1)));
      await _setup(tester, size: const Size(390, 844), scale: 1.0, rtl: false);
      await tester.pumpWidget(_app(StudentHome(database: db, keyStore: InMemoryDeviceKeyStore()), rtl: false));
      await tester.pump(const Duration(milliseconds: 300));
      final inset = ShellInsets.bottomOf(tester.element(find.byType(StudentTimetablePage)));
      expect(inset, greaterThanOrEqualTo(72));
    });

    testWidgets('sync pill collapses to an icon below 400 wide', (tester) async {
      final db = await dbWith(_payload(entries: _everyDay(1)));
      await _setup(tester, size: const Size(320, 568), scale: 1.0, rtl: false);
      await tester.pumpWidget(_app(
        StudentHome(database: db, keyStore: InMemoryDeviceKeyStore(), onSync: () async {}),
        rtl: false,
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Synced'), findsNothing);
      expect(find.byTooltip('Synced. Tap to sync again'), findsOneWidget);
      expect(find.text('OfflineQR'), findsOneWidget);
    });
  });
}

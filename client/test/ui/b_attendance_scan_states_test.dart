// Layout + state matrix for the student Attendance, Scan and Portals screens
// (plus course detail, scan history, result sheet and camera overlays):
// no exception or overflow at any size / text scale / direction, for every
// data shape the screens can meet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/database/local_database.dart';
import 'package:client/core/security/secure_device_key_store.dart';
import 'package:client/core/sync/bootstrap_models.dart';
import 'package:client/features/student_attendance/student_attendance_page.dart';
import 'package:client/features/student_portals/student_portals_page.dart';
import 'package:client/features/student_scan/student_scan_page.dart';
import 'package:client/ui/dark_kit.dart';
import 'package:client/ui/product_theme.dart';

import '../support/bootstrap_fixture.dart';

const _sizes = <String, Size>{
  'fold-280x653': Size(280, 653),
  'small-320x568': Size(320, 568),
  'android-360x640': Size(360, 640),
  'iphone-390x844': Size(390, 844),
  'max-430x932': Size(430, 932),
  'medium-600x960': Size(600, 960),
  'tablet-768x1024': Size(768, 1024),
  'landscape-844x390': Size(844, 390),
  'desktop-1280x800': Size(1280, 800),
};
const _scales = <double>[0.85, 1.0, 1.3, 2.0];
const _studentId = '50000000-0000-4000-8000-000000000001';
const _termId = '10000000-0000-4000-8000-000000000001';
const _sectionId = '20000000-0000-4000-8000-000000000021';

/// (present, absent) per course; names / codes optional overrides.
BootstrapSyncPayload _payload({
  required List<(int, int)> courses,
  List<String>? names,
  List<String>? codes,
}) {
  final base = sampleBootstrapPayload();
  final dtoCourses = <CourseDto>[];
  final offerings = <CourseOfferingDto>[];
  final enrollments = <EnrollmentDto>[];
  final sessions = <AttendanceSessionDto>[];
  final records = <AttendanceRecordDto>[];
  for (var c = 0; c < courses.length; c++) {
    final code = codes != null ? codes[c] : 'CS${1000 + c}';
    final name = names != null ? names[c] : 'Course number $c';
    dtoCourses.add(CourseDto(id: 'course-$c', code: code, name: name));
    offerings.add(CourseOfferingDto(
        id: 'offering-$c',
        courseId: 'course-$c',
        academicTermId: _termId,
        sectionId: _sectionId));
    enrollments.add(EnrollmentDto(
        id: 'enrol-$c',
        studentId: _studentId,
        courseOfferingId: 'offering-$c'));
    final (present, absent) = courses[c];
    for (var i = 0; i < present + absent; i++) {
      final isPresent = i < present;
      // Interleave so both statuses appear in every month.
      final day = DateTime.utc(2025, 1, 6)
          .add(Duration(days: i, hours: 4, minutes: 30));
      final start = day.toIso8601String().replaceAll('.000', '');
      sessions.add(AttendanceSessionDto(
        id: 'sess-$c-$i',
        courseOfferingId: 'offering-$c',
        scheduledStart: start,
        scheduledEnd: day
            .add(const Duration(hours: 1))
            .toIso8601String()
            .replaceAll('.000', ''),
        state: 'CLOSED',
      ));
      records.add(AttendanceRecordDto(
        id: 'rec-$c-$i',
        attendanceSessionId: 'sess-$c-$i',
        studentId: _studentId,
        status: isPresent ? 'PRESENT' : 'ABSENT',
        method: isPresent
            ? (i.isEven ? 'DYNAMIC_QR' : 'FACULTY_ATTESTATION')
            : null,
        recordedAt: start,
      ));
    }
  }
  return BootstrapSyncPayload(
    syncVersion: 1,
    serverTime: '2026-08-18T10:00:00Z',
    student: base.student,
    academicTerms: base.academicTerms,
    sections: base.sections,
    courses: dtoCourses,
    courseOfferings: offerings,
    enrollments: enrollments,
    faculty: const [],
    facultyAssignments: const [],
    timetableEntries: const [],
    attendanceSessions: sessions,
    attendanceRecords: records,
    cursor: 'fixture',
  );
}

String _long(String seed, int n) =>
    List.generate(n, (i) => seed).join(' ').substring(0, n);

class _Fixture {
  const _Fixture(this.name, this.build, {this.detailCode = 'CS1000'});

  final String name;
  final void Function(LocalAttendanceDatabase db) build;
  final String detailCode;
}

void _failedScans(LocalAttendanceDatabase db) {
  db.applyBootstrap(_payload(courses: [(6, 2), (3, 3), (5, 0)]));
  void scan(int i, String session, void Function(String proofId) finish) {
    final now = '2026-08-18T10:0$i:00Z';
    db.saveAttendanceClaim(AttendanceClaimProjection(
      claimId: 'claim-$i',
      sessionId: session,
      studentId: _studentId,
      deviceRegistrationId: 'device-1',
      qrEpoch: 1,
      qrChallenge: 'c',
      qrIssuedAt: now,
      qrExpiresAt: now,
      qrSignature: 's',
      qrCapturedAt: now,
      claimCreatedAt: now,
      claimExpiresAt: now,
      claimState: 'PROOF_READY',
      deviceSignature: 'd',
    ));
    db.saveProofAndEnqueueOutbox(
      proofId: 'proof-$i',
      claimId: 'claim-$i',
      sessionId: session,
      studentId: _studentId,
      deviceRegistrationId: 'device-1',
      payloadJson: '{}',
      createdAt: now,
    );
    finish('proof-$i');
  }

  scan(
      1,
      'sess-0-7',
      (p) => db.markProofRejected(
          proofId: p,
          now: '2026-08-18T10:09:00Z',
          errorCode: _long('SERVER_REJECTED_DEVICE_SIGNATURE_MISMATCH', 140)
              .replaceAll(' ', '_')));
  scan(
      2,
      'sess-1-1',
      (p) => db.markProofRejected(
          proofId: p, now: '2026-08-18T10:09:00Z', errorCode: 'X'));
  scan(3, 'sess-1-2', (_) {});
  scan(
      4,
      'sess-2-0',
      (p) => db.markProofAccepted(
            proofId: p,
            attendanceRecordId: 'rec-2-0',
            sessionId: 'sess-2-0',
            studentId: _studentId,
            deviceRegistrationId: 'device-1',
            method: 'SECURE_PROOF',
            recordedAt: '2026-08-18T10:09:00Z',
            now: '2026-08-18T10:09:00Z',
          ));
}

final _fixtures = <_Fixture>[
  _Fixture('no-data', (db) {}, detailCode: 'NOPE'),
  _Fixture(
      'one-course', (db) => db.applyBootstrap(_payload(courses: [(2, 1)]))),
  _Fixture('forty-courses', (db) {
    db.applyBootstrap(
        _payload(courses: [for (var i = 0; i < 40; i++) (3 + i % 7, i % 5)]));
  }),
  _Fixture('long-names', (db) {
    db.applyBootstrap(_payload(
      courses: [(3, 4), (9, 1)],
      names: [_long('Interdisciplinary Computational Methods', 140), 'W' * 120],
      codes: ['LONGCODE-ABCDEFGHIJ-0001', 'X' * 40],
    ));
  }, detailCode: 'LONGCODE-ABCDEFGHIJ-0001'),
  _Fixture('history-500', (db) {
    db.applyBootstrap(_payload(courses: [(300, 200), (4, 1)]));
  }),
  _Fixture(
      'pct-0', (db) => db.applyBootstrap(_payload(courses: [(0, 6), (0, 2)]))),
  _Fixture(
      'pct-74.9', (db) => db.applyBootstrap(_payload(courses: [(749, 251)]))),
  _Fixture('pct-100',
      (db) => db.applyBootstrap(_payload(courses: [(8, 0), (3, 0)]))),
  const _Fixture('failed-scans', _failedScans),
];

Widget _app(Widget home,
    {required double scale, required TextDirection dir, Key? key}) {
  return MaterialApp(
    key: key,
    theme: buildProductTheme(),
    builder: (context, child) {
      final media = MediaQuery.of(context);
      return Directionality(
        textDirection: dir,
        child: MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      );
    },
    home: home,
  );
}

Future<void> _matrix(
  WidgetTester tester,
  Widget Function() home, {
  bool scroll = true,
}) async {
  addTearDown(tester.view.reset);
  var n = 0;
  for (final size in _sizes.entries) {
    for (final scale in _scales) {
      for (final dir in TextDirection.values) {
        n++;
        final label = '${size.key} @${scale}x ${dir.name}';
        tester.view.physicalSize = size.value * 2;
        tester.view.devicePixelRatio = 2;
        await tester
            .pumpWidget(_app(home(), scale: scale, dir: dir, key: ValueKey(n)));
        await tester.pump(const Duration(milliseconds: 450));
        expect(tester.takeException(), isNull, reason: label);
        if (scroll) {
          final scrollables = find.byType(Scrollable);
          if (scrollables.evaluate().isNotEmpty) {
            for (var i = 0; i < 3; i++) {
              await tester.drag(scrollables.first, const Offset(0, -2500),
                  warnIfMissed: false);
              await tester.pump(const Duration(milliseconds: 400));
            }
            expect(tester.takeException(), isNull, reason: '$label (scrolled)');
          }
        }
      }
    }
  }
}

void main() {
  final keyStore = SecureStorageDeviceKeyStore();

  for (final fx in _fixtures) {
    group('fixture ${fx.name}', () {
      late LocalAttendanceDatabase db;
      setUp(() {
        db = LocalAttendanceDatabase.inMemory();
        fx.build(db);
      });
      tearDown(() => db.close());

      testWidgets('attendance', (tester) async {
        await _matrix(tester, () => StudentAttendancePage(database: db));
      });
      testWidgets('attendance with stale strip', (tester) async {
        await _matrix(
          tester,
          () => StudentAttendancePage(
              database: db,
              staleNotice:
                  'You are offline. Last synced a very long time ago, so numbers may be out of date.'),
          scroll: false,
        );
      });
      testWidgets('course detail', (tester) async {
        await _matrix(
            tester,
            () => SubjectAttendanceDetailPage(
                database: db, courseCode: fx.detailCode));
      });
      testWidgets('scan', (tester) async {
        await _matrix(
            tester, () => StudentScanPage(database: db, keyStore: keyStore));
      });
      testWidgets('scan history', (tester) async {
        await _matrix(tester, () => ScanHistoryPage(database: db));
      });
    });
  }

  group('standalone states', () {
    testWidgets('portals: not configured, configured, open failure',
        (tester) async {
      await _matrix(tester, () => const StudentPortalsPage());
      await _matrix(
        tester,
        () => StudentPortalsPage(
          academicPortalUri: Uri.parse(
              'https://academic.example-university-with-a-very-long-hostname.edu.in/portal'),
          learningPortalUri: Uri.parse('https://lms.example.edu'),
        ),
      );
    });

    testWidgets('loading skeleton', (tester) async {
      await _matrix(
          tester,
          () => const Scaffold(
              body: SafeArea(
                  child: SingleChildScrollView(
                      child: Padding(
                          padding: EdgeInsets.all(16),
                          child: AttendanceLoadingView())))),
          scroll: false);
    });

    for (final kind in ScanResultKind.values) {
      testWidgets('scan result sheet ${kind.name}', (tester) async {
        await _matrix(
          tester,
          () => Scaffold(
            body: ScanResultSheet(
              kind: kind,
              courseName: _long('Design and Analysis of Algorithms', 130),
              reason:
                  'This QR code expired ${_long('because it was scanned too late', 200)} ERR_${'Z' * 90}',
            ),
          ),
          scroll: false,
        );
      });
    }

    for (final kind in ScannerCameraProblem.values) {
      testWidgets('camera overlay ${kind.name}', (tester) async {
        await _matrix(
          tester,
          () => Scaffold(
            body: ScannerCameraOverlay(
                kind: kind,
                detail: 'permissionDenied_${'q' * 120}',
                onRetry: () {}),
          ),
          scroll: false,
        );
      });
    }

    testWidgets('GlowRing renders a full ring without exceptions',
        (tester) async {
      await tester.pumpWidget(_app(
        const Scaffold(
          body: Center(
              child: GlowRing(
                  value: 100, size: 120, stroke: 11, child: Text('100%'))),
        ),
        scale: 1,
        dir: TextDirection.ltr,
      ));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(_app(
        const Scaffold(
          body: Center(child: GlowRing(value: 99.95, size: 120, stroke: 11)),
        ),
        scale: 1,
        dir: TextDirection.ltr,
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('behaviour', () {
    late LocalAttendanceDatabase db;
    setUp(() {
      db = LocalAttendanceDatabase.inMemory()
        ..applyBootstrap(sampleBootstrapPayload());
    });
    tearDown(() => db.close());

    testWidgets('first course card is visible on a 360x640 phone',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(StudentAttendancePage(database: db),
          scale: 1, dir: TextDirection.ltr));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('DAA'), findsOneWidget);
      expect(tester.getTopLeft(find.text('DAA')).dy, lessThan(560));
      expect(find.text('67%'), findsWidgets);
      expect(find.textContaining('2 present'), findsOneWidget);
    });

    testWidgets('sort toggle reorders courses', (tester) async {
      final many = LocalAttendanceDatabase.inMemory()
        ..applyBootstrap(_payload(
          courses: [(1, 9), (9, 1)],
          names: ['Zebra studies', 'Alpha studies'],
        ));
      addTearDown(many.close);
      tester.view.physicalSize = const Size(390, 1400) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(StudentAttendancePage(database: many),
          scale: 1, dir: TextDirection.ltr));
      await tester.pump(const Duration(milliseconds: 450));
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      // Lowest first: Zebra (10%) above Alpha (90%).
      expect(y('Zebra studies'), lessThan(y('Alpha studies')));
      await tester.tap(find.text('A to Z'));
      await tester.pump(const Duration(milliseconds: 450));
      expect(y('Alpha studies'), lessThan(y('Zebra studies')));
      await tester.tap(find.text('Lowest first'));
      await tester.pump(const Duration(milliseconds: 450));
      expect(y('Zebra studies'), lessThan(y('Alpha studies')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('database error shows retry, then skeleton, then error again',
        (tester) async {
      final broken = LocalAttendanceDatabase.inMemory();
      broken.close();
      await tester.pumpWidget(_app(StudentAttendancePage(database: broken),
          scale: 1, dir: TextDirection.ltr));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Could not read attendance'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(find.byType(AttendanceLoadingView), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Could not read attendance'), findsOneWidget);
    });

    testWidgets('no student shows the synced-nothing state', (tester) async {
      final empty = LocalAttendanceDatabase.inMemory();
      addTearDown(empty.close);
      await tester.pumpWidget(_app(StudentAttendancePage(database: empty),
          scale: 1, dir: TextDirection.ltr));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Attendance data unavailable'), findsOneWidget);
    });

    testWidgets('course not found offers a way back', (tester) async {
      await tester.pumpWidget(_app(
          SubjectAttendanceDetailPage(database: db, courseCode: 'NOPE'),
          scale: 1,
          dir: TextDirection.ltr));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Course not found'), findsOneWidget);
      expect(find.text('Go back'), findsOneWidget);
    });

    testWidgets('500-row history is lazy and month grouped', (tester) async {
      final big = LocalAttendanceDatabase.inMemory()
        ..applyBootstrap(_payload(courses: [(300, 200)]));
      addTearDown(big.close);
      tester.view.physicalSize = const Size(390, 844) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
          SubjectAttendanceDetailPage(database: big, courseCode: 'CS1000'),
          scale: 1,
          dir: TextDirection.ltr));
      await tester.pump(const Duration(milliseconds: 450));
      // Far fewer than 500 pills are alive: the list is built lazily.
      final built = find.text('Present').evaluate().length +
          find.text('Absent').evaluate().length;
      expect(built, lessThan(60));
      final header = RegExp(r'^[A-Z]+ 20\d\d$');
      expect(
          find.byWidgetPredicate(
              (w) => w is Text && header.hasMatch(w.data ?? '')),
          findsWidgets);
    });

    testWidgets('portals: not set up opens a contact sheet', (tester) async {
      await tester.pumpWidget(
          _app(const StudentPortalsPage(), scale: 1, dir: TextDirection.ltr));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Not set up'), findsNWidgets(2));
      await tester.tap(find.text('Academic portal'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Who to contact'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('portals: open failure becomes an inline error',
        (tester) async {
      await tester.pumpWidget(_app(
        StudentPortalsPage(
          academicPortalUri: Uri.parse('https://academic.example.edu'),
          learningPortalUri: Uri.parse('https://lms.example.edu'),
          launcher: (_) async => false,
        ),
        scale: 1,
        dir: TextDirection.ltr,
      ));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Ready'), findsNWidgets(2));
      await tester.tap(find.text('Academic portal'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('could not be opened'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('scan page keeps its public texts', (tester) async {
      await tester.pumpWidget(_app(
          StudentScanPage(database: db, keyStore: keyStore),
          scale: 1,
          dir: TextDirection.ltr));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('See all'), findsOneWidget);
      expect(find.bySemanticsLabel('Scan attendance QR'), findsOneWidget);
    });

    testWidgets('scan page without a student is disabled but readable',
        (tester) async {
      final empty = LocalAttendanceDatabase.inMemory();
      addTearDown(empty.close);
      await tester.pumpWidget(_app(
          StudentScanPage(database: empty, keyStore: keyStore),
          scale: 1,
          dir: TextDirection.ltr));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Sync required'), findsOneWidget);
      expect(find.text('No scans yet'), findsOneWidget);
    });

    testWidgets('failed scans show a review note with what to do',
        (tester) async {
      final failed = LocalAttendanceDatabase.inMemory();
      _failedScans(failed);
      addTearDown(failed.close);
      tester.view.physicalSize = const Size(390, 1600) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
          StudentScanPage(database: failed, keyStore: keyStore),
          scale: 1,
          dir: TextDirection.ltr));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.textContaining('need review'), findsWidgets);
      expect(find.textContaining('What to do'), findsWidgets);
      expect(find.textContaining('waiting to sync'), findsOneWidget);
    });
  });
}

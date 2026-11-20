// Layout and state matrix for profile, device, transfer, sign-in and launch
// screens: every state at every size / text scale / direction with long-string
// fixtures, plus keyboard-open checks on the forms. Nothing may overflow.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/app_shell_io.dart';
import 'package:client/core/database/local_database.dart';
import 'package:client/core/network/api_config.dart';
import 'package:client/core/security/device_crypto.dart';
import 'package:client/core/security/device_registration_service.dart';
import 'package:client/core/security/secure_device_key_store.dart';
import 'package:client/core/security/student_auth_store.dart';
import 'package:client/core/sync/bootstrap_models.dart';
import 'package:client/features/device_security/device_screen.dart';
import 'package:client/features/device_security/device_transfer_page.dart';
import 'package:client/features/student_auth/student_login_page.dart';
import 'package:client/features/student_profile/student_profile_page.dart';
import 'package:client/ui/dark_kit_extra_b.dart';
import 'package:client/ui/product_components.dart';
import 'package:client/ui/product_theme.dart';
import 'package:client/ui/state_views.dart';

import '../support/bootstrap_fixture.dart';

const _sizes = <String, Size>{
  'fold-280x653': Size(280, 653),
  'small-320x568': Size(320, 568),
  'android-360x640': Size(360, 640),
  'iphone-390x844': Size(390, 844),
  'max-430x932': Size(430, 932),
  'foldable-600x960': Size(600, 960),
  'tablet-768x1024': Size(768, 1024),
  'landscape-844x390': Size(844, 390),
  'desktop-1280x800': Size(1280, 800),
};
const _scales = <double>[0.85, 1.0, 1.3, 2.0];

const _long80 =
    'Maximilian-Alexander Bartholomew Fitzgerald-Montgomery Venkataraman Subramaniam-Iyer III';
final _longEmail =
    '${'very.long.local.part' * 4}@some-extremely-long-department.institution.example.edu';
final _error300 = List.generate(12,
        (i) => 'Request ${i + 1} failed with a very long diagnostic message.')
    .join(' ');

typedef Build = Widget Function(LocalAttendanceDatabase db);

BootstrapSyncPayload _longPayload() {
  final base = sampleBootstrapPayload();
  return BootstrapSyncPayload(
    syncVersion: base.syncVersion,
    serverTime: base.serverTime,
    student: StudentDto(
      id: base.student.id,
      rollNumber: '123456789012',
      institutionalEmail: _longEmail,
      displayName: _long80,
    ),
    academicTerms: base.academicTerms,
    sections: [
      for (final s in base.sections)
        SectionDto(
            id: s.id,
            academicTermId: s.academicTermId,
            code: 'SECTION-${'X' * 50}'),
    ],
    courses: base.courses,
    courseOfferings: base.courseOfferings,
    enrollments: base.enrollments,
    faculty: base.faculty,
    facultyAssignments: base.facultyAssignments,
    timetableEntries: base.timetableEntries,
    attendanceSessions: base.attendanceSessions,
    attendanceRecords: base.attendanceRecords,
    cursor: base.cursor,
  );
}

DeviceRegistrationProjection _projection({String status = 'ACTIVE'}) =>
    DeviceRegistrationProjection(
      deviceRegistrationId: 'reg-1',
      studentId: 's-1',
      status: status,
      keyFingerprint: 'ab' * 32,
      platform: 'Android ${'Pixel-Pro-Max-Ultra-' * 4}',
      displayLabel: _long80,
      lastVerifiedAt: '2026-08-18T10:00:00.000000+00:00 ${'x' * 60}',
      serverVersion: 3,
    );

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required double scale,
  required bool rtl,
  required Widget home,
  double keyboard = 0,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  if (keyboard > 0) {
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 2);
  }
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildProductTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
      ),
      home: home,
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

/// Registers one test per size x scale x direction for [name].
void _matrix(
  String name,
  Build build, {
  BootstrapSyncPayload Function()? payload,
  bool withData = true,
  Future<void> Function(WidgetTester tester)? interact,
}) {
  for (final size in _sizes.entries) {
    for (final scale in _scales) {
      for (final rtl in [false, true]) {
        // RTL only at the extremes of text scale to keep the matrix fast.
        if (rtl && scale != 1.0 && scale != 2.0) continue;
        testWidgets('$name | ${size.key} @${scale}x ${rtl ? 'RTL' : 'LTR'}',
            (tester) async {
          final db = LocalAttendanceDatabase.inMemory();
          addTearDown(db.close);
          if (withData) {
            db.applyBootstrap((payload ?? sampleBootstrapPayload)());
          }
          await _pump(tester,
              size: size.value, scale: scale, rtl: rtl, home: build(db));
          expect(tester.takeException(), isNull);
          if (interact != null) {
            await interact(tester);
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  }
}

Scaffold _page(Widget body, {String title = 'Page'}) =>
    Scaffold(appBar: AppBar(title: Text(title)), body: SafeArea(child: body));

LoginProblem _problem(String raw) => LoginProblem.classify(raw);

StudentLoginView _login({
  String roll = '',
  String password = '',
  bool submitting = false,
  String? rollError,
  String? passwordError,
  LoginProblem? problem,
  bool obscure = true,
}) =>
    StudentLoginView(
      rollController: TextEditingController(text: roll),
      passwordController: TextEditingController(text: password),
      obscurePassword: obscure,
      onToggleObscure: () {},
      submitting: submitting,
      rollError: rollError,
      passwordError: passwordError,
      problem: problem,
      onSubmit: () {},
    );

Widget _passwordForm({
  Future<void> Function(String)? onSubmit,
}) =>
    Material(
      color: ProductColors.surfaceElevated,
      child: SafeArea(
        child: CreatePasswordForm(
          successDelay: const Duration(milliseconds: 50),
          onSubmit: onSubmit ?? (_) async {},
          onDone: () {},
        ),
      ),
    );

void main() {
  group('profile', () {
    _matrix('profile', (db) => StudentProfilePage(database: db));
    _matrix('profile long values', (db) => StudentProfilePage(database: db),
        payload: _longPayload);
    _matrix('profile without account', (db) => StudentProfilePage(database: db),
        withData: false);
    _matrix(
      'profile rows expanded',
      (db) => StudentProfilePage(database: db),
      payload: _longPayload,
      interact: (tester) async {
        for (final row in ['Account', 'Synchronization', 'Offline data']) {
          await tester.ensureVisible(find.text(row));
          await tester.pump();
          await tester.tap(find.text(row));
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        }
      },
    );
    _matrix(
      'profile info sheets',
      (db) => StudentProfilePage(database: db),
      interact: (tester) async {
        for (final row in ['Notifications', 'Help', 'About']) {
          await tester.ensureVisible(find.text(row));
          await tester.pump();
          await tester.tap(find.text(row));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Close'));
          await tester.pump();
          await tester.tap(find.text('Close'));
          await tester.pump(const Duration(milliseconds: 400));
        }
      },
    );

    test('initials come from letter-led words only', () {
      expect(StudentProfilePage.initialsOf('Student 90010001'), 'S');
      expect(StudentProfilePage.initialsOf('Aarav Mehta'), 'AM');
      expect(StudentProfilePage.initialsOf('  '), '?');
      expect(StudentProfilePage.initialsOf('90010001'), '9');
    });

    testWidgets('copy button puts the roll number on the clipboard',
        (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      final db = LocalAttendanceDatabase.inMemory();
      addTearDown(db.close);
      db.applyBootstrap(sampleBootstrapPayload());
      await _pump(tester,
          size: const Size(390, 844),
          scale: 1,
          rtl: false,
          home: StudentProfilePage(database: db));
      await tester.tap(find.text('Account'));
      await tester.pump(const Duration(milliseconds: 300));
      tester
          .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.copy_rounded).at(1))
          .onPressed!();
      await tester.pump(const Duration(milliseconds: 100));
      expect(copied, 'DEV24155001');
    });
  });

  group('device screen', () {
    _matrix('device screen live', (db) => DeviceScreen(database: db));
    for (final kind in DeviceViewKind.values) {
      for (final registered in [false, true]) {
        _matrix(
          'device ${kind.name} ${registered ? 'with' : 'without'} registration',
          (db) => _page(
            DeviceStatusView(
              kind: kind,
              projection: registered ? _projection() : null,
              notice: kind == DeviceViewKind.active ? _error300 : null,
              error: _error300,
              activity: kind == DeviceViewKind.pendingVerification
                  ? 'Verifying this phone'
                  : null,
              busy: kind == DeviceViewKind.pendingVerification,
              onRegister: () {},
              onVerify: () {},
              onRelink: () {},
              onTransfer: () {},
              onRetry: () {},
            ),
            title: 'Attendance Device',
          ),
          withData: false,
        );
      }
    }
  });

  group('transfer', () {
    _matrix(
      'transfer page live',
      (db) => DeviceTransferPage(
        database: db,
        keyStore: SecureStorageDeviceKeyStore(),
        service: DeviceRegistrationService(
          database: db,
          keyStore: SecureStorageDeviceKeyStore(),
          baseUri: apiBaseUri(),
          authStore: StudentAuthStore(),
        ),
      ),
    );
    for (final stage in TransferStage.values) {
      _matrix(
        'transfer stage ${stage.name}',
        (db) => _page(
            DeviceTransferView(stage: stage, onScan: () {}, onBack: () {})),
        withData: false,
      );
    }
    for (final phase in ScannerPhase.values) {
      _matrix(
        'scanner ${phase.name}',
        (db) => ActivationScannerView(
          phase: phase,
          message: _error300,
          camera: const ColoredBox(color: Colors.black12),
          onClose: () {},
          onRetry: () {},
        ),
        withData: false,
      );
    }
    test('stage derives from the device projection', () {
      expect(transferStageFor(null), TransferStage.start);
      expect(transferStageFor(_projection()), TransferStage.complete);
      expect(transferStageFor(_projection(status: 'REVOKED')),
          TransferStage.blocked);
      expect(transferStageFor(_projection(status: 'PENDING_REPLACEMENT')),
          TransferStage.awaitingIct);
    });
  });

  group('login', () {
    final longRoll = '1' * 80;
    final longPass = 'p' * 90;
    final states = <String, StudentLoginView Function()>{
      'idle': () => _login(),
      'filled long': () => _login(roll: longRoll, password: longPass),
      'visible password': () =>
          _login(roll: '90010001', password: longPass, obscure: false),
      'empty roll': () => _login(
          rollError: LoginValidation.rollProblem(''),
          passwordError: LoginValidation.passwordProblem('')),
      'bad format': () => _login(
          roll: 'abc',
          rollError: LoginValidation.rollProblem('abc'),
          password: 'x'),
      'submitting': () =>
          _login(roll: '90010001', password: 'secret', submitting: true),
      'wrong password': () => _login(
          roll: '90010001',
          password: 'x',
          problem: _problem('Invalid roll number or password.')),
      'wrong password attempts': () => _login(
          roll: '90010001',
          password: 'x',
          problem: _problem('Invalid credentials. 2 attempts left')),
      'locked out': () => _login(
          roll: '90010001',
          password: 'x',
          problem: _problem('Account locked for 15 minutes')),
      'locked out unknown': () =>
          _login(problem: _problem('Too many attempts, temporarily blocked')),
      'offline': () =>
          _login(problem: _problem('SocketException: Failed host lookup: api')),
      'server error': () =>
          _login(problem: _problem('HTTP 503 server error: $_error300')),
      'other error long': () => _login(problem: _problem(_error300)),
      'password changed': () => _login(
          problem: _problem(
              'Password changed. Sign in again with your new password.')),
    };
    for (final e in states.entries) {
      _matrix('login ${e.key}', (db) => e.value(), withData: false);
    }
    _matrix(
      'login page live',
      (db) => StudentLoginPage(
        database: db,
        onLoginComplete: () {},
        authStore: StudentAuthStore(),
      ),
      withData: false,
    );

    test('problem classification', () {
      expect(_problem('Invalid roll number or password.').issue,
          LoginIssue.wrongPassword);
      expect(
          _problem('2 attempts remaining, wrong credentials').attemptsLeft, 2);
      expect(_problem('locked for 7 minutes').lockMinutes, 7);
      expect(_problem('Connection refused').issue, LoginIssue.offline);
      expect(_problem('500 internal').issue, LoginIssue.server);
      expect(LoginValidation.rollProblem('12'), isNotNull);
      expect(LoginValidation.rollProblem('90010001'), isNull);
    });

    for (final (name, size, keyboard) in [
      ('fold', const Size(280, 653), 300.0),
      ('android', const Size(360, 640), 300.0),
      ('landscape', const Size(844, 390), 200.0),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('login keyboard open: $name @${scale}x keeps field visible',
            (tester) async {
          await _pump(tester,
              size: size,
              scale: scale,
              rtl: false,
              home: _login(
                  problem: _problem('Invalid roll number or password.')));
          for (final index in [0, 1]) {
            await tester.scrollUntilVisible(find.text('Student sign in'), 80,
                scrollable: find.byType(Scrollable).first);
            await tester.ensureVisible(find.byType(TextField).at(index));
            await tester.pump();
            await tester.tap(find.byType(TextField).at(index));
            await tester.pump(const Duration(milliseconds: 200));
            // The keyboard slides up after the field has focus; the form must
            // scroll the focused field above it.
            tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 2);
            await tester.pump(const Duration(milliseconds: 700));
            expect(tester.takeException(), isNull);
            final rect = tester.getRect(find.byType(TextField).at(index));
            expect(rect.bottom, lessThanOrEqualTo(size.height - keyboard + 1),
                reason: 'field $index hidden by keyboard');
            expect(rect.top, greaterThanOrEqualTo(-8));
            tester.view.viewInsets = FakeViewPadding.zero;
            await tester.pump(const Duration(milliseconds: 300));
          }
        });
      }
    }
  });

  group('create password sheet', () {
    final states = <String, Future<void> Function(WidgetTester)?>{
      'idle': null,
      'weak': (t) async {
        await t.enterText(find.byType(TextField).first, 'abc');
      },
      'mismatch': (t) async {
        await t.enterText(
            find.byType(TextField).first, 'CorrectHorse-Battery9');
        await t.enterText(find.byType(TextField).last, 'different');
      },
      'strong and matching': (t) async {
        await t.enterText(
            find.byType(TextField).first, 'CorrectHorse-Battery9!');
        await t.enterText(
            find.byType(TextField).last, 'CorrectHorse-Battery9!');
      },
      'long password': (t) async {
        await t.enterText(find.byType(TextField).first, 'Aa1!' * 30);
        await t.enterText(find.byType(TextField).last, 'Aa1!' * 30);
      },
      'submit error': (t) async {
        await t.enterText(
            find.byType(TextField).first, 'CorrectHorse-Battery9!');
        await t.enterText(
            find.byType(TextField).last, 'CorrectHorse-Battery9!');
        await t.ensureVisible(find.text('Set password'));
        await t.tap(find.text('Set password'));
        await t.pump(const Duration(milliseconds: 100));
        expect(find.text('Could not set password'), findsOneWidget);
      },
      'submitting': (t) async {
        await t.enterText(
            find.byType(TextField).first, 'CorrectHorse-Battery9!');
        await t.enterText(
            find.byType(TextField).last, 'CorrectHorse-Battery9!');
        await t.ensureVisible(find.text('Set password'));
        await t.tap(find.text('Set password'));
        await t.pump(const Duration(milliseconds: 100));
        expect(find.text('Saving'), findsOneWidget);
      },
      'success': (t) async {
        await t.enterText(
            find.byType(TextField).first, 'CorrectHorse-Battery9!');
        await t.enterText(
            find.byType(TextField).last, 'CorrectHorse-Battery9!');
        await t.ensureVisible(find.text('Set password'));
        await t.tap(find.text('Set password'));
        await t.pump(const Duration(milliseconds: 10));
        expect(find.text('Password updated'), findsOneWidget);
        await t.pump(const Duration(milliseconds: 100));
      },
    };
    final pending = Completer<void>();
    for (final e in states.entries) {
      _matrix(
        'password sheet ${e.key}',
        (db) => _passwordForm(
          onSubmit: switch (e.key) {
            'submit error' => (_) async => throw StateError(_error300),
            'submitting' => (_) => pending.future,
            _ => null,
          },
        ),
        withData: false,
        interact: e.value,
      );
    }

    for (final (name, size, keyboard) in [
      ('fold', const Size(280, 653), 300.0),
      ('landscape', const Size(844, 390), 200.0),
    ]) {
      testWidgets('password sheet keyboard open: $name', (tester) async {
        await _pump(tester,
            size: size, scale: 1.3, rtl: false, home: _passwordForm());
        for (final i in [0, 1]) {
          await tester.ensureVisible(find.byType(TextField).at(i));
          await tester.pump();
          await tester.tap(find.byType(TextField).at(i));
          await tester.pump(const Duration(milliseconds: 200));
          tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 2);
          await tester.pump(const Duration(milliseconds: 700));
          expect(tester.takeException(), isNull);
          final rect = tester.getRect(find.byType(TextField).at(i));
          expect(rect.bottom, lessThanOrEqualTo(size.height - keyboard + 1),
              reason: 'password field $i hidden by keyboard');
          tester.view.viewInsets = FakeViewPadding.zero;
          await tester.pump(const Duration(milliseconds: 300));
        }
      });
    }

    test('strength meter ordering', () {
      expect(passwordStrength(''), 0);
      expect(passwordStrength('abc'), 1);
      expect(passwordStrength('abcdefghijklmnop'), 2);
      expect(passwordStrength('Abcdefghijklmnop1'), 3);
      expect(passwordStrength('Abcdefghijklmn1!'), 4);
    });
  });

  group('launch and shared components', () {
    _matrix('launch loading', (db) => const AppLaunchScreen(), withData: false);
    _matrix('launch storage unavailable',
        (db) => StorageUnavailableScreen(onRetry: () {}),
        withData: false);
    _matrix('launch storage unavailable no retry',
        (db) => const StorageUnavailableScreen(),
        withData: false);
    _matrix(
      'components long text',
      (db) => _page(
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            EmptyState(title: _long80, message: _error300),
            const SizedBox(height: 12),
            EmptyState(
                title: 'Action',
                message: _error300,
                action:
                    FilledButton(onPressed: () {}, child: const Text('Go'))),
            const SizedBox(height: 12),
            CuteEmptyState(title: _long80, message: _error300),
            const SizedBox(height: 12),
            ProductActionTile(
                title: _long80,
                description: _error300,
                icon: Icons.person,
                onTap: () {}),
            const SizedBox(height: 12),
            ProductSection(label: _long80, children: [
              ProductListTile(
                  icon: Icons.person,
                  title: _long80,
                  subtitle: _error300,
                  onTap: () {}),
              const ProductListTile(icon: Icons.info, title: 'Plain'),
            ]),
            const SizedBox(height: 12),
            ProductNoticeBanner(
                title: _long80,
                message: _error300,
                tone: StatusTone.error,
                action:
                    TextButton(onPressed: () {}, child: const Text('Retry'))),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              const StatusChip(
                  label: _long80, icon: Icons.info, tone: StatusTone.info),
              StatusChip(label: _error300),
            ]),
            const SizedBox(height: 12),
            StateView.error(message: _error300, onAction: () {}),
            const SizedBox(height: 12),
            StateView.offline(actionLabel: 'Retry', onAction: () {}),
            const SizedBox(height: 12),
            const StateView.loading(),
            const SizedBox(height: 12),
            StepTimeline(steps: [
              for (final p in StepProgress.values)
                TimelineStep(title: _long80, body: _error300, progress: p),
            ]),
            for (var i = 0; i <= 4; i++) PasswordStrengthMeter(strength: i),
          ],
        ),
      ),
      withData: false,
    );
  });

  test('InMemoryDeviceKeyStore is available for device fixtures', () {
    expect(InMemoryDeviceKeyStore(), isA<DeviceKeyStore>());
  });
}

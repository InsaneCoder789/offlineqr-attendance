import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/database/local_database.dart';

import 'support/bootstrap_fixture.dart';
import 'test_app.dart';

void main() {
  testWidgets('student dashboard renders from local database', (tester) async {
    final database = LocalAttendanceDatabase.inMemory();
    addTearDown(database.close);
    database.applyBootstrap(sampleBootstrapPayload());

    await tester.pumpWidget(TestApp(database: database));

    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Attendance'), findsWidgets);
    expect(find.text('Timetable'), findsWidgets);

    // Navigate to Scan tab
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Scan Attendance'), findsOneWidget);

    // Navigate to Attendance tab
    await tester.tap(find.text('Attendance').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Aarav Mehta'), findsOneWidget);
    expect(find.text('Design and Analysis of Algorithms'), findsOneWidget);
    expect(find.textContaining('2 Present'), findsOneWidget);
    expect(find.text('67%'), findsOneWidget);
  });

  testWidgets('student destinations fit a compact phone viewport',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final database = LocalAttendanceDatabase.inMemory();
    addTearDown(database.close);
    database.applyBootstrap(sampleBootstrapPayload());

    await tester.pumpWidget(TestApp(database: database));
    await tester.pumpAndSettle();

    for (final destination in ['Attendance', 'Scan', 'Portals', 'Timetable']) {
      await tester.tap(find.text(destination).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$destination overflowed');
    }
  });
}

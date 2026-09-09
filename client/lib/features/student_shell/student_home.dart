import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../core/security/device_crypto.dart';
import '../../ui/kiit_components.dart';
import '../../ui/kiit_theme.dart';
import '../student_attendance/student_attendance_page.dart';
import '../student_portals/student_portals_page.dart';
import '../student_profile/student_profile_page.dart';
import '../student_scan/student_scan_page.dart';
import '../student_timetable/student_timetable_page.dart';

class StudentHome extends StatefulWidget {
  const StudentHome({
    super.key,
    required this.database,
    required this.keyStore,
    this.onSync,
    this.onAttendanceRecorded,
    this.syncing = false,
    this.syncError,
    this.refreshToken = 0,
  });

  final LocalAttendanceDatabase database;
  final DeviceKeyStore keyStore;
  final Future<void> Function()? onSync;
  final Future<bool> Function()? onAttendanceRecorded;
  final bool syncing;
  final String? syncError;
  final int refreshToken;

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      StudentTimetablePage(
        key: ValueKey('timetable-${widget.refreshToken}'),
        database: widget.database,
      ),
      StudentAttendancePage(
        key: ValueKey('attendance-${widget.refreshToken}'),
        database: widget.database,
      ),
      StudentScanPage(
        key: ValueKey('scan-${widget.refreshToken}'),
        database: widget.database,
        keyStore: widget.keyStore,
        onAttendanceRecorded: widget.onAttendanceRecorded,
      ),
      const StudentPortalsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: KiitSpacing.x4,
        title: const KiitLogo(height: 34),
        actions: [
          if (widget.onSync != null)
            Padding(
              padding: const EdgeInsets.only(right: KiitSpacing.x2),
              child: Center(
                child: SyncStatus(
                  label: widget.syncError ??
                      (widget.syncing ? 'Syncing' : 'Synced'),
                  syncing: widget.syncing,
                  offline: widget.syncError != null,
                ),
              ),
            ),
          if (widget.onSync != null)
            IconButton(
              tooltip: 'Sync',
              onPressed: widget.syncing ? null : widget.onSync,
              icon: const Icon(Icons.sync),
            ),
          IconButton(
            tooltip: 'Profile',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StudentProfilePage(
                    database: widget.database,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: KiitColors.surface,
          border: Border(top: BorderSide(color: KiitColors.divider)),
        ),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.calendar_today_outlined),
              selectedIcon: Icon(Icons.calendar_today_rounded),
              label: 'Timetable',
            ),
            NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check_rounded),
              label: 'Attendance',
            ),
            NavigationDestination(
              icon: Icon(Icons.qr_code_scanner_rounded),
              selectedIcon: Icon(Icons.qr_code_scanner_rounded),
              label: 'Scan',
            ),
            NavigationDestination(
              icon: Icon(Icons.apps_outlined),
              selectedIcon: Icon(Icons.apps_rounded),
              label: 'Portals',
            ),
          ],
        ),
      ),
    );
  }
}

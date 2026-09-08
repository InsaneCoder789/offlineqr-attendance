import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../ui/kiit_components.dart';
import '../../ui/kiit_theme.dart';
import '../device_security/device_screen.dart';

class StudentProfilePage extends StatelessWidget {
  const StudentProfilePage({
    super.key,
    required this.database,
  });

  final LocalAttendanceDatabase database;

  @override
  Widget build(BuildContext context) {
    final student = database.getCurrentStudent();
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(KiitSpacing.x4),
        children: [
          KiitCard(
            color: KiitColors.brandPrimarySubtle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const KiitLogo(height: 42),
                const SizedBox(height: KiitSpacing.x6),
                Text(
                  student?.displayName ?? 'Student profile',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: KiitSpacing.x2),
                Text(
                  student == null
                      ? 'Sync your institutional account to view details.'
                      : '${student.rollNumber} · ${student.sectionCode}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: KiitSpacing.x5),
          _ProfileTile(
            icon: Icons.person_outline,
            title: 'Account',
            subtitle: 'Institutional identity and section',
            onTap: () {},
          ),
          _ProfileTile(
            icon: Icons.phone_android_outlined,
            title: 'Attendance Device',
            subtitle: 'This phone registration and verification',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DeviceScreen(database: database),
              ),
            ),
          ),
          _ProfileTile(
            icon: Icons.sync_outlined,
            title: 'Synchronization',
            subtitle: 'Saved data, pending changes, and last update',
            onTap: () {},
          ),
          _ProfileTile(
            icon: Icons.storage_outlined,
            title: 'Offline Data',
            subtitle: 'Attendance and timetable available offline',
            onTap: () {},
          ),
          _ProfileTile(
            icon: Icons.notifications_none,
            title: 'Notifications',
            subtitle: 'Attendance reminders and alerts',
            onTap: () {},
          ),
          _ProfileTile(
            icon: Icons.help_outline,
            title: 'Help',
            subtitle: 'Support for attendance issues',
            onTap: () {},
          ),
          _ProfileTile(
            icon: Icons.info_outline,
            title: 'About',
            subtitle: 'KIIT Attendance platform',
            onTap: () {},
          ),
          const SizedBox(height: KiitSpacing.x4),
          const StatusChip(
            label:
                'Attendance identity is locked to this device. Device changes require verified replacement.',
            icon: Icons.lock_outline,
            tone: StatusTone.info,
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KiitSpacing.x3),
      child: KiitCard(
        padding: const EdgeInsets.symmetric(
          horizontal: KiitSpacing.x4,
          vertical: KiitSpacing.x3,
        ),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: KiitColors.brandPrimaryStrong),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}

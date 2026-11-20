import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/database/local_database.dart';
import '../../ui/dark_kit.dart';
import '../../ui/dark_kit_extra_b.dart';
import '../../ui/product_components.dart';
import '../../ui/product_theme.dart';
import '../../ui/responsive.dart';
import '../device_security/device_screen.dart';

/// Which settings row is expanded inline (only one at a time).
enum _Detail { account, sync, offline }

/// Counts shown by the Synchronization / Offline data rows. Read once per
/// build from the local database; every read is guarded so a storage hiccup
/// shows dashes instead of breaking the page.
class ProfileDataSummary {
  const ProfileDataSummary({
    this.timetableEntries,
    this.attendanceRows,
    this.pendingUploads,
    this.needsReview,
    this.latestRecord,
  });

  final int? timetableEntries;
  final int? attendanceRows;
  final int? pendingUploads;
  final int? needsReview;
  final String? latestRecord;

  factory ProfileDataSummary.read(LocalAttendanceDatabase database) {
    int? timetable;
    int? attendance;
    int? pending;
    int? review;
    String? latest;
    try {
      timetable = [
        for (var day = 1; day <= 7; day++)
          database.getTimetableForDay(day).length
      ].fold<int>(0, (a, b) => a + b);
    } catch (_) {}
    try {
      attendance = database.getAttendanceHistory().length;
    } catch (_) {}
    try {
      final log = database.getRecentAttendanceLog(limit: 500);
      pending = log.where((e) => !e.isServerAccepted && !e.hasDiscrepancy).length;
      review = log.where((e) => e.hasDiscrepancy).length;
      latest = log.isEmpty ? null : log.first.recordedAt;
    } catch (_) {}
    return ProfileDataSummary(
      timetableEntries: timetable,
      attendanceRows: attendance,
      pendingUploads: pending,
      needsReview: review,
      latestRecord: latest,
    );
  }
}

class StudentProfilePage extends StatefulWidget {
  const StudentProfilePage({
    super.key,
    required this.database,
  });

  final LocalAttendanceDatabase database;

  /// Initials from the name's words that start with a letter ("Student
  /// 90010001" -> "S", "Aarav Mehta" -> "AM"). Falls back to the first
  /// character, then '?'.
  static String initialsOf(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && RegExp(r'^\p{L}', unicode: true).hasMatch(w))
        .toList();
    if (words.isEmpty) {
      final t = name.trim();
      return t.isEmpty ? '?' : t.characters.first.toUpperCase();
    }
    final first = words.first.characters.first;
    final last = words.length > 1 ? words.last.characters.first : '';
    return (first + last).toUpperCase();
  }

  @override
  State<StudentProfilePage> createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage> {
  _Detail? _open;

  void _toggle(_Detail d) => setState(() => _open = _open == d ? null : d);

  @override
  Widget build(BuildContext context) {
    final student = widget.database.getCurrentStudent();
    final summary = ProfileDataSummary.read(widget.database);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: AdaptivePage(
          children: [
            const SizedBox(height: ProductSpacing.x4),
            FadeSlideIn(child: _ProfileHero(student: student)),
            const SizedBox(height: ProductSpacing.x5),
            ProductSection(label: 'Security', children: [
              ProductListTile(
                icon: Icons.phone_android_outlined,
                title: 'Attendance device',
                subtitle: 'This phone registration and verification',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DeviceScreen(database: widget.database),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: ProductSpacing.x4),
            ProductSection(label: 'Data', children: [
              _ExpandableRow(
                icon: Icons.person_outline,
                title: 'Account',
                subtitle: 'Institutional identity and section',
                open: _open == _Detail.account,
                onToggle: () => _toggle(_Detail.account),
                detail: student == null
                    ? const _DetailNote(
                        'No account is saved on this phone yet. Sign in and sync to see your details.')
                    : Column(children: [
                        _CopyRow(label: 'Name', value: student.displayName),
                        _CopyRow(label: 'Roll number', value: student.rollNumber),
                        _CopyRow(label: 'Section', value: student.sectionCode),
                      ]),
              ),
              _ExpandableRow(
                icon: Icons.sync_outlined,
                title: 'Synchronization',
                subtitle: _syncSubtitle(summary),
                open: _open == _Detail.sync,
                onToggle: () => _toggle(_Detail.sync),
                detail: Column(children: [
                  _ValueRow(
                      label: 'Latest record',
                      value: summary.latestRecord ?? 'None yet'),
                  _ValueRow(
                      label: 'Waiting to upload',
                      value: _count(summary.pendingUploads)),
                  _ValueRow(
                      label: 'Needs review',
                      value: _count(summary.needsReview)),
                  const _DetailNote(
                      'Pending records upload automatically when you are back online.'),
                ]),
              ),
              _ExpandableRow(
                icon: Icons.storage_outlined,
                title: 'Offline data',
                subtitle: 'Attendance and timetable available offline',
                open: _open == _Detail.offline,
                onToggle: () => _toggle(_Detail.offline),
                detail: Column(children: [
                  _ValueRow(
                      label: 'Timetable entries',
                      value: _count(summary.timetableEntries)),
                  _ValueRow(
                      label: 'Attendance rows',
                      value: _count(summary.attendanceRows)),
                  const _DetailNote(
                      'Saved on this phone, so they stay available without internet.'),
                ]),
              ),
            ]),
            const SizedBox(height: ProductSpacing.x4),
            ProductSection(label: 'Support', children: [
              ProductListTile(
                icon: Icons.notifications_none,
                title: 'Notifications',
                subtitle: 'Attendance reminders and alerts',
                onTap: () => _showInfo(
                  context,
                  icon: Icons.notifications_none,
                  title: 'Notifications',
                  lines: const [
                    'Reminders and alerts appear inside the app when a class is about to start or an attendance record needs your attention.',
                    'Keep notifications allowed in your phone settings so you do not miss a class window.',
                  ],
                ),
              ),
              ProductListTile(
                icon: Icons.help_outline,
                title: 'Help',
                subtitle: 'Support for attendance issues',
                onTap: () => _showInfo(
                  context,
                  icon: Icons.help_outline,
                  title: 'Help',
                  lines: const [
                    'Missed a scan? Records captured offline upload by themselves once you are connected.',
                    'Changed or lost your phone? Open Attendance device and use Transfer device or Relink.',
                    'Anything else: contact your faculty or the ICT help desk with your roll number.',
                  ],
                ),
              ),
              ProductListTile(
                icon: Icons.info_outline,
                title: 'About',
                subtitle: 'OfflineQR platform',
                onTap: () => _showInfo(
                  context,
                  icon: Icons.info_outline,
                  title: 'About OfflineQR',
                  lines: const [
                    'OfflineQR records attendance with signed QR codes, even without internet.',
                    'Your attendance identity is tied to this phone and checked again on the server.',
                  ],
                ),
              ),
            ]),
            const SizedBox(height: ProductSpacing.x5),
            const ProductNoticeBanner(
              title: 'Locked to this device',
              message:
                  'Attendance identity is locked to this device. Device changes require verified replacement.',
            ),
          ],
        ),
      ),
    );
  }

  static String _count(int? v) => v == null ? '-' : '$v';

  static String _syncSubtitle(ProfileDataSummary s) {
    final pending = s.pendingUploads;
    if (pending == null) return 'Saved data and pending changes';
    return pending == 0 ? 'Everything is up to date' : '$pending waiting to upload';
  }

  void _showInfo(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<String> lines,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ProductColors.surfaceElevated,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(ProductSpacing.x5, 0,
              ProductSpacing.x5, ProductSpacing.x5),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    IconChip(icon: icon, size: 40),
                    const SizedBox(width: ProductSpacing.x3),
                    Expanded(
                      child: Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                  ]),
                  const SizedBox(height: ProductSpacing.x4),
                  for (final line in lines) ...[
                    Text(line, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: ProductSpacing.x3),
                  ],
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.student});

  final StudentProfile? student;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return NeonHero(
      padding: const EdgeInsets.all(ProductSpacing.x5),
      child: Row(
        children: [
          // Subtle glow only: the avatar is 56dp, the shadow soft.
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ProductColors.brandPrimary,
              boxShadow: [
                BoxShadow(
                    color: ProductColors.brandPrimary.withValues(alpha: 0.22),
                    blurRadius: 16,
                    spreadRadius: -2),
              ],
            ),
            child: ExcludeSemantics(
              child: Text(
                student == null
                    ? '?'
                    : StudentProfilePage.initialsOf(student!.displayName),
                maxLines: 1,
                style: const TextStyle(
                  color: ProductColors.onBrand,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ),
          const SizedBox(width: ProductSpacing.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student?.displayName ?? 'Student profile',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleLarge?.copyWith(letterSpacing: -0.4),
                ),
                const SizedBox(height: ProductSpacing.x1),
                Text(
                  student == null
                      ? 'Sync your institutional account to view details.'
                      : '${student!.rollNumber} · ${student!.sectionCode}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyMedium?.copyWith(
                      color: ProductColors.textPrimary.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings row that expands its [detail] inline instead of navigating.
class _ExpandableRow extends StatelessWidget {
  const _ExpandableRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.open,
    required this.onToggle,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool open;
  final VoidCallback onToggle;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: open,
          child: ProductListTile(
            icon: icon,
            title: title,
            subtitle: subtitle,
            onTap: onToggle,
            trailing: AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(Icons.expand_more_rounded,
                  color: ProductColors.textMuted),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                      ProductSpacing.x4, 0, ProductSpacing.x4, ProductSpacing.x3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: ProductSpacing.x3,
                          vertical: ProductSpacing.x2),
                      child: detail,
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _DetailNote extends StatelessWidget {
  const _DetailNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ProductSpacing.x2),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: ProductColors.textMuted)),
      ),
    );
  }
}

/// Label on the start, value on the end; values wrap to 3 lines.
class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
          ),
          const SizedBox(width: ProductSpacing.x3),
          Expanded(
            flex: 3,
            child: Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: t.labelLarge?.copyWith(color: ProductColors.textPrimary),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Read-only value with a copy button.
class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _ValueRow(
      label: label,
      value: value,
      trailing: IconButton(
        tooltip: 'Copy $label',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: const Icon(Icons.copy_rounded, size: 18),
        onPressed: () async {
          final messenger = ScaffoldMessenger.maybeOf(context);
          await Clipboard.setData(ClipboardData(text: value));
          messenger?.hideCurrentSnackBar();
          messenger?.showSnackBar(SnackBar(content: Text('$label copied')));
        },
      ),
    );
  }
}

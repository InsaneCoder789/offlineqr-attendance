import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../core/security/device_crypto.dart';
import '../../ui/product_components.dart';
import '../../ui/product_theme.dart';
import '../../ui/responsive.dart';
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

const _destinations = <({IconData icon, IconData selected, String label})>[
  (
    icon: Icons.calendar_today_outlined,
    selected: Icons.calendar_today_rounded,
    label: 'Timetable'
  ),
  (
    icon: Icons.fact_check_outlined,
    selected: Icons.fact_check_rounded,
    label: 'Attendance'
  ),
  (
    icon: Icons.qr_code_scanner_rounded,
    selected: Icons.qr_code_scanner_rounded,
    label: 'Scan'
  ),
  (icon: Icons.apps_outlined, selected: Icons.apps_rounded, label: 'Portals'),
];

class _StudentHomeState extends State<StudentHome> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      StudentTimetablePage(
        key: ValueKey('timetable-${widget.refreshToken}'),
        database: widget.database,
        syncError: widget.syncError,
        onSync: widget.onSync,
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
    return LayoutBuilder(builder: (context, outer) {
      final wide = outer.maxWidth >= Breakpoints.medium;
      return _buildScaffold(context, pages, wide);
    });
  }

  Widget _buildScaffold(BuildContext context, List<Widget> pages, bool wide) {
    final media = MediaQuery.of(context);
    final compact = media.size.height <= 420;
    final narrow = media.size.width < 400;
    final barHeight = _FloatingBar.heightFor(compact: compact, safeBottom: media.padding.bottom);
    final stack = IndexedStack(index: index, children: pages);
    return Scaffold(
      extendBody: !wide,
      appBar: AppBar(
        titleSpacing: narrow ? ProductSpacing.x3 : ProductSpacing.x4,
        title: CappedTextScale(
          max: 1.15,
          child: Row(
            children: [
              ProductLogo(height: narrow ? 26 : 30),
              const SizedBox(width: ProductSpacing.x2),
              // The wordmark shrinks to fit; it is never ellipsized.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'OfflineQR',
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (widget.onSync != null)
            if (narrow)
              _SyncIconPill(
                syncing: widget.syncing,
                error: widget.syncError,
                onSync: widget.onSync!,
              )
            else ...[
              Padding(
                padding: const EdgeInsets.only(right: ProductSpacing.x1),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: SyncStatus(
                      label: widget.syncError ??
                          (widget.syncing ? 'Syncing' : 'Synced'),
                      syncing: widget.syncing,
                      offline: widget.syncError != null,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Sync',
                onPressed: widget.syncing ? null : widget.onSync,
                icon: const Icon(Icons.sync),
              ),
            ],
          Padding(
            padding: EdgeInsets.only(
                right: narrow ? ProductSpacing.x1 : ProductSpacing.x2),
            child: IconButton(
              tooltip: 'Profile',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              padding: EdgeInsets.zero,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StudentProfilePage(
                      database: widget.database,
                    ),
                  ),
                );
              },
              icon: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ProductColors.brandPrimary.withValues(alpha: 0.14),
                  border: Border.all(
                      color: ProductColors.brandPrimary.withValues(alpha: 0.5)),
                ),
                child: const Icon(Icons.person_rounded,
                    size: 22, color: ProductColors.brandPrimary),
              ),
            ),
          ),
        ],
      ),
      // The bar floats over the body; pages pad themselves by [ShellInsets]
      // (read by AdaptivePage) instead of by MediaQuery padding.
      body: MediaQuery.removePadding(
        context: context,
        removeBottom: !wide,
        child: ShellInsets(
          bottom: wide ? 0 : barHeight,
          child: wide
              ? Row(
                  children: [
                    _GlassRail(
                      index: index,
                      onSelected: (value) => setState(() => index = value),
                    ),
                    Expanded(child: stack),
                  ],
                )
              : stack,
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : _FloatingBar(
              index: index,
              compact: compact,
              height: barHeight,
              onSelected: (value) => setState(() => index = value),
            ),
    );
  }
}

/// Icon-only sync status for narrow screens: shows state, doubles as the
/// sync button, and carries the full status as tooltip and semantics.
class _SyncIconPill extends StatelessWidget {
  const _SyncIconPill({
    required this.syncing,
    required this.error,
    required this.onSync,
  });

  final bool syncing;
  final String? error;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    final offline = error != null;
    final color = offline
        ? ProductColors.warning
        : syncing
            ? ProductColors.info
            : ProductColors.success;
    final status = offline
        ? 'Sync failed: $error. Tap to retry'
        : syncing
            ? 'Syncing'
            : 'Synced. Tap to sync again';
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Tooltip(
      message: status,
      child: Semantics(
        button: true,
        enabled: !syncing,
        label: status,
        excludeSemantics: true,
        onTap: syncing ? null : () => onSync(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: syncing ? null : () => onSync(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Center(
              child: Container(
                width: 40,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: color.withValues(alpha: 0.14),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: syncing && !reduced
                    ? Padding(
                        padding: const EdgeInsets.all(7),
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: color),
                      )
                    : Icon(
                        syncing
                            ? Icons.sync
                            : offline
                                ? Icons.cloud_off_outlined
                                : Icons.check_circle_outline,
                        size: 18,
                        color: color,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingBar extends StatelessWidget {
  const _FloatingBar({
    required this.index,
    required this.compact,
    required this.height,
    required this.onSelected,
  });

  final int index;
  final bool compact;
  final double height;
  final ValueChanged<int> onSelected;

  static double _itemHeight(bool compact) => compact ? 44 : 60;
  static double _margin(bool compact) => compact ? 8 : 12;

  /// Total space the bar occupies, including its margin and the safe area.
  static double heightFor({required bool compact, required double safeBottom}) =>
      _itemHeight(compact) + 12 + _margin(compact) + safeBottom;

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding;
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          ProductSpacing.x4 + safe.left,
          0,
          ProductSpacing.x4 + safe.right,
          _margin(compact) + safe.bottom,
        ),
        child: CappedTextScale(
          max: 1.15,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 24 : 28),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [ProductColors.surfaceElevated, ProductColors.surface],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 24,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  for (var i = 0; i < _destinations.length; i++)
                    Expanded(
                      child: _BarItem(
                        destination: _destinations[i],
                        selected: i == index,
                        compact: compact,
                        height: _itemHeight(compact),
                        onTap: () => onSelected(i),
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

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.destination,
    required this.selected,
    required this.compact,
    required this.height,
    required this.onTap,
  });

  final ({IconData icon, IconData selected, String label}) destination;
  final bool selected;
  final bool compact;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fast = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final color =
        selected ? ProductColors.brandPrimary : ProductColors.textMuted;
    final duration = fast ? Duration.zero : const Duration(milliseconds: 200);
    final icon = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: selected
            ? [
                BoxShadow(
                    color: ProductColors.brandPrimary.withValues(alpha: 0.55),
                    blurRadius: 16,
                    spreadRadius: -2),
              ]
            : null,
      ),
      child: Icon(selected ? destination.selected : destination.icon,
          size: compact ? 22 : 24, color: color),
    );
    final label = Text(
      destination.label,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: compact ? 12 : 11,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        color: color,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: duration,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: selected
                ? ProductColors.brandPrimary.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: compact
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [icon, const SizedBox(width: 6), label],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        icon,
                        const SizedBox(height: 3),
                        label,
                        const SizedBox(height: 3),
                        AnimatedContainer(
                          duration: duration,
                          width: selected ? 16 : 0,
                          height: 3,
                          decoration: BoxDecoration(
                            color: ProductColors.brandPrimary,
                            borderRadius: BorderRadius.circular(99),
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

class _GlassRail extends StatelessWidget {
  const _GlassRail({required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return CappedTextScale(
      max: 1.15,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(
              child: Container(
                margin: const EdgeInsets.fromLTRB(
                    ProductSpacing.x3, 0, 0, ProductSpacing.x3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  color: ProductColors.surface,
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.07)),
                ),
                child: NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: onSelected,
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: Colors.transparent,
                  indicatorColor:
                      ProductColors.brandPrimary.withValues(alpha: 0.16),
                  indicatorShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  selectedIconTheme:
                      const IconThemeData(color: ProductColors.brandPrimary),
                  unselectedIconTheme:
                      const IconThemeData(color: ProductColors.textMuted),
                  selectedLabelTextStyle: const TextStyle(
                      color: ProductColors.brandPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12),
                  unselectedLabelTextStyle: const TextStyle(
                      color: ProductColors.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selected),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(d.label, maxLines: 1, softWrap: false),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

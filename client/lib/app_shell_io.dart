import 'dart:async';

import 'package:flutter/material.dart';

import 'core/database/local_database.dart';
import 'core/network/api_config.dart';
import 'core/security/secure_device_key_store.dart';
import 'core/sync/attendance_proof_sync_service.dart';
import 'core/sync/bootstrap_sync_service.dart';
import 'features/student_auth/student_login_page.dart';
import 'features/student_shell/student_home.dart';
import 'ui/kiit_components.dart';
import 'ui/kiit_theme.dart';

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KIIT Attendance',
      theme: buildKiitTheme(),
      onUnknownRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => const KiitNotFoundPage(),
      ),
      home: FutureBuilder<LocalAttendanceDatabase>(
        future: LocalAttendanceDatabase.openDefault(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Text('Local database error: ${snapshot.error}'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return DevelopmentDashboardShell(
            database: snapshot.data!,
            keyStore: SecureStorageDeviceKeyStore(),
          );
        },
      ),
    );
  }
}

class DevelopmentDashboardShell extends StatefulWidget {
  const DevelopmentDashboardShell({
    super.key,
    required this.database,
    required this.keyStore,
  });

  final LocalAttendanceDatabase database;
  final SecureStorageDeviceKeyStore keyStore;

  @override
  State<DevelopmentDashboardShell> createState() =>
      _DevelopmentDashboardShellState();
}

class _DevelopmentDashboardShellState extends State<DevelopmentDashboardShell>
    with WidgetsBindingObserver {
  int refreshToken = 0;
  bool syncing = false;
  String? syncError;
  late bool loggedIn;
  Timer? syncPoller;

  @override
  void initState() {
    super.initState();
    loggedIn = widget.database.getCurrentStudent() != null;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && loggedIn) {
        sync();
        _startSyncPolling();
      }
    });
  }

  @override
  void dispose() {
    syncPoller?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !syncing) {
      sync();
      _startSyncPolling();
    }
    if (state == AppLifecycleState.paused) {
      syncPoller?.cancel();
      syncPoller = null;
    }
  }

  Future<void> sync() async {
    await _syncInternal(forceProofSync: true);
  }

  Future<bool> _syncInternal({
    bool refreshViews = true,
    bool forceProofSync = false,
  }) async {
    if (syncing) return false;
    setState(() => syncing = true);
    try {
      final baseUri = apiBaseUri();
      final proofSync = await AttendanceProofSyncService(
        database: widget.database,
        baseUri: baseUri,
        keyStore: widget.keyStore,
      ).syncPendingProofs(force: forceProofSync);
      var bootstrapOk = true;
      try {
        await BootstrapSyncService(
          database: widget.database,
          baseUri: baseUri,
        ).sync();
      } catch (_) {
        bootstrapOk = false;
      }
      if (proofSync.rejected > 0) {
        setState(() {
          if (refreshViews) {
            refreshToken++;
          }
          syncError = 'Review needed';
        });
        return false;
      }
      setState(() {
        if (refreshViews) {
          refreshToken++;
        }
        syncError =
            !bootstrapOk || proofSync.retryPending > 0 ? 'Sync pending' : null;
      });
      return bootstrapOk && proofSync.retryPending == 0;
    } catch (_) {
      if (mounted) {
        setState(() => syncError = 'Sync failed');
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => syncing = false);
      }
    }
  }

  void _startSyncPolling() {
    if (syncPoller != null || !loggedIn) return;
    // Foreground polling makes captured proofs the first work attempted as
    // soon as the backend becomes reachable again. The outbox backoff still
    // protects the server during a real outage.
    syncPoller = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || syncing || !loggedIn) return;
      _syncInternal(forceProofSync: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!loggedIn) {
      return StudentLoginPage(
        database: widget.database,
        onLoginComplete: () {
          setState(() {
            loggedIn = true;
            refreshToken++;
            syncError = null;
          });
          _startSyncPolling();
        },
      );
    }
    return StudentHome(
      database: widget.database,
      keyStore: widget.keyStore,
      refreshToken: refreshToken,
      onSync: sync,
      onAttendanceRecorded: () => _syncInternal(forceProofSync: true),
      syncing: syncing,
      syncError: syncError,
    );
  }
}

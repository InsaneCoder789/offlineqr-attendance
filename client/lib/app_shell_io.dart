import 'dart:async';

import 'package:flutter/material.dart';

import 'core/database/local_database.dart';
import 'core/network/api_config.dart';
import 'core/security/secure_device_key_store.dart';
import 'core/security/student_auth_store.dart';
import 'core/sync/attendance_proof_sync_service.dart';
import 'core/sync/bootstrap_sync_service.dart';
import 'features/student_auth/student_login_page.dart';
import 'features/student_shell/student_home.dart';
import 'ui/dark_kit_extra_b.dart';
import 'ui/product_components.dart';
import 'ui/product_theme.dart';
import 'ui/state_views.dart';

class AttendanceApp extends StatefulWidget {
  const AttendanceApp({super.key});

  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp> {
  late Future<LocalAttendanceDatabase> _databaseFuture;
  late final StudentAuthStore _authStore;
  LocalAttendanceDatabase? _database;

  @override
  void initState() {
    super.initState();
    _authStore = StudentAuthStore();
    _databaseFuture = _openDatabase();
  }

  Future<LocalAttendanceDatabase> _openDatabase() {
    return LocalAttendanceDatabase.openDefault().then((database) {
      _database = database;
      return database;
    });
  }

  void _retryOpen() {
    setState(() => _databaseFuture = _openDatabase());
  }

  @override
  void dispose() {
    _database?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OfflineQR',
      debugShowCheckedModeBanner: false,
      theme: buildProductTheme(),
      onUnknownRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => const ProductNotFoundPage(),
      ),
      home: FutureBuilder<LocalAttendanceDatabase>(
        future: _databaseFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return StorageUnavailableScreen(onRetry: _retryOpen);
          }
          if (snapshot.connectionState != ConnectionState.done ||
              !snapshot.hasData) {
            return const AppLaunchScreen();
          }
          return StudentAppShell(
            database: snapshot.data!,
            keyStore: SecureStorageDeviceKeyStore(),
            authStore: _authStore,
          );
        },
      ),
    );
  }
}

class StudentAppShell extends StatefulWidget {
  const StudentAppShell({
    super.key,
    required this.database,
    required this.keyStore,
    required this.authStore,
  });

  final LocalAttendanceDatabase database;
  final SecureStorageDeviceKeyStore keyStore;
  final StudentAuthStore authStore;

  @override
  State<StudentAppShell> createState() => _StudentAppShellState();
}

class _StudentAppShellState extends State<StudentAppShell>
    with WidgetsBindingObserver {
  int refreshToken = 0;
  bool syncing = false;
  String? syncError;
  late bool loggedIn;
  bool checkingSession = true;
  Timer? syncPoller;
  Duration _pollInterval = const Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    loggedIn = false;
    WidgetsBinding.instance.addObserver(this);
    _restoreAuthenticatedSession();
  }

  Future<void> _restoreAuthenticatedSession() async {
    final session = await widget.authStore.read();
    if (!mounted) return;
    setState(() {
      loggedIn = session != null &&
          widget.database.getCurrentStudent()?.id == session.studentId;
      checkingSession = false;
    });
    if (loggedIn) {
      await sync();
      _startSyncPolling();
    }
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
    if (syncing || !mounted) return false;
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
          authStore: widget.authStore,
        ).sync();
      } catch (_) {
        bootstrapOk = false;
      }
      if (!mounted) return false;
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
      _pollInterval = proofSync.retryPending > 0
          ? const Duration(seconds: 5)
          : const Duration(seconds: 30);
      return bootstrapOk && proofSync.retryPending == 0;
    } catch (_) {
      if (mounted) {
        setState(() => syncError = 'Sync failed');
      }
      _pollInterval = const Duration(seconds: 10);
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
    void scheduleNext() {
      syncPoller = Timer(_pollInterval, () async {
        if (!mounted || syncing || !loggedIn) return;
        await _syncInternal(forceProofSync: true);
        if (mounted && loggedIn) scheduleNext();
      });
    }

    scheduleNext();
  }

  @override
  Widget build(BuildContext context) {
    if (checkingSession) {
      return const AppLaunchScreen();
    }
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
        authStore: widget.authStore,
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

/// Branded splash shown while the local records open / the session restores.
class AppLaunchScreen extends StatelessWidget {
  const AppLaunchScreen({super.key, this.message = 'Opening your records'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ProductColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: AmbientGlow(alignment: Alignment(0, -0.15), opacity: 0.26),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ProductSpacing.x5),
                child: Semantics(
                  liveRegion: true,
                  label: 'Loading. $message',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _LaunchMark(),
                      const SizedBox(height: ProductSpacing.x6),
                      Text(
                        'OfflineQR',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.2,
                                ),
                      ),
                      const SizedBox(height: ProductSpacing.x5),
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(height: ProductSpacing.x3),
                      Text(
                        '$message...',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the protected local database cannot be opened.
class StorageUnavailableScreen extends StatelessWidget {
  const StorageUnavailableScreen({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ProductColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ProductSpacing.x5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: StateView.error(
                title: 'Attendance storage unavailable',
                message:
                    'The app could not open its protected local records. Try again, or restart the app before attempting attendance.',
                actionLabel: 'Try again',
                onAction: onRetry,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LaunchMark extends StatelessWidget {
  const _LaunchMark();

  @override
  Widget build(BuildContext context) {
    return GlowMark(
      size: 120,
      child: Container(
        width: 112,
        height: 112,
        padding: const EdgeInsets.all(ProductSpacing.x4),
        decoration: BoxDecoration(
          color: ProductColors.surfaceElevated,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
              color: ProductColors.brandPrimary.withValues(alpha: 0.4)),
        ),
        child: Image.asset(
          'assets/branding/app_icon/offlineqr_splash_mark_1024.png',
          errorBuilder: (context, error, stack) => const Icon(
              Icons.qr_code_2_rounded,
              size: 56,
              color: ProductColors.brandPrimary),
        ),
      ),
    );
  }
}

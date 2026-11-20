import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../core/network/api_config.dart';
import '../../core/security/student_auth_service.dart';
import '../../core/security/student_auth_store.dart';
import '../../core/sync/bootstrap_sync_service.dart';
import '../../ui/dark_kit.dart';
import '../../ui/dark_kit_extra_b.dart';
import '../../ui/product_components.dart';
import '../../ui/product_theme.dart';
import '../../ui/responsive.dart';

class StudentLoginPage extends StatefulWidget {
  const StudentLoginPage({
    super.key,
    required this.database,
    required this.onLoginComplete,
    required this.authStore,
  });

  final LocalAttendanceDatabase database;
  final VoidCallback onLoginComplete;
  final StudentAuthStore authStore;

  @override
  State<StudentLoginPage> createState() => _StudentLoginPageState();
}

class _StudentLoginPageState extends State<StudentLoginPage> {
  final rollController = TextEditingController();
  final passwordController = TextEditingController();
  bool obscurePassword = true;
  bool loading = false;
  String? error;
  String? rollError;
  String? passwordError;

  @override
  void dispose() {
    rollController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final roll = rollController.text.trim();
    final rollProblem = LoginValidation.rollProblem(roll);
    final passwordProblem =
        LoginValidation.passwordProblem(passwordController.text);
    if (rollProblem != null || passwordProblem != null) {
      setState(() {
        rollError = rollProblem;
        passwordError = passwordProblem;
        error = null;
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
      rollError = null;
      passwordError = null;
    });
    try {
      final auth =
          StudentAuthService(baseUri: apiBaseUri(), store: widget.authStore);
      final result = await auth.login(
        rollNumber: roll,
        password: passwordController.text,
      );
      if (result.mustChangePassword) {
        final changed =
            await _requirePasswordChange(auth, passwordController.text);
        if (!changed) return;
        throw StateError(
            'Password changed. Sign in again with your new password.');
      }
      await BootstrapSyncService(
        database: widget.database,
        baseUri: apiBaseUri(),
        authStore: widget.authStore,
      ).sync();
      widget.onLoginComplete();
    } catch (exception) {
      if (mounted) {
        setState(
            () => error = exception.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<bool> _requirePasswordChange(
      StudentAuthService auth, String currentPassword) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: ProductColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _CreatePasswordSheet(
        auth: auth,
        currentPassword: currentPassword,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return StudentLoginView(
      rollController: rollController,
      passwordController: passwordController,
      obscurePassword: obscurePassword,
      onToggleObscure: () => setState(() => obscurePassword = !obscurePassword),
      submitting: loading,
      rollError: rollError,
      passwordError: passwordError,
      problem: error == null ? null : LoginProblem.classify(error!),
      onChanged: () {
        if (rollError != null || passwordError != null) {
          setState(() {
            rollError = null;
            passwordError = null;
          });
        }
      },
      onSubmit: login,
    );
  }
}

/// Inline validation shared by the page and tests.
class LoginValidation {
  const LoginValidation._();

  static String? rollProblem(String roll) {
    if (roll.trim().isEmpty) return 'Enter your roll number.';
    if (!RegExp(r'^[0-9]{5,12}$').hasMatch(roll.trim())) {
      return 'Roll numbers are 5 to 12 digits.';
    }
    return null;
  }

  static String? passwordProblem(String password) =>
      password.isEmpty ? 'Enter your password.' : null;
}

enum LoginIssue {
  passwordChanged,
  wrongPassword,
  lockedOut,
  offline,
  server,
  other
}

/// A sign-in failure translated into something the screen can explain.
/// Built from the error text only; attempts/minutes are shown if present.
class LoginProblem {
  const LoginProblem({
    required this.issue,
    required this.message,
    this.attemptsLeft,
    this.lockMinutes,
  });

  final LoginIssue issue;
  final String message;
  final int? attemptsLeft;
  final int? lockMinutes;

  factory LoginProblem.classify(String raw) {
    final text = raw.trim();
    final m = text.toLowerCase();
    int? firstInt(RegExp re) {
      final hit = re.firstMatch(m);
      return hit == null ? null : int.tryParse(hit.group(1)!);
    }

    if (m.startsWith('password changed')) {
      return LoginProblem(issue: LoginIssue.passwordChanged, message: text);
    }
    if (m.contains('socket') ||
        m.contains('connection') ||
        m.contains('network') ||
        m.contains('timeout') ||
        m.contains('timed out') ||
        m.contains('host lookup') ||
        m.contains('unreachable') ||
        m.contains('clientexception')) {
      return const LoginProblem(
        issue: LoginIssue.offline,
        message:
            'The attendance service is currently unreachable. Check your connection and try again.',
      );
    }
    if (m.contains('locked') ||
        m.contains('too many') ||
        m.contains('temporarily')) {
      return LoginProblem(
        issue: LoginIssue.lockedOut,
        message: text,
        lockMinutes: firstInt(RegExp(r'(\d+)\s*(?:min|m\b)')),
      );
    }
    if (m.contains('401') ||
        m.contains('credential') ||
        m.contains('invalid roll') ||
        m.contains('incorrect') ||
        m.contains('password')) {
      return LoginProblem(
        issue: LoginIssue.wrongPassword,
        message: 'The roll number or password is incorrect.',
        attemptsLeft: firstInt(RegExp(r'(\d+)\s*(?:attempt|try|tries)')),
      );
    }
    if (RegExp(r'\b5\d\d\b').hasMatch(m) ||
        m.contains('server') ||
        m.contains('internal')) {
      return LoginProblem(
          issue: LoginIssue.server,
          message: text.replaceAll(RegExp(r'_+'), ' '));
    }
    return LoginProblem(
        issue: LoginIssue.other, message: text.replaceAll(RegExp(r'_+'), ' '));
  }
}

/// Pure presentation of the sign-in screen.
class StudentLoginView extends StatelessWidget {
  const StudentLoginView({
    super.key,
    required this.rollController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.submitting,
    required this.onSubmit,
    this.rollError,
    this.passwordError,
    this.problem,
    this.onChanged,
  });

  final TextEditingController rollController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final bool submitting;
  final VoidCallback onSubmit;
  final String? rollError;
  final String? passwordError;
  final LoginProblem? problem;
  final VoidCallback? onChanged;

  Widget _banner(LoginProblem p) {
    switch (p.issue) {
      case LoginIssue.passwordChanged:
        return ProductNoticeBanner(
          title: 'Password updated',
          message: p.message,
          tone: StatusTone.success,
        );
      case LoginIssue.wrongPassword:
        final left = p.attemptsLeft;
        return ProductNoticeBanner(
          title: 'Sign in unsuccessful',
          message: left == null
              ? p.message
              : '${p.message} $left ${left == 1 ? 'attempt' : 'attempts'} left before a temporary lock.',
          tone: StatusTone.error,
        );
      case LoginIssue.lockedOut:
        final min = p.lockMinutes;
        return ProductNoticeBanner(
          title: 'Too many attempts',
          message: min == null
              ? 'Sign in is paused for a few minutes. Try again shortly.'
              : 'Sign in is paused. Try again in $min ${min == 1 ? 'minute' : 'minutes'}.',
          tone: StatusTone.warning,
        );
      case LoginIssue.offline:
        return ProductNoticeBanner(
          title: 'You are offline',
          message: p.message,
          tone: StatusTone.warning,
          action: submitting
              ? null
              : TextButton.icon(
                  onPressed: onSubmit,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
        );
      case LoginIssue.server:
        return ProductNoticeBanner(
          title: 'Server problem',
          message:
              '${p.message}\nThis is not your fault. Try again in a moment.',
          tone: StatusTone.error,
        );
      case LoginIssue.other:
        return ProductNoticeBanner(
          title: 'Sign in unsuccessful',
          message: p.message,
          tone: StatusTone.error,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const Positioned(
            top: -120,
            left: -80,
            right: -80,
            height: 520,
            child: AmbientGlow(opacity: 0.30),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth > 600
                      ? (constraints.maxWidth - 480) / 2
                      : ProductSpacing.x5,
                  vertical: ProductSpacing.x6,
                ),
                children: [
                  FadeSlideIn(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: GlowMark(
                        size: 76,
                        child: Container(
                          width: 72,
                          height: 72,
                          padding: const EdgeInsets.all(ProductSpacing.x3),
                          decoration: BoxDecoration(
                            color: ProductColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: ProductColors.brandPrimary
                                    .withValues(alpha: 0.4)),
                          ),
                          child: const ProductLogo(height: 48),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: ProductSpacing.x6),
                  CappedTextScale(
                    max: 1.4,
                    child: FadeSlideIn(
                      index: 1,
                      child: Text(
                        'Welcome to OfflineQR',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontSize: constraints.maxWidth < 340 ? 30 : 40,
                          height: 1.04,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: ProductSpacing.x3),
                  FadeSlideIn(
                    index: 2,
                    child: Text(
                      'Sign in with your institutional student credentials. Your assigned section and timetable are loaded automatically.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: ProductColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: ProductSpacing.x8),
                  FadeSlideIn(
                    index: 3,
                    child: GlassCard(
                      padding: const EdgeInsets.all(ProductSpacing.x5),
                      radius: 28,
                      glow: ProductColors.brandPrimary,
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Student sign in',
                                style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4)),
                            const SizedBox(height: ProductSpacing.x1),
                            Text(
                              'Use the same roll number registered with Institution.',
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: ProductSpacing.x4),
                            TextField(
                              controller: rollController,
                              keyboardType: TextInputType.number,
                              autofillHints: const [AutofillHints.username],
                              textInputAction: TextInputAction.next,
                              enabled: !submitting,
                              maxLines: 1,
                              scrollPadding: const EdgeInsets.all(24),
                              onChanged: (_) => onChanged?.call(),
                              decoration: _fieldDecoration(
                                labelText: 'Roll number',
                                hintText: '90010001',
                                errorText: rollError,
                                prefixIcon: const Icon(Icons.badge_outlined),
                              ),
                            ),
                            const SizedBox(height: ProductSpacing.x4),
                            TextField(
                              controller: passwordController,
                              obscureText: obscurePassword,
                              autofillHints: const [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              enabled: !submitting,
                              maxLines: 1,
                              scrollPadding: const EdgeInsets.all(24),
                              onChanged: (_) => onChanged?.call(),
                              onSubmitted: (_) =>
                                  submitting ? null : onSubmit(),
                              decoration: _fieldDecoration(
                                labelText: 'Password',
                                errorText: passwordError,
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: obscurePassword
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: onToggleObscure,
                                  icon: Icon(obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined),
                                ),
                              ),
                            ),
                            if (problem != null) ...[
                              const SizedBox(height: ProductSpacing.x4),
                              _banner(problem!),
                            ],
                            const SizedBox(height: ProductSpacing.x5),
                            _NeonButton(
                              onPressed: submitting ? null : onSubmit,
                              loading: submitting,
                              icon: Icons.login,
                              label: submitting ? 'Signing in' : 'Continue',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: ProductSpacing.x5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: 16,
                          color: ProductColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: ProductSpacing.x2),
                      Flexible(
                        child: Text(
                          'Your attendance device remains bound to your student identity.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: ProductColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatePasswordSheet extends StatelessWidget {
  const _CreatePasswordSheet({
    required this.auth,
    required this.currentPassword,
  });

  final StudentAuthService auth;
  final String currentPassword;

  @override
  Widget build(BuildContext context) {
    return CreatePasswordForm(
      onSubmit: (newPassword) => auth.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      ),
      onDone: () {
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(context).pop(true);
      },
    );
  }
}

/// Forced password change: strength meter, rule checklist, mismatch hint,
/// submit error and a short success state. [onSubmit] does the work (and
/// throws on failure); [onDone] runs after the success state was shown.
class CreatePasswordForm extends StatefulWidget {
  const CreatePasswordForm({
    super.key,
    required this.onSubmit,
    required this.onDone,
    this.successDelay = const Duration(milliseconds: 700),
  });

  final Future<void> Function(String newPassword) onSubmit;
  final VoidCallback onDone;
  final Duration successDelay;

  @override
  State<CreatePasswordForm> createState() => _CreatePasswordFormState();
}

class _CreatePasswordFormState extends State<CreatePasswordForm> {
  static const _minLength = 14;
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  bool obscure = true;
  bool saving = false;
  bool done = false;
  String? sheetError;

  @override
  void dispose() {
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  bool get _kindsOk => passwordKinds(newPassword.text) >= 3;
  bool get _longEnough => newPassword.text.length >= _minLength;
  bool get _matches =>
      confirmPassword.text.isNotEmpty &&
      confirmPassword.text == newPassword.text;

  Future<void> _submit() async {
    if (newPassword.text != confirmPassword.text) {
      setState(() => sheetError = 'The passwords do not match.');
      return;
    }
    setState(() {
      saving = true;
      sheetError = null;
    });
    try {
      await widget.onSubmit(newPassword.text);
      if (!mounted) return;
      setState(() => done = true);
      await Future<void>.delayed(widget.successDelay);
      if (mounted) widget.onDone();
    } catch (error) {
      if (mounted) {
        setState(() {
          saving = false;
          sheetError = error.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    final showMismatch =
        confirmPassword.text.isNotEmpty && !_matches && !saving;
    return PopScope(
      canPop: false,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          ProductSpacing.x5,
          ProductSpacing.x6,
          ProductSpacing.x5,
          ProductSpacing.x5 + inset,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: done
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 56, color: ProductColors.success),
                      const SizedBox(height: ProductSpacing.x3),
                      Text('Password updated',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge),
                      const SizedBox(height: ProductSpacing.x2),
                      Text('Sign in again with your new password.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Create your password',
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontSize: 26, letterSpacing: -0.8)),
                      const SizedBox(height: ProductSpacing.x2),
                      Text(
                        'Your temporary password must be replaced before attendance services can be used.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: ProductSpacing.x4),
                      TextField(
                        controller: newPassword,
                        obscureText: obscure,
                        enabled: !saving,
                        maxLines: 1,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newPassword],
                        scrollPadding: EdgeInsets.only(bottom: inset + 24),
                        onChanged: (_) => setState(() {}),
                        decoration: _fieldDecoration(
                          labelText: 'New password',
                          suffixIcon: IconButton(
                            tooltip:
                                obscure ? 'Show passwords' : 'Hide passwords',
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: ProductSpacing.x3),
                      PasswordStrengthMeter(
                          strength: passwordStrength(newPassword.text,
                              minLength: _minLength)),
                      const SizedBox(height: ProductSpacing.x3),
                      TextField(
                        controller: confirmPassword,
                        obscureText: obscure,
                        enabled: !saving,
                        maxLines: 1,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.newPassword],
                        scrollPadding: EdgeInsets.only(bottom: inset + 24),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => saving ? null : _submit(),
                        decoration: _fieldDecoration(
                          labelText: 'Confirm new password',
                          errorText: showMismatch
                              ? 'The passwords do not match.'
                              : null,
                        ),
                      ),
                      const SizedBox(height: ProductSpacing.x3),
                      _Rule(
                          ok: _longEnough,
                          label: 'At least $_minLength characters'),
                      _Rule(
                          ok: _kindsOk,
                          label:
                              'Three of: lowercase, uppercase, number, symbol'),
                      _Rule(ok: _matches, label: 'Both passwords match'),
                      if (sheetError != null) ...[
                        const SizedBox(height: ProductSpacing.x3),
                        ProductNoticeBanner(
                          title: 'Could not set password',
                          message: sheetError!,
                          tone: StatusTone.error,
                        ),
                      ],
                      const SizedBox(height: ProductSpacing.x4),
                      _NeonButton(
                        onPressed: saving ? null : _submit,
                        loading: saving,
                        icon: Icons.check_rounded,
                        label: saving ? 'Saving' : 'Set password',
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: ProductSpacing.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 18,
            color: ok ? ProductColors.success : ProductColors.textMuted,
          ),
          const SizedBox(width: ProductSpacing.x2),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration({
  required String labelText,
  String? hintText,
  String? errorText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    errorText: errorText,
    errorMaxLines: 3,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    fillColor: Colors.black.withValues(alpha: 0.35),
    border: border(Colors.white.withValues(alpha: 0.10)),
    enabledBorder: border(Colors.white.withValues(alpha: 0.10)),
    focusedBorder: border(ProductColors.brandPrimary, 1.6),
    errorBorder: border(ProductColors.error),
    focusedErrorBorder: border(ProductColors.error, 1.6),
    disabledBorder: border(Colors.white.withValues(alpha: 0.05)),
  );
}

class _NeonButton extends StatelessWidget {
  const _NeonButton({
    required this.onPressed,
    required this.label,
    this.icon,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: enabled
            ? [
                BoxShadow(
                    color: ProductColors.brandPrimary.withValues(alpha: 0.4),
                    blurRadius: 24,
                    spreadRadius: -6,
                    offset: const Offset(0, 8)),
              ]
            : null,
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 56),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          onPressed: onPressed,
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon),
          label: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

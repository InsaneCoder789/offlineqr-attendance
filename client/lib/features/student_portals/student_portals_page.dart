import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/dark_kit.dart';
import '../../ui/dark_kit_extra_b.dart';
import '../../ui/product_components.dart';
import '../../ui/responsive.dart';
import '../../ui/product_theme.dart';

/// Opens [uri] outside the app. Returns false when it could not be opened.
typedef PortalLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultLauncher(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

class StudentPortalsPage extends StatelessWidget {
  const StudentPortalsPage({
    super.key,
    this.academicPortalUri,
    this.learningPortalUri,
    this.launcher = _defaultLauncher,
  });

  static const academicUrl = String.fromEnvironment('ACADEMIC_PORTAL_URL');
  static const learningUrl = String.fromEnvironment('LEARNING_PORTAL_URL');

  /// Overrides the build-time portal addresses (used by tests and previews).
  final Uri? academicPortalUri;
  final Uri? learningPortalUri;
  final PortalLauncher launcher;

  static Uri? configuredPortal(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
        ? uri
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final academic = academicPortalUri ?? configuredPortal(academicUrl);
    final learning = learningPortalUri ?? configuredPortal(learningUrl);
    return Scaffold(
      body: SafeArea(
        child: AdaptivePage(
          children: [
            const SizedBox(height: ProductSpacing.x5),
            const ProductPageHeader(
              title: 'Institution services',
              description:
                  'Open the university services connected to your academic life.',
            ),
            const SizedBox(height: ProductSpacing.x5),
            _PortalTile(
              title: 'Academic portal',
              subtitle: 'Academic profile, examinations, fees and records',
              url: academic,
              accent: ProductColors.brandPrimary,
              launcher: launcher,
              child: const ProductLogo(height: 36),
            ),
            const SizedBox(height: ProductSpacing.x4),
            _PortalTile(
              title: 'Learning portal',
              subtitle: 'Course resources and classroom learning tools',
              url: learning,
              accent: ProductColors.info,
              launcher: launcher,
              child: const Icon(Icons.school_outlined,
                  color: ProductColors.info, size: 32),
            ),
            if (academic == null || learning == null) ...[
              const SizedBox(height: ProductSpacing.x4),
              const ProductNoticeBanner(
                title: 'Some services are not linked',
                message:
                    'Services appear here once your institution configures them.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PortalTile extends StatefulWidget {
  const _PortalTile({
    required this.title,
    required this.subtitle,
    required this.url,
    required this.child,
    required this.accent,
    required this.launcher,
  });

  final String title;
  final String subtitle;
  final Uri? url;
  final Widget child;
  final Color accent;
  final PortalLauncher launcher;

  @override
  State<_PortalTile> createState() => _PortalTileState();
}

class _PortalTileState extends State<_PortalTile> {
  bool _opening = false;
  bool _failed = false;

  Future<void> _open() async {
    final url = widget.url;
    if (url == null || _opening) return;
    setState(() {
      _opening = true;
      _failed = false;
    });
    var opened = false;
    try {
      opened = await widget.launcher(url);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    setState(() {
      _opening = false;
      _failed = !opened;
    });
  }

  void _showNotSetUp() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: ProductColors.surface,
      showDragHandle: true,
      builder: (_) => PortalNotSetUpSheet(portalName: widget.title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configured = widget.url != null;
    final c = widget.accent;
    return FadeSlideIn(
      child: MergeSemantics(
        child: Semantics(
          button: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  c.withValues(alpha: 0.30),
                  ProductColors.surface,
                  ProductColors.surface
                ],
                stops: const [0, 0.6, 1],
              ),
              border: Border.all(color: c.withValues(alpha: 0.28)),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: configured ? _open : _showNotSetUp,
                child: Padding(
                  padding: const EdgeInsets.all(ProductSpacing.x5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            padding: const EdgeInsets.all(ProductSpacing.x2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(20),
                              border:
                                  Border.all(color: c.withValues(alpha: 0.35)),
                            ),
                            child: Center(child: widget.child),
                          ),
                          const SizedBox(width: ProductSpacing.x3),
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: configured
                                  ? const NeonPill(
                                      label: 'Ready', icon: Icons.link_rounded)
                                  : const NeonPill(
                                      label: 'Not set up',
                                      color: ProductColors.warning,
                                      icon: Icons.settings_suggest_outlined,
                                    ),
                            ),
                          ),
                          const SizedBox(width: ProductSpacing.x3),
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.07),
                            ),
                            child: _opening
                                ? Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: c),
                                  )
                                : Icon(
                                    configured
                                        ? Icons.open_in_new_rounded
                                        : Icons.info_outline_rounded,
                                    color: c,
                                    size: 22,
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: ProductSpacing.x5),
                      Text(widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontSize: 24, letterSpacing: -0.6)),
                      const SizedBox(height: ProductSpacing.x1),
                      Text(
                        configured
                            ? widget.subtitle
                            : 'Your institution has not set this up yet. Tap to see who to contact.',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (configured) ...[
                        const SizedBox(height: ProductSpacing.x3),
                        Row(
                          children: [
                            Icon(Icons.north_east_rounded, size: 16, color: c),
                            const SizedBox(width: ProductSpacing.x1),
                            Expanded(
                              child: Text(
                                widget.url!.host,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                    color: c, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_failed) ...[
                        const SizedBox(height: ProductSpacing.x3),
                        _OpenError(title: widget.title, onRetry: _open),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline replacement for the old "could not be opened" snackbar.
class _OpenError extends StatelessWidget {
  const _OpenError({required this.title, required this.onRetry});

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ProductColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(ProductRadius.medium),
          border:
              Border.all(color: ProductColors.error.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(ProductSpacing.x3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 20, color: ProductColors.error),
              const SizedBox(width: ProductSpacing.x2),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: ProductSpacing.x2,
                  children: [
                    Text(
                        '$title could not be opened. Check your connection or browser, then try again.',
                        style: text.bodyMedium
                            ?.copyWith(color: ProductColors.textPrimary)),
                    TextButton(
                        onPressed: onRetry, child: const Text('Try again')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet explaining that a portal is not configured and who to ask.
class PortalNotSetUpSheet extends StatelessWidget {
  const PortalNotSetUpSheet({super.key, required this.portalName});

  final String portalName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            ProductSpacing.x5, 0, ProductSpacing.x5, ProductSpacing.x5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconChip(
                  icon: Icons.settings_suggest_outlined,
                  color: ProductColors.warning),
            ),
            const SizedBox(height: ProductSpacing.x3),
            Text('$portalName is not set up',
                style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: ProductSpacing.x2),
            Text(
              'This app has not been linked to your institution\'s $portalName yet, so there is nothing to open. '
              'Your attendance and scanning are not affected.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: ProductSpacing.x4),
            Text('Who to contact',
                style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ProductColors.textPrimary)),
            const SizedBox(height: ProductSpacing.x2),
            const _ContactLine(
                icon: Icons.apartment_rounded,
                text: 'Your department or academic office'),
            const _ContactLine(
                icon: Icons.support_agent_rounded,
                text: 'The university IT helpdesk'),
            const _ContactLine(
                icon: Icons.person_outline_rounded,
                text: 'Your class coordinator or faculty advisor'),
            const SizedBox(height: ProductSpacing.x2),
            Text(
                'Ask them to enable this service for the OfflineQR app. It appears here automatically after an update.',
                style: text.bodySmall),
            const SizedBox(height: ProductSpacing.x4),
            FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Got it')),
          ],
        ),
      ),
    );
  }
}

class _ContactLine extends StatelessWidget {
  const _ContactLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ProductSpacing.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: ProductColors.brandPrimary),
          const SizedBox(width: ProductSpacing.x3),
          Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: ProductColors.textPrimary))),
        ],
      ),
    );
  }
}

import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/material.dart';

import '../aurora/aurora_shapes.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import '../messaging/message_repository.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.repository,
    required this.onReady,
    required this.onSkip,
  });

  final MessageRepository repository;
  final VoidCallback onReady;
  final VoidCallback onSkip;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.requestAccess();
      final access = await widget.repository.access();
      if (!mounted) return;
      if (access.ready) {
        widget.onReady();
      } else {
        setState(() => _error = tr("The default SMS role was not granted. You can try again in Settings."));
      }
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final aurora = context.aurora;
    return AuroraScaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AuroraShapeContainer(
                    shape: AuroraShapes.fab,
                    size: 44,
                    gradient: [scheme.primary, scheme.tertiary],
                    glow: aurora.glow,
                    child: Icon(Icons.bolt_rounded, size: 21, color: scheme.onPrimary),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    tr("Qingniao"),
                    style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    'AURORA',
                    style: context.texts.labelSmall?.copyWith(
                      letterSpacing: 2,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 34),
              Center(child: AuroraBloom(size: 156)),
              const SizedBox(height: 18),
              Text(
                tr("Make room for\nwhat matters."),
                style: context.texts.displayMedium?.copyWith(
                  height: 1.12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1.4,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                tr("Keep SMS, verification codes and MMS together, with colors and motion you control."),
                style: context.texts.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.7),
              ),
              const SizedBox(height: 28),
               _FeatureRow(
                icon: Icons.shield_outlined,
                title: tr("Verification codes stay on your device"),
                body: tr("Message analysis runs locally, without ads or analytics SDKs."),
              ),
               _FeatureRow(
                icon: Icons.auto_awesome_outlined,
                title: 'Material 3 Expressive',
                body: tr("Shapes respond smoothly as the interface changes."),
              ),
               _FeatureRow(
                icon: Icons.memory_rounded,
                title: tr("Local processing"),
                body: tr("Search, message segmentation and encryption run on this device."),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: AuroraGlass(
                    padding: const EdgeInsets.all(14),
                    color: scheme.errorContainer.withValues(alpha: .5),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 18, color: scheme.onErrorContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: context.texts.bodySmall?.copyWith(
                              color: scheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _request,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sms_outlined),
                  label: Text(_busy ? tr("Waiting for system confirmation\u2026") : tr("Set as default SMS app")),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: widget.onSkip,
                  child:  Text(tr("Explore first")),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  tr("You can change your default SMS app in system settings at any time"),
                  style: context.texts.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: .75),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: ShapeDecoration(
              shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(15)),
              color: scheme.secondaryContainer.withValues(alpha: .6),
            ),
            child: Icon(icon, size: 20, color: scheme.onSecondaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.texts.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: context.texts.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

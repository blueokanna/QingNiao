import '../aurora/aurora_shapes.dart';

import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/material.dart';

import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import '../messaging/format.dart';
import '../messaging/message_hub.dart';
import '../messaging/message_repository.dart';
import '../messaging/message_widgets.dart';
import '../messaging/models.dart';
import 'conversation_screen.dart';

class OtpScreen extends StatelessWidget {
  const OtpScreen({super.key, required this.repository, required this.hub});

  final MessageRepository repository;
  final MessageHub hub;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: hub,
      builder: (context, _) {
        final items = hub.allThreads
            .where((thread) => thread.hasOtp)
            .toList(growable: false);
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.paddingOf(context).top + 8),
            ),
            SliverToBoxAdapter(
              child: AuroraLargeHeader(
                title: tr("Verification codes"),
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
              ),
            ),
            if (items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(top: 20),
                  child: AuroraEmpty(
                    title: tr("No verification codes yet"),
                    message: tr(
                      "Codes found in your messages will appear here.",
                    ),
                    icon: Icons.shield_outlined,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
                sliver: SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final thread = items[index];
                    return Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 10),
                      child: _OtpCard(
                        thread: thread,
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ConversationScreen(
                              repository: repository,
                              hub: hub,
                              thread: thread,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OtpCard extends StatelessWidget {
  const _OtpCard({required this.thread, required this.onOpen});

  final ThreadSummary thread;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final aurora = context.aurora;
    return AuroraGlass(
      radius: 28,
      gradient: [Color.alphaBlend(aurora.otpSoft, aurora.glass), aurora.glass],
      child: AuroraPressable(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AuroraAvatar(seed: thread.address, size: 38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          thread.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.titleSmall,
                        ),
                        if (thread.title != thread.address)
                          Text(
                            MessageFormat.phone(thread.address),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      MessageFormat.inboxTime(thread.date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        thread.otp!,
                        style: context.texts.displayMedium?.copyWith(
                          fontSize: 40,
                          letterSpacing: 6,
                          fontWeight: FontWeight.w600,
                          color: aurora.otp,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OtpChip(code: thread.otp!, iconOnly: true),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                thread.preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      tr("Processed on this device"),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelSmall?.copyWith(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (thread.unread > 0)
                    AuroraBadge(count: thread.unread, small: true),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

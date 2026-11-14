import 'package:flutter/material.dart';

import '../aurora/aurora_shapes.dart';
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
        final items = hub.threads.where((thread) => thread.hasOtp).toList(growable: false);
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              child: Row(
                children: [
                  const SizedBox(width: 20),
                  AuroraShapeContainer(
                    shape: AuroraShapes.nav,
                    size: 40,
                    gradient: [context.colors.tertiary, context.colors.primary],
                    child: Icon(Icons.shield_rounded, size: 19, color: context.colors.onPrimary),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '验证码',
                    style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: AuroraLargeHeader(
                eyebrow: 'LOCAL · ON DEVICE',
                title: '验证码',
                description: '${items.length} 条可用 · 解析只在本机完成，不会上传正文',
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
              ),
            ),
            if (items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: AuroraEmpty(
                    title: '还没有需要复制的验证码',
                    message: '当短信里出现验证码时，青鸟会把它们安静地收在这里。',
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
                      padding: const EdgeInsets.only(bottom: 10),
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
      gradient: [
        Color.alphaBlend(aurora.otpSoft, aurora.glass),
        aurora.glass,
      ],
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
                        Text(thread.title, style: context.texts.titleSmall),
                        Text(
                          MessageFormat.phone(thread.address),
                          style: context.texts.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    MessageFormat.inboxTime(thread.date),
                    style: context.texts.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    thread.otp!,
                    style: context.texts.displayMedium?.copyWith(
                      fontSize: 40,
                      letterSpacing: 6,
                      fontWeight: FontWeight.w600,
                      color: aurora.otp,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  OtpChip(code: thread.otp!),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                thread.preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 12, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '仅在设备端解析',
                    style: context.texts.labelSmall?.copyWith(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (thread.unread > 0) AuroraBadge(count: thread.unread, small: true),
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded, size: 16, color: scheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

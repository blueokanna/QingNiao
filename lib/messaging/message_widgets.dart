import 'package:qingniao/l10n/app_strings.dart';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../app/app_settings.dart';
import '../aurora/aurora_motion.dart';
import '../aurora/aurora_shapes.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import 'format.dart';
import 'models.dart';

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.thread,
    this.onTap,
    this.onLongPress,
    this.showSim = false,
    this.selected = false,
  });

  final ThreadSummary thread;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showSim;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final aurora = context.aurora;
    final unread = thread.unread;
    return RepaintBoundary(
      child: AuroraGlass(
        radius: 26,
        gradient: unread > 0
            ? [
                Color.alphaBlend(scheme.primaryContainer.withValues(alpha: .5), aurora.glass),
                aurora.glass,
              ]
            : null,
        color: selected ? Color.alphaBlend(scheme.primary.withValues(alpha: .14), aurora.glass) : null,
        child: AuroraPressable(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(26),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AuroraAvatar(
                      seed: thread.address,
                      size: 54,
                      unread: unread > 0,
                      label: thread.isGroup ? null : thread.title,
                      icon: thread.isGroup ? Icons.groups_2_rounded : null,
                      heroTag: 'thread-avatar-${thread.threadId}',
                    ),
                    if (unread > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: AuroraBadge(count: unread, small: true),
                      ),
                  ],
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (thread.pinned)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.push_pin_rounded, size: 13, color: scheme.primary),
                            ),
                          Expanded(
                            child: Text(
                              thread.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.texts.titleMedium?.copyWith(
                                fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            MessageFormat.inboxTime(thread.date),
                            style: context.texts.labelSmall?.copyWith(
                              color: unread > 0 ? scheme.primary : scheme.onSurfaceVariant,
                              fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (thread.hasMms)
                            Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: Icon(Icons.image_outlined, size: 14, color: scheme.onSurfaceVariant),
                            ),
                          Expanded(
                            child: Text(
                              _previewText(thread),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.texts.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (thread.hasOtp || showSim || thread.category != MessageCategory.personal) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (thread.hasOtp) ...[
                              OtpChip(code: thread.otp!, compact: true),
                              const SizedBox(width: 6),
                            ],
                            if (thread.category != MessageCategory.personal) ...[
                              CategoryTag(category: thread.category),
                              const SizedBox(width: 6),
                            ],
                            if (showSim) SimBadge(subscriptionId: thread.subscriptionId),
                            const Spacer(),
                            if (thread.count > 0 && !thread.hasOtp)
                              Text(
                                tr("Messages: {p0}", [thread.count]),
                                style: context.texts.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant.withValues(alpha: .7),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _previewText(ThreadSummary thread) {
    if (thread.hasOtp) {
      return thread.preview.replaceAll(thread.otp!, '•' * thread.otp!.length);
    }
    return thread.preview.isEmpty ? tr("(Empty message)") : thread.preview;
  }
}

class SimBadge extends StatelessWidget {
  const SimBadge({super.key, required this.subscriptionId});

  final int subscriptionId;

  @override
  Widget build(BuildContext context) {
    if (subscriptionId < 0) return const SizedBox.shrink();
    final scheme = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: ShapeDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: .55),
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(99)),
      ),
      child: Text(
        'SIM ${subscriptionId == 0 ? 1 : subscriptionId}',
        style: context.texts.labelSmall?.copyWith(
          color: scheme.onTertiaryContainer,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class CategoryTag extends StatelessWidget {
  const CategoryTag({super.key, required this.category});

  final MessageCategory category;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (category) {
      MessageCategory.verification => (tr("Verification codes"), Icons.lock_outline_rounded),
      MessageCategory.finance => (tr("Finance"), Icons.account_balance_outlined),
      MessageCategory.promotion => (tr("Promotions"), Icons.local_offer_outlined),
      MessageCategory.personal => (tr("Personal"), Icons.chat_bubble_outline_rounded),
    };
    final scheme = context.colors;
    final color = switch (category) {
      MessageCategory.verification => scheme.tertiary,
      MessageCategory.finance => scheme.primary,
      MessageCategory.promotion => scheme.onSurfaceVariant,
      MessageCategory.personal => scheme.secondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: .1),
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(99)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10.5, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class OtpChip extends StatefulWidget {
  const OtpChip({
    super.key,
    required this.code,
    this.compact = false,
    this.inverted = false,
    this.onCopied,
  });

  final String code;
  final bool compact;
  final bool inverted;
  final VoidCallback? onCopied;

  @override
  State<OtpChip> createState() => _OtpChipState();
}

class _OtpChipState extends State<OtpChip> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() => _copied = true);
    widget.onCopied?.call();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return AuroraPressable(
      onTap: _copy,
      pressedScale: .05,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: AuroraMotion.base,
        padding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 12, vertical: widget.compact ? 3 : 7),
        decoration: ShapeDecoration(
          color: widget.inverted
              ? aurora.outgoingText.withValues(alpha: _copied ? .26 : .16)
              : aurora.otpSoft,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(widget.compact ? 10 : 14),
            side: BorderSide(color: aurora.otp.withValues(alpha: .22)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: AuroraMotion.fast,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                _copied ? Icons.check_rounded : Icons.content_copy_rounded,
                key: ValueKey(_copied),
                size: widget.compact ? 11 : 14,
                color: widget.inverted ? aurora.outgoingText : aurora.otp,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              widget.code,
              style: TextStyle(
                fontSize: widget.compact ? 11 : 13.5,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: widget.inverted ? aurora.outgoingText : aurora.otp,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.groupedTop = false,
    this.groupedBottom = false,
    this.selected = false,
    this.onLongPress,
    this.onRetry,
    this.onOpenLink,
    this.onOpenAttachment,
    this.revealIndex = 0,
  });

  final SmsMessage message;
  final bool groupedTop;
  final bool groupedBottom;
  final bool selected;
  final VoidCallback? onLongPress;
  final VoidCallback? onRetry;
  final ValueChanged<String>? onOpenLink;
  final ValueChanged<Attachment>? onOpenAttachment;
  final int revealIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final aurora = context.aurora;
    final settings = AppScope.maybeOf(context);
    final style = settings?.bubbleStyle ?? AuroraBubbleStyle.soft;
    final outgoing = message.outgoing;
    final radius = switch (style) {
      AuroraBubbleStyle.capsule => 28.0,
      AuroraBubbleStyle.cookie => 30.0,
      AuroraBubbleStyle.soft => 24.0,
    };
    final small = 7.0;
    final border = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(groupedTop && !outgoing ? small : radius),
        topRight: Radius.circular(groupedTop && outgoing ? small : radius),
        bottomLeft: Radius.circular(groupedBottom && !outgoing ? small : (outgoing ? radius : small)),
        bottomRight: Radius.circular(groupedBottom && outgoing ? small : (outgoing ? small : radius)),
      ),
      side: selected
          ? BorderSide(color: scheme.primary, width: 1.6)
          : (outgoing ? BorderSide.none : BorderSide(color: aurora.hairline, width: 1)),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.sender.isNotEmpty && !outgoing) ...[
          Text(
            message.sender,
            style: context.texts.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
        ],
        if (message.isMms && message.attachments.isNotEmpty)
          AttachmentGrid(
            attachments: message.attachments,
            onOpen: onOpenAttachment,
            outgoing: outgoing,
          ),
        if (message.body.isNotEmpty)
          _MessageText(
            message: message,
            outgoing: outgoing,
            onOpenLink: onOpenLink,
          ),
        if (message.hasOtp) ...[
          const SizedBox(height: 8),
          OtpChip(code: message.otp!, inverted: outgoing),
        ],
        const SizedBox(height: 5),
        Wrap(
          spacing: 5,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (message.isMms)
              Icon(
                Icons.image_outlined,
                size: 11,
                color: outgoing ? context.aurora.outgoingText.withValues(alpha: .7) : scheme.onSurfaceVariant,
              ),
            Text(
              MessageFormat.time(message.date),
              style: context.texts.labelSmall?.copyWith(
                fontSize: 10,
                color: outgoing
                    ? context.aurora.outgoingText.withValues(alpha: .6)
                    : scheme.onSurfaceVariant.withValues(alpha: .7),
              ),
            ),
            if (outgoing) _DeliveryMark(state: message.delivery, onDark: true),
            if (outgoing && message.subscriptionId >= 0)
              Text(
                'SIM ${message.subscriptionId == 0 ? 1 : message.subscriptionId}',
                style: TextStyle(
                  fontSize: 9.5,
                  color: context.aurora.outgoingText.withValues(alpha: .55),
                ),
              ),
          ],
        ),
        if (message.isFailed)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: TextButton.icon(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 30),
                foregroundColor: outgoing ? context.aurora.outgoingText : scheme.error,
                textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 13),
              label:  Text(tr("Resend")),
            ),
          ),
      ],
    );

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
      padding: EdgeInsets.fromLTRB(14, message.body.isEmpty && message.hasAttachments ? 8 : 11, 14, 9),
      decoration: ShapeDecoration(
        shape: border,
        color: outgoing ? null : aurora.incomingBubble,
        gradient: outgoing ? aurora.outgoingGradient : null,
        shadows: outgoing
            ? [BoxShadow(color: scheme.primary.withValues(alpha: .08), blurRadius: 18, offset: const Offset(0, 6))]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? .18 : .045),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: DefaultTextStyle.merge(
        style: context.texts.bodyLarge?.copyWith(
          color: outgoing ? aurora.outgoingText : aurora.incomingText,
          height: 1.48,
        ),
        child: content,
      ),
    );

    return AuroraReveal(
      index: revealIndex,
      offset: outgoing ? 10 : 14,
      child: Padding(
        padding: EdgeInsets.only(
          left: outgoing ? 44 : 0,
          right: outgoing ? 0 : 44,
          top: groupedTop ? 2 : 7,
          bottom: groupedBottom ? 2 : 5,
        ),
        child: Align(
          alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: onLongPress,
            child: RepaintBoundary(child: bubble),
          ),
        ),
      ),
    );
  }
}

class _MessageText extends StatelessWidget {
  const _MessageText({required this.message, required this.outgoing, this.onOpenLink});

  final SmsMessage message;
  final bool outgoing;
  final ValueChanged<String>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final base = DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];
    final body = message.body;
    final matches = RegExp(r'https?://[^\s<>()（）]+').allMatches(body).toList();
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) spans.add(TextSpan(text: body.substring(cursor, match.start)));
      var url = match.group(0)!;
      while (url.isNotEmpty && '.,;:!?，。；：！？'.contains(url[url.length - 1])) {
        url = url.substring(0, url.length - 1);
      }
      spans.add(
        TextSpan(
          text: url,
          style: TextStyle(
            color: outgoing ? context.aurora.outgoingText : scheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: (outgoing ? context.aurora.outgoingText : scheme.primary).withValues(alpha: .5),
          ),
          recognizer: TapGestureRecognizer()..onTap = () => onOpenLink?.call(url),
        ),
      );
      cursor = match.start + url.length;
    }
    if (cursor < body.length) spans.add(TextSpan(text: body.substring(cursor)));

    final otp = message.otp;
    if (otp != null && otp.isNotEmpty) {
      for (var index = 0; index < spans.length; index++) {
        final span = spans[index];
        if (span is TextSpan && span.text != null && span.text!.contains(otp)) {
          final text = span.text!;
          final at = text.indexOf(otp);
          spans[index] = TextSpan(
            children: [
              if (at > 0) TextSpan(text: text.substring(0, at)),
              TextSpan(
                text: otp,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: outgoing ? context.aurora.outgoingText : context.aurora.otp,
                  backgroundColor: outgoing
                      ? context.aurora.outgoingText.withValues(alpha: .14)
                      : context.aurora.otpSoft,
                ),
              ),
              if (at + otp.length < text.length) TextSpan(text: text.substring(at + otp.length)),
            ],
            style: span.style,
          );
          break;
        }
      }
    }

    return Text.rich(TextSpan(style: base, children: spans));
  }
}

class _DeliveryMark extends StatelessWidget {
  const _DeliveryMark({required this.state, this.onDark = false});

  final DeliveryState state;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final color = onDark
        ? context.colors.onPrimaryContainer.withValues(alpha: .62)
        : context.colors.onSurfaceVariant;
    final (icon, tooltip) = switch (state) {
      DeliveryState.sending => (Icons.schedule_rounded, tr("Sending")),
      DeliveryState.sent => (Icons.done_rounded, tr("Sent")),
      DeliveryState.delivered => (Icons.done_all_rounded, tr("Delivered")),
      DeliveryState.failed => (Icons.error_outline_rounded, tr("Failed to send")),
      DeliveryState.none => (Icons.done_rounded, tr("Sent")),
    };
    return Tooltip(
      message: tooltip,
      child: Icon(icon, size: 13, color: state == DeliveryState.failed ? context.colors.error : color),
    );
  }
}

class DayDivider extends StatelessWidget {
  const DayDivider({super.key, required this.millis});

  final int millis;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              MessageFormat.dayLabel(millis),
              style: context.texts.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

class AttachmentGrid extends StatelessWidget {
  const AttachmentGrid({super.key, required this.attachments, this.onOpen, this.outgoing = false});

  final List<Attachment> attachments;
  final ValueChanged<Attachment>? onOpen;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final images = attachments.where((item) => item.isImage).toList();
    final files = attachments.where((item) => !item.isImage).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 168,
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: images.length == 1 ? 1 : 2,
                    crossAxisSpacing: 3,
                    mainAxisSpacing: 3,
                  ),
                  itemCount: math.min(images.length, 4),
                  itemBuilder: (context, index) => AttachmentPreview(
                    attachment: images[index],
                    onTap: () => onOpen?.call(images[index]),
                  ),
                ),
              ),
            ),
          ),
        for (final file in files) AttachmentPreview(attachment: file, onTap: () => onOpen?.call(file)),
      ],
    );
  }
}

class AttachmentPreview extends StatelessWidget {
  const AttachmentPreview({super.key, required this.attachment, this.onTap});

  final Attachment attachment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    if (!attachment.isImage) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: AuroraGlass(
          radius: 12,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                attachment.isVideo
                    ? Icons.videocam_outlined
                    : attachment.isAudio
                    ? Icons.graphic_eq_rounded
                    : Icons.insert_drive_file_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelSmall,
                ),
              ),
              if (attachment.size > 0) ...[
                const SizedBox(width: 8),
                Text(
                  MessageFormat.bytes(attachment.size),
                  style: context.texts.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.alphaBlend(scheme.primary.withValues(alpha: .34), scheme.surfaceContainerHigh),
              Color.alphaBlend(scheme.tertiary.withValues(alpha: .26), scheme.surfaceContainerLow),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.photo_outlined,
            color: scheme.onSurfaceVariant.withValues(alpha: .6),
            size: 30,
          ),
        ),
      ),
    );
  }
}

class MessageComposer extends StatelessWidget {
  const MessageComposer({
    super.key,
    required this.controller,
    required this.segment,
    required this.onSend,
    this.focusNode,
    this.sending = false,
    this.enabled = true,
    this.onAttach,
    this.onSchedule,
    this.onPickSim,
    this.simLabel,
    this.attachments = 0,
    this.hintText = "Write a message\u2026",
    this.onChanged,
    this.showTools = true,
  });

  final TextEditingController controller;
  final SegmentInfo segment;
  final VoidCallback onSend;
  final FocusNode? focusNode;
  final bool sending;
  final bool enabled;
  final VoidCallback? onAttach;
  final VoidCallback? onSchedule;
  final VoidCallback? onPickSim;
  final String? simLabel;
  final int attachments;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final bool showTools;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final aurora = context.aurora;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTools)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    if (onAttach != null)
                      _ToolIcon(
                        icon: Icons.add_photo_alternate_outlined,
                        tooltip: tr("Add attachment"),
                        onTap: enabled ? onAttach : null,
                        badge: attachments,
                      ),
                    if (onSchedule != null)
                      _ToolIcon(
                        icon: Icons.schedule_send_outlined,
                        tooltip: tr("Schedule message"),
                        onTap: enabled ? onSchedule : null,
                      ),
                    const Spacer(),
                    if (simLabel != null)
                      AuroraPressable(
                        onTap: enabled ? onPickSim : null,
                        borderRadius: BorderRadius.circular(12),
                        child: AuroraGlass(
                          radius: 11,
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          child: Row(
                            children: [
                              Icon(Icons.sim_card_outlined, size: 12, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(
                                simLabel!,
                                style: context.texts.labelSmall?.copyWith(fontSize: 10.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            AuroraGlass(
              radius: 26,
              color: aurora.glassStrong,
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              border: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: enabled && !sending,
                      minLines: 1,
                      maxLines: 5,
                      onChanged: onChanged,
                      textCapitalization: TextCapitalization.sentences,
                      style: context.texts.bodyLarge,
                      decoration: InputDecoration(
                        hintText: hintText,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
                      ),
                    ),
                  ),
                  _SendButton(
                    enabled: enabled && !sending && controller.text.trim().isNotEmpty,
                    sending: sending,
                    onTap: onSend,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      segment.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelSmall?.copyWith(
                        fontSize: 10,
                        color: segment.segments > 1 ? scheme.tertiary : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (segment.segments > 1)
                    Flexible(
                      child: Text(
                        tr("This message will be sent in {p0} segments", [segment.segments]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: context.texts.labelSmall?.copyWith(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  const _ToolIcon({required this.icon, required this.tooltip, this.onTap, this.badge = 0});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: AuroraPressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 38,
          height: 34,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 20, color: context.colors.onSurfaceVariant),
              if (badge > 0)
                Positioned(
                  right: 4,
                  top: 3,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: context.colors.tertiary, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.sending, required this.onTap});

  final bool enabled;
  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final shape = enabled ? MaterialShapes.cookie9Sided : MaterialShapes.circle;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: AuroraPressable(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: AuroraMotion.base,
          curve: AuroraMotion.emphasized,
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: enabled
                ? LinearGradient(
                    colors: [scheme.primary, Color.lerp(scheme.primary, scheme.secondary, .65)!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: enabled ? null : scheme.surfaceContainerHighest.withValues(alpha: .6),
          ),
          child: sending
              ? const Center(child: SizedBox(width: 20, height: 20, child: AuroraLoading(size: 18)))
              : AuroraShapeContainer(
                  shape: shape,
                  size: 46,
                  progress: 0,
                  color: Colors.transparent,
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 21,
                    color: enabled ? scheme.onPrimary : scheme.onSurfaceVariant.withValues(alpha: .5),
                  ),
                ),
        ),
      ),
    );
  }
}

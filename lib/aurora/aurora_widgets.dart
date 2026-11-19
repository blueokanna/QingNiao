import 'package:qingniao/l10n/app_strings.dart';

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../app/app_settings.dart';

import 'aurora_backdrop.dart';
import 'aurora_engine.dart';
import 'aurora_motion.dart';
import 'aurora_shapes.dart';
import 'aurora_theme.dart';

class AuroraScaffold extends StatefulWidget {
  const AuroraScaffold({
    super.key,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.resizeToAvoidBottomInset = true,
    this.extendBody = true,
    this.veil = true,
  });

  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool resizeToAvoidBottomInset;
  final bool extendBody;
  final bool veil;

  @override
  State<AuroraScaffold> createState() => _AuroraScaffoldState();
}

class _AuroraScaffoldState extends State<AuroraScaffold> {
  Timer? _idle;

  bool _onScroll(ScrollNotification notification) {
    AuroraEngine.instance.setScrolling(true);
    _idle?.cancel();
    _idle = Timer(const Duration(milliseconds: 140), () {
      AuroraEngine.instance.setScrolling(false);
    });
    return false;
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      extendBody: widget.extendBody,
      floatingActionButton: widget.floatingActionButton,
      floatingActionButtonLocation: widget.floatingActionButtonLocation,
      bottomNavigationBar: widget.bottomNavigationBar,
      body: Stack(
        children: [
          if (!AuroraBackdropScope.exists(context))
            const Positioned.fill(child: AuroraBackdrop()),
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: widget.body,
            ),
          ),
        ],
      ),
    );
  }
}

class AuroraGlass extends StatelessWidget {
  const AuroraGlass({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = 26,
    this.color,
    this.gradient,
    this.border = true,
    this.borderColor,
    this.height,
    this.width,
    this.clip = true,
    this.shadow = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? color;
  final List<Color>? gradient;
  final bool border;
  final Color? borderColor;
  final double? height;
  final double? width;
  final bool clip;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    return Container(
      width: width,
      height: height,
      margin: margin,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: ShapeDecoration(
        shape: shape,
        color: gradient == null ? (color ?? aurora.glass) : null,
        gradient: gradient == null
            ? null
            : LinearGradient(
                colors: gradient!,
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
              ),
        shadows: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .28 : .07),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ]
            : null,
      ),
      foregroundDecoration: border
          ? ShapeDecoration(
              shape: shape.copyWith(
                side: BorderSide(
                  color: borderColor ?? aurora.hairline,
                  width: 1,
                ),
              ),
            )
          : null,
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
  }
}

class AuroraPressable extends StatefulWidget {
  const AuroraPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.pressedScale = .018,
    this.haptic = true,
    this.enableFeedback = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final double pressedScale;
  final bool haptic;
  final bool enableFeedback;

  @override
  State<AuroraPressable> createState() => _AuroraPressableState();
}

class _AuroraPressableState extends State<AuroraPressable> {
  late final AuroraSpring _spring = AuroraEngine.instance.spring(
    stiffness: 460,
    dampingRatio: .72,
  );

  @override
  void dispose() {
    AuroraEngine.instance.releaseSpring(_spring);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(24);
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final animate =
        enabled &&
        widget.enableFeedback &&
        !AuroraMotion.isReduced(context) &&
        TickerMode.valuesOf(context).enabled;
    if (!animate) _spring.jumpTo(0);
    return AnimatedBuilder(
      animation: _spring,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          enableFeedback: widget.enableFeedback,
          onHighlightChanged: animate
              ? (highlighted) => _spring.animateTo(highlighted ? 1 : 0)
              : null,
          onTap: widget.onTap == null
              ? null
              : () {
                  if (widget.haptic && widget.enableFeedback) {
                    HapticFeedback.selectionClick();
                  }
                  widget.onTap!();
                },
          onLongPress: widget.onLongPress == null
              ? null
              : () {
                  if (widget.haptic && widget.enableFeedback) {
                    HapticFeedback.mediumImpact();
                  }
                  widget.onLongPress!();
                },
          child: widget.child,
        ),
      ),
      builder: (context, child) => Transform.scale(
        scale: animate ? 1 - _spring.value * widget.pressedScale : 1,
        child: child,
      ),
    );
  }
}

class AuroraIconButton extends StatelessWidget {
  const AuroraIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.badge,
    this.size = 44,
    this.filled = false,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final int? badge;
  final double size;
  final bool filled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final scheme = context.colors;
    final button = AuroraPressable(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(size * .42),
          ),
          color: filled ? scheme.primary : aurora.glass,
        ),
        child: Icon(
          icon,
          size: size * .46,
          color: color ?? (filled ? scheme.onPrimary : scheme.onSurfaceVariant),
        ),
      ),
    );
    final content = badge == null || badge == 0
        ? button
        : Badge(
            label: Text('$badge'),
            backgroundColor: scheme.error,
            child: button,
          );
    return tooltip == null
        ? content
        : Tooltip(message: tooltip!, child: content);
  }
}

class AuroraFilterBar extends StatelessWidget {
  const AuroraFilterBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final List<AuroraFilterItem> items;
  final String selected;
  final ValueChanged<String> onSelected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            _FilterChip(
              item: items[index],
              selected: items[index].value == selected,
              onTap: () => onSelected(items[index].value),
            ),
          ],
        ],
      ),
    );
  }
}

class AuroraFilterItem {
  const AuroraFilterItem(this.value, this.label, {this.icon, this.count});

  final String value;
  final String label;
  final IconData? icon;
  final int? count;
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AuroraFilterItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: item.icon == null ? null : Icon(item.icon, size: 18),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.label),
          if (item.count != null && item.count! > 0) ...[
            const SizedBox(width: 8),
            Text('${item.count}', style: context.texts.labelSmall),
          ],
        ],
      ),
    );
  }
}

class AuroraSearchField extends StatefulWidget {
  const AuroraSearchField({
    super.key,
    required this.hintText,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.leading,
    this.trailing,
    this.autofocus = false,
  });

  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? leading;
  final Widget? trailing;
  final bool autofocus;

  @override
  State<AuroraSearchField> createState() => _AuroraSearchFieldState();
}

class _AuroraSearchFieldState extends State<AuroraSearchField> {
  late final FocusNode _focus = FocusNode();
  late TextEditingController _controller =
      widget.controller ?? TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_onText);
  }

  void _onText() {
    final has = _controller.text.isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  void didUpdateWidget(AuroraSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == oldWidget.controller) return;
    final previous = _controller;
    previous.removeListener(_onText);
    _controller =
        widget.controller ?? TextEditingController.fromValue(previous.value);
    if (oldWidget.controller == null) previous.dispose();
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_onText);
  }

  @override
  void dispose() {
    _controller.removeListener(_onText);
    _focus.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SearchBar(
      controller: _controller,
      focusNode: _focus,
      autoFocus: widget.autofocus,
      hintText: widget.hintText,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(
        context.colors.surfaceContainerHigh,
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16),
      ),
      leading: widget.leading ?? const Icon(Icons.search_rounded),
      trailing: [
        if (_hasText)
          IconButton(
            tooltip: tr('Clear'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              _controller.clear();
              widget.onChanged?.call('');
            },
          )
        else if (widget.trailing != null)
          widget.trailing!,
      ],
    );
  }
}

class AuroraTopBar extends StatelessWidget {
  const AuroraTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.onBack,
    this.showBack = true,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final bool showBack;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          if (showBack) ...[
            AuroraIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: tr("Back"),
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 10),
          ],
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (compact
                              ? context.texts.titleMedium
                              : context.texts.titleLarge)
                          ?.copyWith(color: scheme.onSurface),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class AuroraLargeHeader extends StatelessWidget {
  const AuroraLargeHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.description,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(24, 16, 24, 8),
  });

  final String title;
  final String? eyebrow;
  final String? description;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!,
                    style: context.texts.labelMedium?.copyWith(
                      color: scheme.primary,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  title,
                  style: context.texts.headlineLarge?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    description!,
                    style: context.texts.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ],
      ),
    );
  }
}

Future<T?> showAuroraSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool dismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .46),
    sheetAnimationStyle: AuroraMotion.isReduced(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: AuroraMotion.sheet,
            curve: AuroraMotion.decelerate,
            reverseDuration: AuroraMotion.base,
            reverseCurve: AuroraMotion.accelerate,
          ),
    builder: (context) => AuroraSheetSurface(child: builder(context)),
  );
}

class AuroraSheetSurface extends StatelessWidget {
  const AuroraSheetSurface({
    super.key,
    required this.child,
    this.maxHeightFactor = .92,
    this.padding = const EdgeInsets.fromLTRB(20, 10, 20, 20),
  });

  final Widget child;
  final double maxHeightFactor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final aurora = context.aurora;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(top: media.padding.top + 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: media.size.height * maxHeightFactor,
        ),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: const RoundedSuperellipseBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            color: scheme.surfaceContainerHigh,
            shadows: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .24),
                blurRadius: 40,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: padding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsetsDirectional.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: aurora.hairline,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Flexible(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> showAuroraDialog<T>({
  required BuildContext context,
  required Widget title,
  required Widget content,
  List<Widget> actions = const [],
  bool dismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierColor: Colors.black.withValues(alpha: .42),
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DefaultTextStyle.merge(
              style: context.texts.headlineSmall,
              child: title,
            ),
            const SizedBox(height: 10),
            DefaultTextStyle.merge(
              style: context.texts.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
              child: content,
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ],
          ],
        ),
      ),
    ),
  );
}

void showAuroraSnack(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle_outline_rounded,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 3),
      content: Row(
        children: [
          Icon(icon, size: 18, color: context.colors.onInverseSurface),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ),
  );
}

class AuroraEmpty extends StatelessWidget {
  const AuroraEmpty({
    super.key,
    required this.title,
    this.message,
    this.action,
    this.icon,
    this.size = 128,
  });

  final String title;
  final String? message;
  final Widget? action;
  final IconData? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              AuroraBloom(size: size),
              if (icon != null)
                Icon(icon, size: 30, color: scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.texts.titleLarge,
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

class AuroraSection extends StatelessWidget {
  const AuroraSection({
    super.key,
    this.title,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
  });

  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Text(
                title!,
                style: context.texts.labelMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          AuroraGlass(
            border: false,
            color: context.colors.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class AuroraSettingTile extends StatelessWidget {
  const AuroraSettingTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.showDivider = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final color = destructive ? scheme.error : scheme.onSurface;
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: ShapeDecoration(
                        shape: RoundedSuperellipseBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        color:
                            (destructive
                                    ? scheme.errorContainer
                                    : scheme.secondaryContainer)
                                .withValues(alpha: .7),
                      ),
                      child: Icon(
                        icon,
                        size: 19,
                        color: destructive
                            ? scheme.onErrorContainer
                            : scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: context.texts.titleSmall?.copyWith(
                            color: color,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: context.texts.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ] else if (onTap != null)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 68),
            child: Divider(color: context.aurora.hairline, height: 1),
          ),
      ],
    );
  }
}

class AuroraBadge extends StatelessWidget {
  const AuroraBadge({super.key, required this.count, this.small = false});

  final int count;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8,
        vertical: small ? 1 : 2,
      ),
      constraints: BoxConstraints(minWidth: small ? 18 : 22),
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(99),
        ),
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.tertiary, .6)!,
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          fontSize: small ? 10 : 11,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: scheme.onPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class AuroraLoading extends StatelessWidget {
  const AuroraLoading({super.key, this.size = 26});

  final double size;

  @override
  Widget build(BuildContext context) {
    final engine = AuroraEngine.instance;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: engine.clock,
        builder: (context, _) => CustomPaint(
          size: Size(size * 3, size),
          painter: _LoadingPainter(
            time: engine.reduceMotion ? 0 : engine.clock.value,
            color: context.colors.primary,
          ),
        ),
      ),
    );
  }
}

class _LoadingPainter extends CustomPainter {
  _LoadingPainter({required this.time, required this.color});

  final double time;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.height * .28;
    for (var index = 0; index < 3; index++) {
      final phase = time * 2.2 - index * .55;
      final wave = (math.sin(phase) + 1) / 2;
      final lift = (math.sin(phase - .4) + 1) / 2;
      final center = Offset(
        size.width * (.2 + index * .3),
        size.height * .5 - lift * size.height * .18,
      );
      canvas.drawCircle(
        center,
        radius * (.72 + wave * .34),
        Paint()..color = color.withValues(alpha: .35 + wave * .5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LoadingPainter old) =>
      old.time != time || old.color != color;
}

class AuroraErrorBanner extends StatelessWidget {
  const AuroraErrorBanner({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: AuroraGlass(
        color: scheme.errorContainer.withValues(alpha: .55),
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 20,
              color: scheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: context.texts.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onErrorContainer,
                ),
                child: Text(tr("Retry")),
              ),
          ],
        ),
      ),
    );
  }
}

class AuroraNavBar extends StatelessWidget {
  const AuroraNavBar({
    super.key,
    required this.index,
    required this.destinations,
    required this.onSelected,
    this.blurSigma,
    this.surfaceOpacity,
    this.highlight,
  });

  final int index;
  final List<AuroraNavDestination> destinations;
  final ValueChanged<int> onSelected;
  final double? blurSigma;
  final double? surfaceOpacity;
  final bool? highlight;

  // Integer slider steps bound this cache to 33 small filter objects.
  static final _blurFilters = <int, ui.ImageFilter>{};

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final settings = AppScope.maybeOf(context);
    final sigma = (blurSigma ?? settings?.navigationBlur ?? 18).round().clamp(
      0,
      32,
    );
    final tintOpacity = MediaQuery.highContrastOf(context)
        ? .94
        : (surfaceOpacity ?? settings?.navigationOpacity ?? .78).clamp(
            .55,
            .95,
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        // Filter the live scene only inside the capsule. No snapshots or
        // animation timer: the compositor updates this when its backdrop paints.
        child: BackdropFilter(
          enabled: sigma > 0,
          filter: _blurFilters.putIfAbsent(
            sigma,
            () => ui.ImageFilter.blur(
              sigmaX: sigma.toDouble(),
              sigmaY: sigma.toDouble(),
            ),
          ),
          child: CustomPaint(
            key: const ValueKey('navigation-capsule-surface'),
            foregroundPainter:
                (highlight ?? settings?.navigationHighlight ?? true)
                ? _NavigationEdgePainter(
                    dark: Theme.of(context).brightness == Brightness.dark,
                    highContrast: MediaQuery.highContrastOf(context),
                  )
                : null,
            child: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: onSelected,
              animationDuration: AuroraMotion.duration(
                context,
                AuroraMotion.base,
              ),
              height: 80,
              backgroundColor: scheme.surfaceContainer.withValues(
                alpha: tintOpacity,
              ),
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              elevation: 0,
              indicatorShape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              destinations: [
                for (final destination in destinations)
                  GestureDetector(
                    onLongPress: destination.onLongPress,
                    child: Semantics(
                      onLongPress: destination.onLongPress,
                      child: NavigationDestination(
                        tooltip: destination.onLongPress == null ? null : '',
                        icon: Badge.count(
                          count: destination.badge,
                          isLabelVisible: destination.badge > 0,
                          child: Icon(destination.icon),
                        ),
                        selectedIcon: Badge.count(
                          count: destination.badge,
                          isLabelVisible: destination.badge > 0,
                          child: Icon(destination.selectedIcon),
                        ),
                        label: destination.label,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A static specular rim: no animation or extra offscreen compositing layer.
class _NavigationEdgePainter extends CustomPainter {
  const _NavigationEdgePainter({
    required this.dark,
    required this.highContrast,
  });

  final bool dark;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final rim = RRect.fromRectAndRadius(
      bounds.deflate(1),
      const Radius.circular(39),
    );
    // A quiet outer keyline gives the white highlight definition on light glass.
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds.deflate(.4), const Radius.circular(39.6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = Colors.black.withValues(alpha: dark ? .22 : .1),
    );
    canvas.drawRRect(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = highContrast ? 1.8 : 1.4
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: dark ? .8 : .98),
            Colors.white.withValues(alpha: dark ? .42 : .76),
            Colors.white.withValues(alpha: dark ? .1 : .3),
            Colors.white.withValues(alpha: dark ? .4 : .72),
          ],
          stops: const [0, .36, .66, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_NavigationEdgePainter oldDelegate) =>
      dark != oldDelegate.dark || highContrast != oldDelegate.highContrast;
}

class AuroraNavDestination {
  const AuroraNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge = 0,
    this.onLongPress,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badge;
  final VoidCallback? onLongPress;
}

class AuroraFab extends StatelessWidget {
  const AuroraFab({
    super.key,
    required this.icon,
    required this.onTap,
    this.label,
    this.size = 60,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final aurora = context.aurora;
    if (label != null) {
      return FloatingActionButton.extended(
        onPressed: onTap,
        tooltip: tooltip,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        icon: Icon(icon, size: 24),
        label: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * .55,
          ),
          child: Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
    }
    final content = AuroraPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: AuroraShapeContainer(
        shape: MaterialShapes.sunny,
        width: label == null ? size : null,
        height: size,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 18),
        gradient: [
          scheme.primary,
          Color.lerp(scheme.primary, scheme.tertiary, .7)!,
        ],
        glow: aurora.glow,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: scheme.onPrimary),
            if (label != null) ...[
              const SizedBox(width: 8),
              Text(
                label!,
                style: context.texts.labelLarge?.copyWith(
                  color: scheme.onPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return tooltip == null
        ? content
        : Tooltip(message: tooltip!, child: content);
  }
}

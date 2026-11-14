import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import 'aurora_backdrop.dart';
import 'aurora_engine.dart';
import 'aurora_motion.dart';
import 'aurora_shapes.dart';
import 'aurora_theme.dart';

/// 所有页面的共同外壳：持续流动的极光背景 + 透明 Scaffold。
///
/// 背景位于最底层并由 [RepaintBoundary] 隔离；滚动会通知极光引擎降低
/// 氛围动效频率，把渲染预算留给消息列表。
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

/// 玻璃质感表面：半透明、极细描边、顶部高光，不依赖 BackdropFilter。
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
  final double? height;
  final double? width;
  final bool clip;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));
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
              shape: shape.copyWith(side: BorderSide(color: aurora.hairline, width: 1)),
            )
          : null,
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
  }
}

/// 带弹簧按压反馈的点击层。弹簧由极光引擎统一 tick，不额外创建 controller。
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
  late final AuroraSpring _spring = AuroraEngine.instance.spring(stiffness: 460, dampingRatio: .72);

  @override
  void dispose() {
    AuroraEngine.instance.releaseSpring(_spring);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(24);
    return Listener(
      onPointerDown: (_) => _spring.animateTo(1),
      onPointerUp: (_) => _spring.animateTo(0),
      onPointerCancel: (_) => _spring.animateTo(0),
      child: AnimatedBuilder(
        animation: _spring,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onTap == null
                ? null
                : () {
                    if (widget.haptic) HapticFeedback.selectionClick();
                    widget.onTap!();
                  },
            onLongPress: widget.onLongPress == null
                ? null
                : () {
                    if (widget.haptic) HapticFeedback.mediumImpact();
                    widget.onLongPress!();
                  },
            child: widget.child,
          ),
        ),
        builder: (context, child) => Transform.scale(
          scale: 1 - _spring.value * widget.pressedScale,
          child: child,
        ),
      ),
    );
  }
}

/// 玻璃图标按钮，可带未读徽章。
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
          shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(size * .42)),
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
    return tooltip == null ? content : Tooltip(message: tooltip!, child: content);
  }
}

/// 逐项形变的筛选条。选中项使用渐变与超椭圆，切换时连续过渡。
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
  const _FilterChip({required this.item, required this.selected, required this.onTap});

  final AuroraFilterItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final aurora = context.aurora;
    return AuroraPressable(
      onTap: onTap,
      pressedScale: .035,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: AuroraMotion.base,
        curve: AuroraMotion.emphasized,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(selected ? 18 : 14),
          ),
          color: selected ? null : aurora.glass,
          gradient: selected
              ? LinearGradient(colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, .5)!])
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.icon != null) ...[
              Icon(
                item.icon,
                size: 16,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              item.label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
            if (item.count != null && item.count! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.onPrimary.withValues(alpha: .2)
                      : scheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(98),
                ),
                child: Text(
                  '${item.count}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? scheme.onPrimary : scheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 搜索胶囊。聚焦时描边与阴影连续增强，不改变布局尺寸。
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
  late final TextEditingController _controller = widget.controller ?? TextEditingController();
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
  void dispose() {
    _controller.removeListener(_onText);
    _focus.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final aurora = context.aurora;
    final focused = _focus.hasFocus;
    return AnimatedContainer(
      duration: AuroraMotion.base,
      curve: AuroraMotion.emphasized,
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: focused ? scheme.primary.withValues(alpha: .55) : aurora.hairline,
            width: focused ? 1.4 : 1,
          ),
        ),
        color: aurora.glassStrong,
        shadows: focused
            ? [BoxShadow(color: scheme.primary.withValues(alpha: .12), blurRadius: 22, offset: const Offset(0, 8))]
            : null,
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 10),
            child: widget.leading ?? Icon(Icons.search_rounded, size: 20, color: scheme.onSurfaceVariant),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              textInputAction: TextInputAction.search,
              style: context.texts.bodyLarge,
              decoration: InputDecoration(
                hintText: widget.hintText,
                filled: false,
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (_hasText)
            IconButton(
              tooltip: '清除',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () {
                _controller.clear();
                widget.onChanged?.call('');
              },
            )
          else
            widget.trailing ?? const SizedBox(width: 14),
        ],
      ),
    );
  }
}

/// 页面顶部：返回、标题、副标题与操作。
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
              tooltip: '返回',
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
                  style: (compact ? context.texts.titleMedium : context.texts.titleLarge)?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
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

/// 大标题区域：eyebrow + 标题 + 描述。
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
                  style: context.texts.headlineLarge?.copyWith(color: scheme.onSurface),
                ),
                if (description != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    description!,
                    style: context.texts.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
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

/// 底部弹出的极光面板。
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
    sheetAnimationStyle: const AnimationStyle(
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
      padding: EdgeInsets.only(top: media.padding.top + 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * maxHeightFactor),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: const RoundedSuperellipseBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            color: scheme.surfaceContainerHigh,
            shadows: [
              BoxShadow(color: Colors.black.withValues(alpha: .24), blurRadius: 40, offset: const Offset(0, -8)),
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
                    margin: const EdgeInsets.only(bottom: 12),
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

/// 极光对话框。
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
              style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
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

/// 轻提示，带图标与可选操作。
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

/// 空状态：发光花朵 + 标题 + 行动。
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
              if (icon != null) Icon(icon, size: 30, color: scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: context.texts.titleLarge),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

/// 分组标题与设置卡片。
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
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: children),
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
                        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(14)),
                        color: (destructive ? scheme.errorContainer : scheme.secondaryContainer)
                            .withValues(alpha: .7),
                      ),
                      child: Icon(
                        icon,
                        size: 19,
                        color: destructive ? scheme.onErrorContainer : scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: context.texts.titleSmall?.copyWith(color: color)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: context.texts.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 12), trailing!]
                  else if (onTap != null)
                    Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 68),
            child: Divider(color: context.aurora.hairline, height: 1),
          ),
      ],
    );
  }
}

/// 未读徽章数字，滚动增长。
class AuroraBadge extends StatelessWidget {
  const AuroraBadge({super.key, required this.count, this.small = false});

  final int count;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 1 : 2),
      constraints: BoxConstraints(minWidth: small ? 18 : 22),
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(99)),
        gradient: LinearGradient(
          colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, .6)!],
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

/// 极光加载指示器：三颗 Material 形状交替形变。
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
      final center = Offset(size.width * (.2 + index * .3), size.height * .5 - lift * size.height * .18);
      canvas.drawCircle(
        center,
        radius * (.72 + wave * .34),
        Paint()..color = color.withValues(alpha: .35 + wave * .5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LoadingPainter old) => old.time != time || old.color != color;
}

/// 错误提示条。
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
            Icon(Icons.error_outline_rounded, size: 20, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: context.texts.bodySmall?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: scheme.onErrorContainer),
                child: const Text('重试'),
              ),
          ],
        ),
      ),
    );
  }
}

/// 底部导航：选中项的形状胶囊连续形变。
class AuroraNavBar extends StatelessWidget {
  const AuroraNavBar({
    super.key,
    required this.index,
    required this.destinations,
    required this.onSelected,
  });

  final int index;
  final List<AuroraNavDestination> destinations;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(28)),
          color: aurora.navSurface,
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .16),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _NavItem(
                    destination: destinations[i],
                    selected: i == index,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuroraNavDestination {
  const AuroraNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badge;
}

/// 极光主操作按钮：阳光形 M3 形状 + 渐变 + 柔光。
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
    final content = AuroraPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: AuroraShapeContainer(
        shape: MaterialShapes.sunny,
        width: label == null ? size : null,
        height: size,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 18),
        gradient: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, .7)!],
        glow: aurora.glow,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: scheme.onPrimary),
            if (label != null) ...[
              const SizedBox(width: 8),
              Text(
                label!,
                style: context.texts.labelLarge?.copyWith(color: scheme.onPrimary),
              ),
            ],
          ],
        ),
      ),
    );
    return tooltip == null ? content : Tooltip(message: tooltip!, child: content);
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.selected, required this.onTap});

  final AuroraNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return AuroraPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: AuroraMotion.base,
        curve: AuroraMotion.emphasized,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(selected ? 20 : 16),
          ),
          color: selected ? scheme.secondaryContainer.withValues(alpha: .8) : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: destination.badge > 0,
              label: Text(destination.badge > 99 ? '99+' : '${destination.badge}'),
              child: Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 23,
                color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              destination.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

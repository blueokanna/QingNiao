import 'package:flutter/material.dart';

import '../aurora/aurora_shapes.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import '../messaging/message_repository.dart';
import '../messaging/models.dart';

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

class _OnboardingScreenState extends State<OnboardingScreen> with WidgetsBindingObserver {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置或授权弹窗返回时自动复检，避免用户再点一次。
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final access = await widget.repository.access();
      if (!mounted) return;
      if (access.ready) {
        widget.onReady();
      } else if (_error != null) {
        setState(() => _error = _missingText(access));
      }
    } catch (_) {
      // 保持当前提示，等待用户主动重试。
    }
  }

  static String _missingText(AccessState access) {
    final missing = <String>[
      if (!access.defaultApp) '默认短信应用',
      if (!access.readSms) '读取短信',
      if (!access.sendSms) '发送短信',
      if (!access.receiveSms) '接收短信',
    ];
    return '还差：${missing.join('、')}。授权后会自动进入收件箱。';
  }

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
        setState(() => _error = _missingText(access));
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
                    '青鸟短信',
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
                '让重要的消息\n自然抵达。',
                style: context.texts.displayMedium?.copyWith(
                  height: 1.12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1.4,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '短信、验证码与彩信在一处安放。界面会随壁纸取色，动效由极光引擎统一调度。',
                style: context.texts.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.7),
              ),
              const SizedBox(height: 28),
              const _FeatureRow(
                icon: Icons.shield_outlined,
                title: '验证码只在本机解析',
                body: '不上传正文，不接入广告或统计 SDK。',
              ),
              const _FeatureRow(
                icon: Icons.auto_awesome_outlined,
                title: 'Material 3 Expressive',
                body: '形状随状态连续形变，页面之间没有硬切。',
              ),
              const _FeatureRow(
                icon: Icons.memory_rounded,
                title: 'Rust 引擎',
                body: '分词搜索、短信分段与端到端加密都在本地完成。',
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
                  label: Text(_busy ? '等待系统确认…' : '设为默认短信应用'),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: widget.onSkip,
                  child: const Text('先看看界面'),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '之后可以随时在系统设置中切换默认短信应用',
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

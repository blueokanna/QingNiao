import 'package:flutter/material.dart';

import '../aurora/aurora_widgets.dart';
import '../messaging/message_repository.dart';

class DeviceCompatibilityScreen extends StatefulWidget {
  const DeviceCompatibilityScreen({super.key, required this.repository});
  final MessageRepository repository;

  @override
  State<DeviceCompatibilityScreen> createState() =>
      _DeviceCompatibilityScreenState();
}

class _DeviceCompatibilityScreenState extends State<DeviceCompatibilityScreen>
    with WidgetsBindingObserver {
  Map<dynamic, dynamic>? _device;
  Map<dynamic, dynamic>? _access;
  Map<dynamic, dynamic>? _capabilities;
  bool _testing = false;
  bool _loading = true;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await Future.wait([
        widget.repository.invoke<Map>('deviceDiagnostics'),
        widget.repository.invoke<Map>('access'),
        widget.repository.invoke<Map>('notificationCapabilities'),
      ]);
      if (!mounted || request != _request) return;
      setState(() {
        _device = data[0];
        _access = data[1];
        _capabilities = data[2];
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = '无法读取设备状态，请重试');
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _open(String method) async {
    try {
      await widget.repository.invoke<void>(method);
    } catch (_) {
      if (mounted) showAuroraSnack(context, '系统未提供此设置入口，请从系统设置打开应用信息');
    }
  }

  Future<void> _testNotification() async {
    setState(() => _testing = true);
    try {
      final promoted = await widget.repository.invoke<bool>('testNotification');
      if (!mounted) return;
      showAuroraSnack(
        context,
        promoted == true
            ? '测试通知已发送，可在通知栏或流体云查看'
            : '测试通知已发送；本机未开放流体云，通知会出现在通知栏',
        icon: Icons.notifications_active_outlined,
      );
    } catch (error) {
      if (mounted) {
        showAuroraSnack(context, messageError(error), icon: Icons.error_outline_rounded);
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Widget _status(
    String label,
    bool? enabled, {
    String yes = '已开启',
    String no = '未开启',
  }) {
    return ListTile(
      title: Text(label),
      subtitle: Text(
        enabled == null
            ? '无法读取'
            : enabled
            ? yes
            : no,
      ),
      leading: Icon(
        enabled == true ? Icons.check_circle_outline : Icons.info_outline,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = _device ?? const {};
    final access = _access ?? const {};
    final manufacturer = (device['manufacturer'] as String? ?? '')
        .toLowerCase();
    final guidance = switch (manufacturer) {
      'oneplus' || 'oppo' || 'realme' => 'ColorOS / OxygenOS 的后台管理可能影响同步和定时任务。若任务延迟，请检查应用的后台活动、自启动和通知设置；菜单名称随系统版本变化。',
      'xiaomi' || 'redmi' || 'poco' =>
        'HyperOS / MIUI 的省电策略可能影响同步和定时任务。若任务延迟，请检查应用省电、自启动和通知设置；菜单名称随系统版本变化。',
      _ => '后台限制和省电模式可能影响同步及定时任务。短信与彩信还取决于默认短信角色、SIM 状态和运营商配置。',
    };
    return AuroraScaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const BackButton(),
                const Expanded(child: Text('设备与权限诊断')),
                IconButton(
                  onPressed: _loading ? null : _refresh,
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (_device != null) ...[
              Text(
                '${device['manufacturer']} ${device['model']}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text('Android API ${device['sdk']} · com.blue.qingniao'),
              const SizedBox(height: 16),
              _status('默认短信角色', access['defaultApp'] as bool?),
              _status('读取短信', access['readSms'] as bool?),
              _status('接收短信', access['receiveSms'] as bool?),
              _status('发送短信', access['sendSms'] as bool?),
              _status('系统通知', device['notificationsEnabled'] as bool?),
              _status(
                '流体云 / 实时胶囊',
                _capabilities?['fluidCloud'] == true &&
                        _capabilities?['fluidCloudActive'] == true
                    ? true
                    : false,
                yes: '已上岛：新短信会出现在状态栏胶囊',
                no: '系统未启用提升，新短信仍会即时通知',
              ),
              _status(
                '后台运行限制',
                device['batteryRestricted'] as bool?,
                yes: '系统正在限制后台运行',
                no: '系统未报告后台限制',
              ),
              _status('省电模式', device['powerSaveMode'] as bool?),
              const SizedBox(height: 16),
              Text(guidance),
              const SizedBox(height: 12),
              const Text('此页显示系统报告的状态，不代表已经通过该机型或运营商的收发测试。'),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _testing ? null : _testNotification,
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(_testing ? '正在发送…' : '发送一条测试通知'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => _open('appSettings'),
              child: const Text('应用权限与后台设置'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _open('notificationSettings'),
              child: const Text('通知设置'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _open('batterySettings'),
              child: const Text('电池优化设置'),
            ),
          ],
        ),
      ),
    );
  }
}

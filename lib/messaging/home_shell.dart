import 'dart:async';

import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/material.dart';

import '../aurora/aurora_widgets.dart';
import '../aurora/aurora_tab_transition.dart';
import '../messaging/inbox_screen.dart';
import '../messaging/message_hub.dart';
import '../messaging/message_repository.dart';
import '../messaging/otp_screen.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_engine.dart';
import 'compose_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.repository, required this.hub});

  final MessageRepository repository;
  final MessageHub hub;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  late final SyncEngine _sync = SyncEngine(widget.repository);
  Timer? _syncTimer;
  bool _syncing = false;
  int _syncTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.hub.addListener(_onHubChanged);
    widget.hub.start();
    _startForegroundSync();
  }

  void _onHubChanged() {
    if (_syncTick == widget.hub.syncTick) return;
    _syncTick = widget.hub.syncTick;
    _sync.invalidateState();
    _startForegroundSync();
  }

  Future<void> _startForegroundSync() async {
    try {
      final status = await _sync.status(refresh: false);
      if (!mounted) return;
      _syncTimer?.cancel();
      _syncTimer = null;
      if (status['enabled'] != true ||
          (WidgetsBinding.instance.lifecycleState != null &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed)) {
        return;
      }
      _syncTimer = Timer.periodic(
        const Duration(minutes: 2),
        (_) => _syncNow(),
      );
      await _syncNow();
    } catch (_) {}
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await _sync.syncNow();
      await widget.hub.refresh(silent: true);
    } catch (_) {
    } finally {
      _syncing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sync.invalidateState();
      _startForegroundSync();
    } else {
      _syncTimer?.cancel();
      _syncTimer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.hub.removeListener(_onHubChanged);
    _syncTimer?.cancel();
    _sync.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (_index == index) return;
    setState(() => _index = index);
  }

  Future<void> _compose() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ComposeScreen(repository: widget.repository, hub: widget.hub),
      ),
    );
    widget.hub.refresh(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.hub,
      builder: (context, _) {
        final hub = widget.hub;
        return AuroraScaffold(
          resizeToAvoidBottomInset: false,
          floatingActionButton: _index == 0
              ? Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 4),
                  child: AuroraFab(
                    icon: Icons.edit_rounded,
                    tooltip: tr("Compose"),
                    onTap: _compose,
                  ),
                )
              : null,
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          bottomNavigationBar: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 2),
            child: AuroraNavBar(
              index: _index,
              onSelected: _select,
              destinations: [
                AuroraNavDestination(
                  icon: Icons.forum_outlined,
                  selectedIcon: Icons.forum_rounded,
                  label: tr("Messages"),
                  badge: hub.unread,
                ),
                AuroraNavDestination(
                  icon: Icons.shield_outlined,
                  selectedIcon: Icons.shield_rounded,
                  label: tr("Verification codes"),
                  badge: hub.otpCount,
                ),
                AuroraNavDestination(
                  icon: Icons.tune_rounded,
                  selectedIcon: Icons.tune_rounded,
                  label: tr("Settings"),
                ),
              ],
            ),
          ),
          body: AuroraTabTransition(
            index: _index,
            children: [
              InboxScreen(repository: widget.repository, hub: hub),
              OtpScreen(repository: widget.repository, hub: hub),
              SettingsScreen(repository: widget.repository, hub: hub),
            ],
          ),
        );
      },
    );
  }
}

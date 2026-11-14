import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/material.dart';

import '../aurora/aurora_widgets.dart';
import '../messaging/inbox_screen.dart';
import '../messaging/message_hub.dart';
import '../messaging/message_repository.dart';
import '../messaging/otp_screen.dart';
import '../settings/settings_screen.dart';
import 'compose_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.repository, required this.hub});

  final MessageRepository repository;
  final MessageHub hub;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final PageController _pages = PageController();

  @override
  void initState() {
    super.initState();
    widget.hub.start();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (_index == index) return;
    setState(() => _index = index);
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutQuint,
    );
  }

  Future<void> _compose() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComposeScreen(repository: widget.repository, hub: widget.hub),
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
                  padding: const EdgeInsets.only(bottom: 4),
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
          body: PageView(
            controller: _pages,
            onPageChanged: (index) => setState(() => _index = index),
            physics: const BouncingScrollPhysics(),
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

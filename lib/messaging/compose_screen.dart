import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import 'format.dart';
import 'message_hub.dart';
import 'message_repository.dart';
import 'models.dart';
import 'sim_identity.dart';

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({
    super.key,
    required this.repository,
    required this.hub,
    this.initialRecipient,
    this.initialRecipients = const [],
    this.initialBody = '',
  });

  final MessageRepository repository;
  final MessageHub hub;
  final String? initialRecipient;
  final List<String> initialRecipients;
  final String initialBody;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen>
    with WidgetsBindingObserver {
  final TextEditingController _recipientInput = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final FocusNode _bodyFocus = FocusNode();
  final List<ContactChoice> _recipients = [];
  List<SimCard> _sims = const [];
  int? _simId;
  int _simGeneration = 0;
  AttachmentChoice? _attachment;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final value in [
      if (widget.initialRecipient != null) widget.initialRecipient!,
      ...widget.initialRecipients,
    ]) {
      final number = value.trim();
      if (number.isNotEmpty && !_recipients.any((r) => r.number == number)) {
        _recipients.add(ContactChoice(number: number, name: ''));
      }
    }
    _body.text = widget.initialBody;
    _loadSims();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadSims();
  }

  Future<void> _loadSims() async {
    final generation = ++_simGeneration;
    try {
      final sims = await widget.repository.subscriptions();
      if (!mounted || generation != _simGeneration) return;
      setState(() {
        _sims = sims;
        if (!sims.any((sim) => sim.id == _simId)) {
          _simId = sims.length == 1 ? sims.first.id : null;
        }
      });
    } catch (_) {
      if (mounted && generation == _simGeneration) {
        setState(() {
          _sims = const [];
          _simId = null;
        });
      }
    }
  }

  void _addRecipient(String value) {
    final number = value.trim();
    if (number.isEmpty) return;
    setState(() {
      if (!_recipients.any((item) => item.number == number)) {
        _recipients.add(ContactChoice(number: number, name: ''));
      }
      _recipientInput.clear();
    });
  }

  Future<void> _pickContact() async {
    try {
      final contact = await widget.repository.pickContact();
      if (contact == null || !mounted) return;
      if (_recipients.any((item) => item.number == contact.number)) return;
      setState(() => _recipients.add(contact));
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    }
  }

  Future<void> _pickAttachment() async {
    try {
      final attachment = await widget.repository.pickAttachment();
      if (attachment != null && mounted) {
        setState(() => _attachment = attachment);
      }
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    }
  }

  Future<void> _pickSim() async {
    await _loadSims();
    if (!mounted || _sims.length < 2) return;
    final selected = await showAuroraSheet<int>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final sim in _sims)
            AuroraSettingTile(
              title: simCardLabel(sim),
              subtitle:
                  '${tr('Subscription ID')}: ${sim.id}'
                  '${sim.carrier.isEmpty ? '' : ' · ${sim.carrier}'}',
              icon: Icons.sim_card_outlined,
              trailing: sim.id == _simId
                  ? Icon(
                      Icons.check_circle_rounded,
                      color: context.colors.primary,
                      size: 20,
                    )
                  : null,
              onTap: () => Navigator.pop(context, sim.id),
            ),
        ],
      ),
    );
    if (selected != null && mounted) setState(() => _simId = selected);
  }

  Future<void> _schedule() async {
    _addRecipient(_recipientInput.text);
    final body = _body.text.trim();
    if (body.isEmpty) {
      showAuroraSnack(
        context,
        tr("Write a message before scheduling it"),
        icon: Icons.schedule_rounded,
      );
      return;
    }
    if (_recipients.isEmpty) {
      showAuroraSnack(context, tr("Add a recipient first"));
      return;
    }
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    final at = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (at.isBefore(DateTime.now())) {
      showAuroraSnack(context, tr("Choose a future time"));
      return;
    }
    try {
      await widget.repository.schedule(
        address: _recipients.first.number,
        body: body,
        at: at.millisecondsSinceEpoch,
        subscriptionId: _simId,
      );
      _body.clear();
      if (mounted) {
        showAuroraSnack(
          context,
          tr("Scheduled for {p0}", [
            MessageFormat.dateTime(at.millisecondsSinceEpoch),
          ]),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    // Tapping Send does not submit the phone keyboard's current value.
    _addRecipient(_recipientInput.text);
    final body = _body.text.trim();
    if (_recipients.isEmpty) {
      setState(() => _error = tr("Add at least one recipient"));
      return;
    }
    if (body.isEmpty && _attachment == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final signature = AppScope.of(context).signature.trim();
      final full = signature.isEmpty || body.isEmpty
          ? body
          : '$body\n\n$signature';
      if (_attachment != null || _recipients.length > 1) {
        await widget.repository.sendMms(
          recipients: _recipients
              .map((item) => item.number)
              .toList(growable: false),
          body: full,
          subscriptionId: _simId,
          attachment: _attachment?.uri,
        );
      } else {
        await widget.repository.send(
          address: _recipients.first.number,
          body: full,
          subscriptionId: _simId,
        );
      }
      widget.hub.refresh(silent: true);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recipientInput.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return AuroraScaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AuroraTopBar(
              title: tr("New message"),
              subtitle: _recipients.isEmpty
                  ? tr("Enter a number or choose a contact")
                  : tr("Recipients: {p0}", [_recipients.length]),
              actions: [
                AuroraIconButton(
                  icon: Icons.schedule_rounded,
                  tooltip: tr('Schedule message'),
                  onPressed: _sending ? null : _schedule,
                ),
                AuroraIconButton(
                  icon: Icons.send_rounded,
                  tooltip: tr("Send"),
                  filled: true,
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
            if (_error != null)
              AuroraErrorBanner(
                message: _error!,
                onRetry: () => setState(() => _error = null),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                physics: const BouncingScrollPhysics(),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final recipient in _recipients)
                        InputChip(
                          avatar: const Icon(
                            Icons.person_outline_rounded,
                            size: 16,
                          ),
                          label: Text(
                            recipient.name.isEmpty
                                ? recipient.number
                                : recipient.name,
                          ),
                          onDeleted: _sending
                              ? null
                              : () => setState(
                                  () => _recipients.remove(recipient),
                                ),
                          deleteIcon: const Icon(Icons.close_rounded, size: 15),
                          shape: RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      SizedBox(
                        width: 190,
                        child: TextField(
                          controller: _recipientInput,
                          enabled: !_sending,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          onSubmitted: _addRecipient,
                          decoration: InputDecoration(
                            hintText: tr("Number"),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      TextButton.icon(
                        onPressed: _sending ? null : _pickContact,
                        icon: const Icon(
                          Icons.person_add_alt_outlined,
                          size: 18,
                        ),
                        label: Text(tr("Choose a contact")),
                      ),
                      TextButton.icon(
                        onPressed: _sending ? null : _pickAttachment,
                        icon: const Icon(Icons.attach_file_rounded, size: 18),
                        label: Text(
                          _attachment == null
                              ? tr("Add attachment")
                              : tr("Change attachment"),
                        ),
                      ),
                    ],
                  ),
                  if (_attachment != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 10),
                      child: AuroraGlass(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.image_outlined,
                              size: 16,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _attachment!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.texts.labelSmall,
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _attachment = null),
                              icon: const Icon(Icons.close_rounded, size: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                  AuroraGlass(
                    radius: 26,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: _body,
                        focusNode: _bodyFocus,
                        enabled: !_sending,
                        minLines: 8,
                        maxLines: 18,
                        maxLength: 20000,
                        style: context.texts.bodyLarge?.copyWith(height: 1.55),
                        decoration: InputDecoration(
                          hintText: tr("Write a message\u2026"),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          counterText: '',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_sims.isNotEmpty)
                        Flexible(
                          child: ActionChip(
                            avatar: const Icon(
                              Icons.sim_card_outlined,
                              size: 15,
                            ),
                            label: Text(
                              _simId == null
                                  ? tr('Choose SIM')
                                  : MessageSimSource.resolve(
                                      _simId!,
                                      _sims,
                                    ).label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onPressed: _sending ? null : _pickSim,
                          ),
                        ),
                      const Spacer(),
                      Text(
                        MessageFormat.segment(_body.text).label,
                        style: context.texts.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

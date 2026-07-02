part of '../settings_screen.dart';

class _SosSettingsCard extends ConsumerStatefulWidget {
  const _SosSettingsCard();

  @override
  ConsumerState<_SosSettingsCard> createState() => _SosSettingsCardState();
}

class _SosSettingsCardState extends ConsumerState<_SosSettingsCard> {
  late final TextEditingController _templateCtrl;

  @override
  void initState() {
    super.initState();
    _templateCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _templateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(sosSettingsProvider);
    final channels =
        ref.watch(channelsProvider).where((c) => !c.isEmpty).toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    final contacts = ref.watch(contactsProvider);

    if (_templateCtrl.text != settings.messageTemplate) {
      _templateCtrl.text = settings.messageTemplate;
      _templateCtrl.selection = TextSelection.collapsed(
        offset: _templateCtrl.text.length,
      );
    }

    String channelLabel(ChannelInfo c) {
      final name =
          c.name.trim().isEmpty
              ? context.l10n.settingsSosUnnamedChannel
              : c.name.trim();
      return '#${c.index} $name';
    }

    Contact? selectedContact;
    for (final c in contacts) {
      if (base64Encode(c.publicKey) == settings.contactKeyBase64) {
        selectedContact = c;
        break;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sos, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Text(
                  'SOS',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.settingsSosDesc('{gps}'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SosTargetType>(
              key: ValueKey('sos_target_${settings.targetType.name}'),
              initialValue: settings.targetType,
              decoration: InputDecoration(
                labelText: context.l10n.settingsSosTarget,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: SosTargetType.channel,
                  child: Text(context.l10n.settingsSosTargetChannel),
                ),
                DropdownMenuItem(
                  value: SosTargetType.contact,
                  child: Text(context.l10n.settingsSosTargetPrivateContact),
                ),
              ],
              onChanged: (v) {
                if (v != null) {
                  ref.read(sosSettingsProvider.notifier).setTargetType(v);
                }
              },
            ),
            const SizedBox(height: 10),
            if (settings.targetType == SosTargetType.channel)
              DropdownButtonFormField<int>(
                key: ValueKey('sos_channel_${settings.channelIndex}'),
                initialValue: settings.channelIndex,
                decoration: InputDecoration(
                  labelText: context.l10n.settingsSosChannelLabel,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  if (channels.isEmpty)
                    DropdownMenuItem(
                      value: 0,
                      child: Text(context.l10n.settingsSosGeneralChannel),
                    ),
                  ...channels.map(
                    (c) => DropdownMenuItem<int>(
                      value: c.index,
                      child: Text(channelLabel(c)),
                    ),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    ref.read(sosSettingsProvider.notifier).setChannelIndex(v);
                  }
                },
              )
            else
              InkWell(
                onTap:
                    contacts.isEmpty
                        ? null
                        : () => _pickSosContact(context, contacts, settings),
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: context.l10n.settingsSosDestinationContact,
                    border: const OutlineInputBorder(),
                    suffixIcon: const Icon(Icons.search),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedContact?.displayName ??
                              (contacts.isEmpty
                                  ? context.l10n.settingsSosNoContactsAvailable
                                  : context.l10n.settingsSosTapToSearchContact),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (selectedContact != null)
                        IconButton(
                          tooltip: context.l10n.settingsSosClearContact,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed:
                              () => ref
                                  .read(sosSettingsProvider.notifier)
                                  .setContactKey(null),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _templateCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: context.l10n.settingsSosMessage,
                hintText: context.l10n.settingsSosMessageHint('{gps}'),
                border: const OutlineInputBorder(),
              ),
              onChanged:
                  (v) => ref
                      .read(sosSettingsProvider.notifier)
                      .setMessageTemplate(v),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.settingsSosIncludeGps),
              subtitle: Text(context.l10n.settingsSosIncludeGpsDesc),
              value: settings.includeGps,
              onChanged:
                  (v) =>
                      ref.read(sosSettingsProvider.notifier).setIncludeGps(v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.settingsSosHoldDuration,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '${settings.holdDurationSeconds}s',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Slider(
              min: 3,
              max: 5,
              divisions: 2,
              value: settings.holdDurationSeconds.toDouble(),
              activeColor: theme.colorScheme.error,
              onChanged:
                  (v) => ref
                      .read(sosSettingsProvider.notifier)
                      .setHoldDuration(v.round()),
            ),
            Text(
              context.l10n.settingsSosHoldDurationDesc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: _SosHoldButton(
                holdSeconds: settings.holdDurationSeconds,
                label: context.l10n.settingsSosHoldToSend,
                onActivated: () async {
                  final result =
                      await ref.read(sosServiceProvider).sendConfiguredSos();
                  if (!context.mounted) return;
                  final messenger = ScaffoldMessenger.of(context);
                  switch (result.outcome) {
                    case SosSendOutcome.sent:
                      messenger.showSnackBar(
                        SnackBar(content: Text(context.l10n.settingsSosSent)),
                      );
                    case SosSendOutcome.notConnected:
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            context.l10n.settingsSosRadioNotConnected,
                          ),
                        ),
                      );
                    case SosSendOutcome.missingContact:
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.settingsSosMissingContact),
                        ),
                      );
                    case SosSendOutcome.permissionDenied:
                    case SosSendOutcome.locationDisabled:
                    case SosSendOutcome.failed:
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            result.detail?.isNotEmpty == true
                                ? context.l10n.settingsSosSendFailedDetail(
                                  result.detail!,
                                )
                                : context.l10n.settingsSosSendFailed,
                          ),
                        ),
                      );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSosContact(
    BuildContext context,
    List<Contact> contacts,
    SosSettings settings,
  ) async {
    String query = '';

    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final q = query.trim().toLowerCase();
            final filtered =
                contacts.where((c) {
                    if (q.isEmpty) return true;
                    return c.displayName.toLowerCase().contains(q) ||
                        c.shortId.toLowerCase().contains(q);
                  }).toList()
                  ..sort(
                    (a, b) => a.displayName.toLowerCase().compareTo(
                      b.displayName.toLowerCase(),
                    ),
                  );

            return AlertDialog(
              title: Text(context.l10n.settingsSosSearchContact),
              content: SizedBox(
                width: 420,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: context.l10n.settingsSosSearchHint,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (v) => setLocal(() => query = v),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child:
                            filtered.isEmpty
                                ? Center(
                                  child: Text(
                                    context.l10n.settingsSosNoContactFound,
                                  ),
                                )
                                : ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (context, i) {
                                    final c = filtered[i];
                                    final key = base64Encode(c.publicKey);
                                    final selected =
                                        key == settings.contactKeyBase64;
                                    return ListTile(
                                      dense: true,
                                      title: Text(c.displayName),
                                      subtitle: Text(c.shortId),
                                      trailing:
                                          selected
                                              ? const Icon(Icons.check)
                                              : null,
                                      onTap: () => Navigator.of(ctx).pop(key),
                                    );
                                  },
                                ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop('__clear__'),
                  child: Text(context.l10n.commonClear),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: Text(context.l10n.commonCancel),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;
    if (result == '__clear__') {
      await ref.read(sosSettingsProvider.notifier).setContactKey(null);
      return;
    }
    if (result != null) {
      await ref.read(sosSettingsProvider.notifier).setContactKey(result);
    }
  }
}

// ---------------------------------------------------------------------------
// Hold-to-activate SOS button widget
// ---------------------------------------------------------------------------

class _SosHoldButton extends StatefulWidget {
  const _SosHoldButton({
    required this.holdSeconds,
    required this.label,
    required this.onActivated,
  });

  final int holdSeconds;
  final String label;
  final Future<void> Function() onActivated;

  @override
  State<_SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<_SosHoldButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.holdSeconds),
    )..addStatusListener(_onStatus);
  }

  Future<void> _onStatus(AnimationStatus status) async {
    if (status == AnimationStatus.completed && mounted && !_sending) {
      setState(() => _sending = true);
      await widget.onActivated();
      if (mounted) {
        setState(() => _sending = false);
        _anim.reset();
      }
    }
  }

  @override
  void didUpdateWidget(_SosHoldButton old) {
    super.didUpdateWidget(old);
    if (old.holdSeconds != widget.holdSeconds) {
      _anim.duration = Duration(seconds: widget.holdSeconds);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _start(TapDownDetails _) {
    if (!_sending) _anim.forward();
  }

  void _cancel([TapUpDetails? _]) {
    if (!_sending && _anim.status != AnimationStatus.completed) {
      _anim.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return GestureDetector(
      onTapDown: _start,
      onTapUp: _cancel,
      onTapCancel: () => _cancel(),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: color.withAlpha((30 + (180 * _anim.value).round())),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withAlpha(120), width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: _sending ? null : _anim.value,
                        strokeWidth: 3,
                        color: color,
                        backgroundColor: color.withAlpha(40),
                      ),
                      Icon(Icons.sos, size: 14, color: color),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _sending ? '…' : widget.label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

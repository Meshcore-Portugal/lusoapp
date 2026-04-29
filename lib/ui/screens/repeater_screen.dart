import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../protocol/companion_decoder.dart';
import '../../protocol/models.dart';
import '../../providers/radio_providers.dart';
import '../../services/repeater_history_store.dart';
import '../widgets/repeater/repeater_widgets.dart';
import 'repeater_help_screen.dart';

// ─── helpers ──────────────────────────────────────────────────────────────────

Uint8List _hexToBytes(String hex) {
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(bytes);
}

Contact? _findContact(String keyHex, List<Contact> contacts) {
  final key = _hexToBytes(keyHex);
  for (final c in contacts) {
    if (c.publicKey.length < key.length) continue;
    var match = true;
    for (var i = 0; i < key.length; i++) {
      if (key[i] != c.publicKey[i]) {
        match = false;
        break;
      }
    }
    if (match) return c;
  }
  return null;
}

// ─── screen ───────────────────────────────────────────────────────────────────

class RepeaterScreen extends ConsumerStatefulWidget {
  const RepeaterScreen({super.key, required this.contactKeyHex});

  final String contactKeyHex;

  @override
  ConsumerState<RepeaterScreen> createState() => _RepeaterScreenState();
}

class _RepeaterScreenState extends ConsumerState<RepeaterScreen> {
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _txPowerCtrl = TextEditingController();
  final _advertZeroHopCtrl = TextEditingController();
  final _advertFloodCtrl = TextEditingController();
  final _floodMaxCtrl = TextEditingController();

  bool _obscure = true;
  bool _loginWaiting = false;
  String? _loginError;
  bool _loggedIn = false;

  bool _pendingCommand = false;
  String? _pendingLabel;

  // Per-field loading state (field key -> in-flight)
  final Set<String> _loadingFields = <String>{};
  bool? _repeatEnabled; // null = unknown

  // Command-line history (most recent at the bottom)
  final List<RepeaterHistoryEntry> _history = <RepeaterHistoryEntry>[];
  late final RepeaterHistoryStore _historyStore;
  final TextEditingController _cmdInputCtrl = TextEditingController();
  final ScrollController _cmdScrollCtrl = ScrollController();
  int _currentTab = 0; // 0=Status, 1=Command Line, 2=Settings

  // 6-byte prefix as hex (12 chars) — key into repeaterStatusProvider
  String get _prefixHex => widget.contactKeyHex.substring(0, 12);

  Uint8List get _pubKey => _hexToBytes(widget.contactKeyHex);

  @override
  void initState() {
    super.initState();
    _historyStore = RepeaterHistoryStore(widget.contactKeyHex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(loginResultProvider.notifier).state = null;
    });
    _loadHistory();
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _txPowerCtrl.dispose();
    _advertZeroHopCtrl.dispose();
    _advertFloodCtrl.dispose();
    _floodMaxCtrl.dispose();
    _cmdInputCtrl.dispose();
    _cmdScrollCtrl.dispose();
    super.dispose();
  }

  // ── History management ────────────────────────────────────────────────────

  void _pushHistory(String command, String response) {
    _history.add(RepeaterHistoryEntry(command: command, response: response));
    unawaited(_historyStore.save(_history));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_cmdScrollCtrl.hasClients) {
        _cmdScrollCtrl.animateTo(
          _cmdScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadHistory() async {
    final loaded = await _historyStore.load();
    if (!mounted || loaded.isEmpty) return;
    setState(() {
      _history
        ..clear()
        ..addAll(loaded);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_cmdScrollCtrl.hasClients) {
        _cmdScrollCtrl.jumpTo(_cmdScrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _clearHistory() async {
    setState(() => _history.clear());
    await _historyStore.clear();
  }

  // ── Help screen ───────────────────────────────────────────────────────────

  Future<void> _openHelp() async {
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => RepeaterHelpScreen(onPick: (cmd) {})),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _currentTab = 1;
      _cmdInputCtrl.text = picked;
      _cmdInputCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _cmdInputCtrl.text.length),
      );
    });
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  Future<void> _login() async {
    final service = ref.read(radioServiceProvider);
    if (service == null) return;

    ref.read(loginResultProvider.notifier).state = null;
    setState(() {
      _loginWaiting = true;
      _loginError = null;
    });

    final completer = Completer<String?>();
    late StreamSubscription<CompanionResponse> sub;
    sub = service.responses.listen((r) {
      if (completer.isCompleted) return;
      if (r is LoginSuccessPush) {
        completer.complete(null);
      } else if (r is LoginFailPush) {
        completer.complete('Falhou — verifique a palavra-passe');
      } else if (r is ErrorResponse) {
        final msg =
            r.errorCode == 2
                ? 'Contacto não encontrado no rádio — force um advert deste nó'
                : 'Erro do rádio (código ${r.errorCode})';
        completer.complete(msg);
      }
    });

    await service.login(_pubKey, _passCtrl.text);

    final error = await completer.future
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => 'Sem resposta do rádio (timeout)',
        )
        .whenComplete(sub.cancel);

    if (!mounted) return;
    if (error == null) {
      setState(() {
        _loginWaiting = false;
        _loggedIn = true;
      });
    } else {
      setState(() {
        _loginWaiting = false;
        _loginError = error;
      });
    }
  }

  Future<void> _requestStats() async {
    final service = ref.read(radioServiceProvider);
    await service?.sendStatusRequest(_pubKey);
  }

  // ── CLI plumbing ──────────────────────────────────────────────────────────

  /// Returns true when [key] is the 6-byte prefix of [_pubKey].
  bool _matchesSenderPrefix(Uint8List key, Uint8List prefix) {
    if (key.length < 6) return false;
    for (var i = 0; i < 6; i++) {
      if (key[i] != prefix[i]) return false;
    }
    return true;
  }

  /// Send a CLI [command] and complete with the first matching response text.
  Future<String> _awaitResponse(
    String command, {
    Duration timeout = const Duration(seconds: 10),
    String onTimeoutText = '',
  }) async {
    final service = ref.read(radioServiceProvider);
    if (service == null) return onTimeoutText;

    final prefix = Uint8List.fromList(_pubKey.take(6).toList());
    final completer = Completer<String>();
    late StreamSubscription<CompanionResponse> sub;
    sub = service.responses.listen((r) {
      if (completer.isCompleted) return;
      if (r is PrivateMessageResponse && r.message.senderKey != null) {
        if (_matchesSenderPrefix(r.message.senderKey!, prefix)) {
          completer.complete(r.message.text.trim());
        }
      }
    });

    await service.sendAdminCommand(_pubKey, command);

    return completer.future
        .timeout(timeout, onTimeout: () => onTimeoutText)
        .whenComplete(sub.cancel);
  }

  Future<String?> _queryField(String command) async {
    final raw = await _awaitResponse(command);
    if (mounted) setState(() => _pushHistory(command, raw));
    return raw;
  }

  // Firmware GET responses are formatted as "> {value}".
  String? _parseIntResponse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return RegExp(r'-?\d+').firstMatch(raw)?.group(0);
  }

  String _stripPrompt(String raw) {
    var s = raw.trim();
    if (s.startsWith('> ')) s = s.substring(2);
    if (s.startsWith('>')) s = s.substring(1);
    return s.trim();
  }

  Future<void> _refreshField({
    required String fieldKey,
    required String command,
    required void Function(String? raw) onResult,
  }) async {
    if (_loadingFields.contains(fieldKey)) return;
    setState(() => _loadingFields.add(fieldKey));
    final raw = await _queryField(command);
    if (!mounted) return;
    setState(() {
      _loadingFields.remove(fieldKey);
      onResult(raw);
    });
  }

  Future<void> _sendCmd(String command, String label) async {
    setState(() {
      _pendingCommand = true;
      _pendingLabel = label;
    });

    final response = await _awaitResponse(
      command,
      timeout: const Duration(seconds: 15),
      onTimeoutText: '(sem resposta do nó)',
    );

    if (!mounted) return;
    setState(() {
      _pendingCommand = false;
      _pendingLabel = null;
      _pushHistory(command, response);
    });

    if (command == 'start ota' &&
        response.toLowerCase().startsWith('ok - mac:')) {
      _showOtaDialog(response);
    }
  }

  void _showOtaDialog(String response) {
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('OTA Iniciado'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.system_update_alt,
                  size: 48,
                  color: Colors.blue,
                ),
                const SizedBox(height: 12),
                Text(
                  response,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ligue-se ao nó via BLE DFU (ex: nRF Connect) para actualizar o firmware.',
                  style: TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final contacts = ref.watch(contactsProvider);
    final contact = _findContact(widget.contactKeyHex, contacts);
    final stats = ref.watch(
      repeaterStatusProvider.select((m) => m[_prefixHex]),
    );

    // Pre-populate name from contact model on first load
    if (contact != null && _nameCtrl.text.isEmpty && contact.name.isNotEmpty) {
      _nameCtrl.text = contact.name;
    }

    final displayName =
        contact?.displayName ?? widget.contactKeyHex.substring(0, 8);

    if (!_loggedIn) {
      return _buildLoginScaffold(l10n, theme, contact, displayName, stats);
    }

    final views = <Widget>[
      _buildStatusView(l10n, theme, stats),
      _buildCommandLineView(l10n, theme),
      _buildSettingsView(l10n, theme),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.repeaterTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: l10n.repeaterMenuHelp,
            onPressed: _openHelp,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.repeaterMenuClearHistory,
            onPressed: _history.isEmpty ? null : _clearHistory,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                displayName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(180),
                ),
              ),
            ),
          ),
        ),
      ),
      body: IndexedStack(index: _currentTab, children: views),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (i) => setState(() => _currentTab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.info_outline),
            selectedIcon: const Icon(Icons.info),
            label: l10n.repeaterTabStatus,
          ),
          NavigationDestination(
            icon: const Icon(Icons.terminal_outlined),
            selectedIcon: const Icon(Icons.terminal),
            label: l10n.repeaterTabCommandLine,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.repeaterTabSettings,
          ),
        ],
      ),
    );
  }

  // ── Pre-auth view ──────────────────────────────────────────────────────────

  Widget _buildLoginScaffold(
    AppLocalizations l10n,
    ThemeData theme,
    Contact? contact,
    String displayName,
    RepeaterStats? stats,
  ) {
    return Scaffold(
      appBar: AppBar(title: Text(l10n.repeaterTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RepeaterIdentityCard(
            name: displayName,
            contact: contact,
            loggedIn: _loggedIn,
          ),
          const SizedBox(height: 16),
          if (stats != null) ...[
            RepeaterSectionHeader(title: l10n.contactsStats),
            const SizedBox(height: 8),
            RepeaterStatsCard(stats: stats),
            const SizedBox(height: 16),
          ],
          RepeaterSectionHeader(title: l10n.contactsAuth),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: l10n.contactsPassword,
                      hintText: l10n.contactsPasswordHint,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline),
                      errorText: _loginError,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _loginWaiting ? null : _login,
                    icon:
                        _loginWaiting
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.login),
                    label: Text(
                      _loginWaiting ? 'A ligar...' : l10n.contactsJoin,
                    ),
                  ),
                  if (stats == null) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.repeaterNoStats,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status tab ─────────────────────────────────────────────────────────────

  Widget _buildStatusView(
    AppLocalizations l10n,
    ThemeData theme,
    RepeaterStats? stats,
  ) {
    final contacts = ref.watch(contactsProvider);
    final contact = _findContact(widget.contactKeyHex, contacts);
    final displayName =
        contact?.displayName ?? widget.contactKeyHex.substring(0, 8);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        RepeaterIdentityCard(
          name: displayName,
          contact: contact,
          loggedIn: _loggedIn,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 6),
            Text(
              l10n.repeaterAuthenticated,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            RepeaterRefreshButton(
              label: l10n.repeaterFetchStats,
              enabled: !_pendingCommand,
              onTap: _requestStats,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (stats != null)
          RepeaterStatsCard(stats: stats)
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.repeaterNoStats,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  // ── Command Line tab ───────────────────────────────────────────────────────

  Widget _buildCommandLineView(AppLocalizations l10n, ThemeData theme) {
    return Column(
      children: [
        Expanded(
          child:
              _history.isEmpty
                  ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.repeaterCmdEmpty,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                  : ListView.builder(
                    controller: _cmdScrollCtrl,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _history.length,
                    itemBuilder: (_, i) {
                      final entry = _history[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '> ${entry.command}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            if (entry.response.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  entry.response,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
        ),
        if (_pendingCommand)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  '${l10n.contactsStatusSending} $_pendingLabel...',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cmdInputCtrl,
                    enabled: !_pendingCommand,
                    onSubmitted: (v) => _submitCliInput(v, l10n),
                    decoration: InputDecoration(
                      hintText: l10n.repeaterCmdHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  tooltip: l10n.repeaterCmdClear,
                  onPressed: _history.isEmpty ? null : _clearHistory,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
                IconButton(
                  onPressed:
                      _pendingCommand
                          ? null
                          : () => _submitCliInput(_cmdInputCtrl.text, l10n),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _submitCliInput(String value, AppLocalizations l10n) {
    final cmd = value.trim();
    if (cmd.isEmpty || _pendingCommand) return;
    _cmdInputCtrl.clear();
    _sendCmd(cmd, l10n.repeaterTabCommandLine);
  }

  // ── Settings tab ───────────────────────────────────────────────────────────

  Widget _buildSettingsView(AppLocalizations l10n, ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withAlpha(40),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 18, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.repeaterMinimalTrafficHint,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        RepeaterSectionHeader(title: l10n.repeaterConfig),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RepeaterConfigRow(
                  label: l10n.repeaterNodeName,
                  controller: _nameCtrl,
                  hint: 'Ex: Repetidor Lisboa',
                  enabled: !_pendingCommand,
                  loading: _loadingFields.contains('name'),
                  showRefresh: true,
                  onRefresh:
                      () => _refreshField(
                        fieldKey: 'name',
                        command: 'get name',
                        onResult: (raw) {
                          if (raw == null || raw.isEmpty) return;
                          final cleaned = _stripPrompt(raw);
                          if (cleaned.isNotEmpty) _nameCtrl.text = cleaned;
                        },
                      ),
                  onApply:
                      () => _sendCmd(
                        'set name ${_nameCtrl.text.trim()}',
                        l10n.repeaterNodeName,
                      ),
                ),
                const Divider(height: 24),
                RepeaterConfigRow(
                  label: l10n.repeaterTxPower,
                  controller: _txPowerCtrl,
                  hint: '1–30',
                  suffix: 'dBm',
                  keyboardType: TextInputType.number,
                  enabled: !_pendingCommand,
                  loading: _loadingFields.contains('tx'),
                  showRefresh: true,
                  onRefresh:
                      () => _refreshField(
                        fieldKey: 'tx',
                        command: 'get tx',
                        onResult: (raw) {
                          final v = _parseIntResponse(raw);
                          if (v != null) _txPowerCtrl.text = v;
                        },
                      ),
                  onApply:
                      () => _sendCmd(
                        'set tx ${_txPowerCtrl.text.trim()}',
                        l10n.repeaterTxPower,
                      ),
                ),
                const Divider(height: 24),
                RepeaterConfigRow(
                  label: l10n.repeaterAdvertZeroHop,
                  sublabel: l10n.repeaterIntervalMinutes,
                  controller: _advertZeroHopCtrl,
                  hint: '60–240',
                  keyboardType: TextInputType.number,
                  enabled: !_pendingCommand,
                  loading: _loadingFields.contains('zerohop'),
                  showRefresh: true,
                  onRefresh:
                      () => _refreshField(
                        fieldKey: 'zerohop',
                        command: 'get advert.interval',
                        onResult: (raw) {
                          final v = _parseIntResponse(raw);
                          if (v != null) _advertZeroHopCtrl.text = v;
                        },
                      ),
                  onApply:
                      () => _sendCmd(
                        'set advert.interval ${_advertZeroHopCtrl.text.trim()}',
                        l10n.repeaterAdvertZeroHop,
                      ),
                ),
                const Divider(height: 24),
                RepeaterConfigRow(
                  label: l10n.repeaterAdvertFlood,
                  sublabel: l10n.repeaterIntervalHours,
                  controller: _advertFloodCtrl,
                  hint: '3–168',
                  keyboardType: TextInputType.number,
                  enabled: !_pendingCommand,
                  loading: _loadingFields.contains('flood'),
                  showRefresh: true,
                  onRefresh:
                      () => _refreshField(
                        fieldKey: 'flood',
                        command: 'get flood.advert.interval',
                        onResult: (raw) {
                          final v = _parseIntResponse(raw);
                          if (v != null) _advertFloodCtrl.text = v;
                        },
                      ),
                  onApply:
                      () => _sendCmd(
                        'set flood.advert.interval ${_advertFloodCtrl.text.trim()}',
                        l10n.repeaterAdvertFlood,
                      ),
                ),
                const Divider(height: 24),
                RepeaterConfigRow(
                  label: l10n.repeaterFloodMax,
                  controller: _floodMaxCtrl,
                  hint: '0–64',
                  keyboardType: TextInputType.number,
                  enabled: !_pendingCommand,
                  loading: _loadingFields.contains('floodmax'),
                  showRefresh: true,
                  onRefresh:
                      () => _refreshField(
                        fieldKey: 'floodmax',
                        command: 'get flood.max',
                        onResult: (raw) {
                          final v = _parseIntResponse(raw);
                          if (v != null) _floodMaxCtrl.text = v;
                        },
                      ),
                  onApply:
                      () => _sendCmd(
                        'set flood.max ${_floodMaxCtrl.text.trim()}',
                        l10n.repeaterFloodMax,
                      ),
                ),
                const Divider(height: 24),
                _buildRepeatToggleRow(l10n, theme),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        RepeaterSectionHeader(title: l10n.contactsRemoteActions),
        const SizedBox(height: 8),
        Card(child: Column(children: _buildActionTiles(l10n))),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildRepeatToggleRow(AppLocalizations l10n, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.repeaterForwarding,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                l10n.repeaterForwardingDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: l10n.repeaterFetchStats,
          icon:
              _loadingFields.contains('repeat')
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.refresh, size: 20),
          onPressed:
              _pendingCommand
                  ? null
                  : () => _refreshField(
                    fieldKey: 'repeat',
                    command: 'get repeat',
                    onResult: (raw) {
                      final r = _stripPrompt(raw ?? '').toLowerCase();
                      if (r == 'on') {
                        _repeatEnabled = true;
                      } else if (r == 'off') {
                        _repeatEnabled = false;
                      }
                    },
                  ),
        ),
        _repeatEnabled == true
            ? const FilledButton(onPressed: null, child: Text('ON'))
            : OutlinedButton(
              onPressed:
                  _pendingCommand
                      ? null
                      : () async {
                        setState(() => _repeatEnabled = true);
                        await _sendCmd(
                          'set repeat on',
                          l10n.repeaterForwarding,
                        );
                      },
              child: const Text('ON'),
            ),
        const SizedBox(width: 4),
        _repeatEnabled == false
            ? const FilledButton(onPressed: null, child: Text('OFF'))
            : OutlinedButton(
              onPressed:
                  _pendingCommand
                      ? null
                      : () async {
                        setState(() => _repeatEnabled = false);
                        await _sendCmd(
                          'set repeat off',
                          l10n.repeaterForwarding,
                        );
                      },
              child: const Text('OFF'),
            ),
      ],
    );
  }

  List<Widget> _buildActionTiles(AppLocalizations l10n) => [
    RepeaterActionTile(
      icon: Icons.broadcast_on_home,
      title: l10n.contactsFloodAdvert,
      subtitle: l10n.contactsFloodAdvertDesc,
      enabled: !_pendingCommand,
      onTap: () => _sendCmd('advert', l10n.contactsFloodAdvert),
    ),
    RepeaterActionTile(
      icon: Icons.wifi_tethering,
      title: l10n.contactsZeroHopAdvert,
      subtitle: l10n.contactsZeroHopAdvertDesc,
      enabled: !_pendingCommand,
      onTap: () => _sendCmd('advert.zerohop', l10n.contactsZeroHopAdvert),
    ),
    RepeaterActionTile(
      icon: Icons.schedule,
      title: l10n.contactsSyncClock,
      subtitle: l10n.contactsSyncClockDesc,
      enabled: !_pendingCommand,
      onTap: () => _sendCmd('clock sync', l10n.contactsSyncClock),
    ),
    RepeaterActionTile(
      icon: Icons.bar_chart,
      title: l10n.repeaterClearStats,
      subtitle: l10n.repeaterClearStatsDesc,
      enabled: !_pendingCommand,
      onTap: () => _sendCmd('clear stats', l10n.repeaterClearStats),
    ),
    RepeaterActionTile(
      icon: Icons.system_update_alt,
      title: l10n.contactsStartOTA,
      subtitle: l10n.contactsStartOTADesc,
      enabled: !_pendingCommand,
      onTap: _confirmAndStartOta,
    ),
  ];

  Future<void> _confirmAndStartOta() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l10n.contactsConfirmOTATitle),
            content: Text(
              '${l10n.contactsConfirmOTAContent}\n\n'
              '${l10n.contactsConfirmOTAQuestion}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                child: Text(l10n.contactsStartOTA),
              ),
            ],
          ),
    );
    if (ok == true) {
      await _sendCmd('start ota', l10n.contactsStartOTA);
    }
  }
}

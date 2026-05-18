import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// A repeater CLI command paired with a short, human-readable description.
/// Tokens mirror the parser in MeshCore's `CommonCLI.cpp`. CLI verbs stay
/// in English (they are literal commands sent to the firmware); descriptions
/// are also kept in English to keep this catalogue concise and avoid an
/// explosion of l10n keys.
class _Cmd {
  const _Cmd(this.name, this.desc);
  final String name;
  final String desc;
}

const List<_Cmd> _kCommands = <_Cmd>[
  _Cmd('advert', 'Sends a flood advert from the repeater.'),
  _Cmd('advert.zerohop', 'Sends a zero-hop (local) advert from the repeater.'),
  _Cmd('clear stats', 'Clears the stats for this repeater.'),
  _Cmd('clock', 'Gets the current date and time on the repeater.'),
  _Cmd(
    'clock sync',
    'Sets the repeater clock from the device sending the command.',
  ),
  _Cmd('erase', 'Erases the repeater filesystem (admin only).'),
  _Cmd(
    'get advert.interval',
    'Get the local (zero-hop) automatic advert interval (minutes).',
  ),
  _Cmd('get af', 'Get the airtime factor.'),
  _Cmd('get agc.reset.interval', 'Get the AGC reset interval (seconds).'),
  _Cmd('get allow.read.only', 'Get whether read-only access is allowed.'),
  _Cmd('get direct.txdelay', 'Get the direct TX delay factor.'),
  _Cmd('get flood.advert.interval', 'Get the flood advert interval (hours).'),
  _Cmd('get flood.max', 'Get the maximum flood hop count.'),
  _Cmd('get freq', 'Get the radio frequency (MHz).'),
  _Cmd('get guest.password', 'Get the guest password.'),
  _Cmd('get int.thresh', 'Get the interference threshold.'),
  _Cmd('get lat', 'Get the configured latitude.'),
  _Cmd('get lon', 'Get the configured longitude.'),
  _Cmd(
    'get loop.detect',
    'Get the loop-detect mode (off / minimal / moderate / strict).',
  ),
  _Cmd('get multi.acks', 'Get the number of multi-ACKs.'),
  _Cmd('get name', 'Get the repeater node name.'),
  _Cmd('get owner.info', 'Get the owner info string.'),
  _Cmd('get path.hash.mode', 'Get the path hash mode.'),
  _Cmd('get public.key', 'Get the repeater public key.'),
  _Cmd(
    'get radio',
    'Get the radio parameters (freq, bandwidth, SF, coding rate).',
  ),
  _Cmd('get radio.rxgain', 'Get the boosted RX gain state (SX1262/SX1268).'),
  _Cmd('get repeat', 'Get whether forwarding (repeat) is enabled.'),
  _Cmd('get role', 'Get the firmware role string.'),
  _Cmd('get rxdelay', 'Get the RX delay base (seconds).'),
  _Cmd('get tx', 'Get the transmit power (dBm).'),
  _Cmd('get txdelay', 'Get the TX delay factor.'),
  _Cmd('neighbors', 'List known neighbours.'),
  _Cmd('neighbor.remove <pubkey>', 'Remove a neighbour by public-key prefix.'),
  _Cmd('password <new>', 'Change the admin password.'),
  _Cmd('reboot', 'Reboot the repeater.'),
  _Cmd(
    'set advert.interval <mins>',
    'Set the local advert interval (60–240 minutes).',
  ),
  _Cmd('set af <factor>', 'Set the airtime factor.'),
  _Cmd(
    'set agc.reset.interval <secs>',
    'Set the AGC reset interval (rounded to multiples of 4 s).',
  ),
  _Cmd('set allow.read.only <on|off>', 'Allow or block read-only access.'),
  _Cmd('set direct.txdelay <factor>', 'Set the direct TX delay factor.'),
  _Cmd(
    'set flood.advert.interval <hours>',
    'Set the flood advert interval (3–168 hours; 0 disables).',
  ),
  _Cmd('set flood.max <n>', 'Set the maximum flood hop count (0–64).'),
  _Cmd('set freq <MHz>', 'Set the radio frequency (reboot to apply).'),
  _Cmd('set guest.password <pwd>', 'Set the guest password.'),
  _Cmd('set int.thresh <n>', 'Set the interference threshold.'),
  _Cmd('set lat <deg>', 'Set the latitude.'),
  _Cmd('set lon <deg>', 'Set the longitude.'),
  _Cmd(
    'set loop.detect <off|minimal|moderate|strict>',
    'Set the loop-detect mode.',
  ),
  _Cmd('set multi.acks <n>', 'Set the number of multi-ACKs.'),
  _Cmd('set name <text>', 'Set the repeater node name.'),
  _Cmd(
    'set owner.info <text>',
    'Set the owner info (use | to separate lines).',
  ),
  _Cmd('set path.hash.mode <n>', 'Set the path hash mode.'),
  _Cmd(
    'set radio <freq,bw,sf,cr>',
    'Set radio parameters in one go (reboot to apply).',
  ),
  _Cmd('set radio.rxgain <on|off>', 'Toggle boosted RX gain (SX1262/SX1268).'),
  _Cmd('set repeat <on|off>', 'Enable or disable packet forwarding.'),
  _Cmd('set rxdelay <secs>', 'Set the RX delay base (≥ 0).'),
  _Cmd('set tx <dBm>', 'Set the transmit power.'),
  _Cmd('set txdelay <factor>', 'Set the TX delay factor (≥ 0).'),
  _Cmd('start ota', 'Start the OTA firmware update flow.'),
  _Cmd('time <epoch>', 'Set the clock to a UNIX epoch (seconds).'),
  _Cmd('ver', 'Get the firmware version.'),
];

/// Searchable, scrollable list of repeater CLI commands.
///
/// When [onPick] is provided, tapping a command pops the screen returning
/// the chosen command text (the parent can pre-fill its terminal input).
class RepeaterHelpScreen extends StatefulWidget {
  const RepeaterHelpScreen({super.key, this.onPick});

  final void Function(String command)? onPick;

  @override
  State<RepeaterHelpScreen> createState() => _RepeaterHelpScreenState();
}

class _RepeaterHelpScreenState extends State<RepeaterHelpScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final q = _query.trim().toLowerCase();
    final filtered =
        q.isEmpty
            ? _kCommands
            : _kCommands
                .where(
                  (c) =>
                      c.name.toLowerCase().contains(q) ||
                      c.desc.toLowerCase().contains(q),
                )
                .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.repeaterHelpTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.repeaterHelpSubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(180),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: theme.colorScheme.primary.withAlpha(40),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.repeaterHelpFirmwareNote,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.repeaterHelpSearchHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final cmd = filtered[i];
                return ListTile(
                  title: Text(
                    cmd.name,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  subtitle: Text(cmd.desc),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    if (widget.onPick != null) {
                      Navigator.of(context).pop(cmd.name);
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

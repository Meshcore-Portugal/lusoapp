import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/l10n.dart';
import '../../../protocol/models.dart';
import '../../../providers/radio_providers.dart';
import '../../widgets/path_sheet.dart';

// ─── layout & style constants ─────────────────────────────────────────────────
const double _kSelfR = 30.0;
const double _kMaxNodeR = 18.0;
const double _kMinNodeR = 5.0;
const double _kLabelW = 84.0;

/// Minimum (base) ring radius per hop bucket (0 = direct … 3 = flood/3+).
/// Actual radius grows beyond this when the bucket is dense.
const _kBaseRings = [170.0, 320.0, 470.0, 600.0];

/// Vertical gap between sub-rings within the same hop bucket.
const double _kSubRingGap = 70.0;

/// Maximum nodes packed onto a single sub-ring before spilling onto a new one.
/// (sub-ring radius keeps growing too, but we also stack to avoid one huge circle)
const int _kMaxNodesPerSubRing = 36;

/// Type ordering for in-ring grouping (companion → repeater → room → sensor → unknown)
const _kTypeOrder = [0x01, 0x02, 0x03, 0x04, 0x00];

/// Below this scale, node labels are auto-hidden (regardless of toggle).
const double _kLabelMinScale = 0.55;

const _kSelfColor = Color(0xFF6366F1);
const _kTypeColors = {
  0x01: Color(0xFF3B82F6), // chat     → blue
  0x02: Color(0xFFF97316), // repeater → orange
  0x03: Color(0xFFA855F7), // room     → purple
  0x04: Color(0xFF14B8A6), // sensor   → teal
};
const _kUnknownColor = Color(0xFF6B7280);

// ─── helpers ──────────────────────────────────────────────────────────────────

Color _edgeColor(double? snr, int hopCount) {
  if (snr != null) {
    if (snr >= 5) return const Color(0xFF22C55E);
    if (snr >= 0) return const Color(0xFFFACC15);
    return const Color(0xFFEF4444);
  }
  final alpha = switch (hopCount) {
    0 => 0.50,
    1 => 0.35,
    2 => 0.22,
    _ => 0.13,
  };
  return Colors.white.withValues(alpha: alpha);
}

String _fullKeyHex(List<int> key) =>
    key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// 64-char hex of the first 32 bytes of a contact's public key, matching the
/// keys stored in [radioContactsSnapshotProvider].
String _pubKeyHex(List<int> key) =>
    key.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String _relTime(int unixSeconds, AppLocalizations l10n) {
  if (unixSeconds == 0) return '—';
  final diff = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000),
  );
  if (diff.inSeconds < 60) return l10n.topologySecondsAgo(diff.inSeconds);
  if (diff.inMinutes < 60) return l10n.topologyMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.topologyHoursAgo(diff.inHours);
  if (diff.inDays < 7) return l10n.topologyDaysAgo(diff.inDays);
  return l10n.topologyWeeksAgo(diff.inDays ~/ 7);
}

IconData _typeIcon(int? type) => switch (type) {
  0x02 => Icons.cell_tower,
  0x03 => Icons.meeting_room_outlined,
  0x04 => Icons.sensors,
  _ => Icons.person_outline,
};

String _typeName(int type, AppLocalizations l10n) => switch (type) {
  0x01 => l10n.discoverTypeCompanion,
  0x02 => l10n.commonRepeater,
  0x03 => l10n.commonRoom,
  0x04 => l10n.commonSensor,
  _ => l10n.discoverTypeUnknown,
};

// ─── graph data classes ───────────────────────────────────────────────────────

class _Node {
  const _Node({
    required this.id,
    required this.label,
    required this.color,
    required this.isSelf,
    required this.x,
    required this.y,
    required this.pathLen,
    required this.radius,
    this.contact,
    this.ringRadius,
    this.ringAngle,
  });

  final String id;
  final String label;
  final Color color;
  final bool isSelf;
  final double x;
  final double y;
  final int pathLen;
  final double radius;
  final Contact? contact;

  /// Polar coordinates (only set for non-self nodes) so we can re-anchor
  /// once the canvas centre is known.
  final double? ringRadius;
  final double? ringAngle;

  _Node movedTo(double nx, double ny) => _Node(
    id: id,
    label: label,
    color: color,
    isSelf: isSelf,
    x: nx,
    y: ny,
    pathLen: pathLen,
    radius: radius,
    contact: contact,
    ringRadius: ringRadius,
    ringAngle: ringAngle,
  );
}

class _RingGuide {
  const _RingGuide({required this.radius, required this.hopBucket});
  final double radius;
  final int hopBucket;
}

class _Edge {
  const _Edge({
    required this.fromId,
    required this.toId,
    this.snr,
    this.hopCount = 0,
  });

  final String fromId;
  final String toId;
  final double? snr;
  final int hopCount;
}

// ─── graph builder ────────────────────────────────────────────────────────────

Contact? _findByHashHex(String hashHex, List<Contact> contacts) {
  if (hashHex.isEmpty || hashHex.length.isOdd) return null;
  final byteLen = hashHex.length ~/ 2;
  for (final c in contacts) {
    if (c.publicKey.length < byteLen) continue;
    var ok = true;
    for (int j = 0; j < byteLen; j++) {
      if (c.publicKey[j] !=
          int.parse(hashHex.substring(j * 2, j * 2 + 2), radix: 16)) {
        ok = false;
        break;
      }
    }
    if (ok) return c;
  }
  return null;
}

({
  Map<String, _Node> nodes,
  List<_Edge> edges,
  double canvas,
  int totalContacts,
  List<_RingGuide> rings,
})
_buildGraph(
  List<Contact> contacts,
  SelfInfo? selfInfo,
  List<TraceResult> history,
  String selfLabel, {
  bool radioOnly = false,
  Set<String> radioSnapshot = const {},
}) {
  final totalContacts = contacts.length;

  // Optional "only contacts stored on the radio" filter.
  // If the snapshot is empty (e.g. not yet synced), fall back to local list.
  final visible =
      (radioOnly && radioSnapshot.isNotEmpty)
          ? contacts
              .where((c) => radioSnapshot.contains(_pubKeyHex(c.publicKey)))
              .toList()
          : contacts;

  // Group contacts by hop bucket [0, 1, 2, 3+/flood]
  final groups = <int, List<Contact>>{};
  for (final c in visible) {
    final hops = c.pathLen == 0xFF ? 3 : (c.pathLen & 0x3F).clamp(0, 3);
    (groups[hops] ??= []).add(c);
  }

  // Sort each ring by type first (companion → repeater → room → sensor),
  // then by name within each type. This produces contiguous arcs of one
  // colour, dramatically reducing visual chaos.
  int typeRank(int t) {
    final i = _kTypeOrder.indexOf(t);
    return i < 0 ? _kTypeOrder.length : i;
  }

  for (final list in groups.values) {
    list.sort((a, b) {
      final r = typeRank(a.type).compareTo(typeRank(b.type));
      if (r != 0) return r;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
  }

  final nodes = <String, _Node>{};
  final seen = <String>{};
  final edges = <_Edge>[];
  final rings = <_RingGuide>[];
  double maxRing = _kBaseRings[0];

  // For each hop bucket, split into N sub-rings of ≤ _kMaxNodesPerSubRing nodes.
  // Each sub-ring gets its own radius (base + offset * gap) and node radius.
  final sortedBuckets = groups.keys.toList()..sort();
  for (final bucket in sortedBuckets) {
    final list = groups[bucket]!;
    final n = list.length;
    if (n == 0) continue;

    final subRingCount =
        ((n + _kMaxNodesPerSubRing - 1) ~/ _kMaxNodesPerSubRing).clamp(1, 8);
    final perSub = (n / subRingCount).ceil();
    final base = _kBaseRings[bucket.clamp(0, _kBaseRings.length - 1)];

    for (int sub = 0; sub < subRingCount; sub++) {
      final start = sub * perSub;
      final end = math.min(start + perSub, n);
      final slice = list.sublist(start, end);
      final m = slice.length;

      // Node radius shrinks with sub-ring density.
      final nodeR =
          (_kMaxNodeR * math.sqrt(20.0 / math.max(m, 1)))
              .clamp(_kMinNodeR, _kMaxNodeR)
              .toDouble();
      final spacing = nodeR * 2 + 5.0;
      final needed = (m * spacing) / (2 * math.pi);
      final r = math.max(base + sub * _kSubRingGap, needed);
      if (r > maxRing) maxRing = r;
      rings.add(_RingGuide(radius: r, hopBucket: bucket));

      // Place inside the slice (already type-sorted globally; stays sorted here)
      for (int i = 0; i < m; i++) {
        final c = slice[i];
        final angle = (2 * math.pi * i / m) - math.pi / 2;
        final id = c.shortId;
        // Skip if a previous sub-ring already placed a duplicate shortId.
        if (nodes.containsKey(id)) continue;
        nodes[id] = _Node(
          id: id,
          label: c.displayName,
          color: _kTypeColors[c.type] ?? _kUnknownColor,
          isSelf: false,
          x: 0, // patched below once we know the centre
          y: 0,
          pathLen: c.pathLen,
          radius: nodeR,
          contact: c,
          ringRadius: r,
          ringAngle: angle,
        );
        _addEdge(edges, seen, 'self', id, hopCount: bucket);
      }
    }
  }

  // Canvas grows with the largest ring so nothing clips.
  final canvas = (maxRing + _kMaxNodeR + 32) * 2;
  final cx = canvas / 2;
  final cy = canvas / 2;

  // Self at canvas centre
  nodes['self'] = _Node(
    id: 'self',
    label: selfInfo?.name ?? selfLabel,
    color: _kSelfColor,
    isSelf: true,
    x: cx,
    y: cy,
    pathLen: 0,
    radius: _kSelfR,
  );

  // Patch x/y now that we know the canvas centre.
  for (final entry in nodes.entries) {
    final node = entry.value;
    if (node.isSelf) continue;
    nodes[entry.key] = node.movedTo(
      cx + node.ringRadius! * math.cos(node.ringAngle!),
      cy + node.ringRadius! * math.sin(node.ringAngle!),
    );
  }

  // Overlay trace-derived inter-relay edges (only when both endpoints visible).
  for (final trace in history) {
    final hops = trace.hops;
    if (hops.isEmpty) continue;

    final c0 = _findByHashHex(hops[0].hashHex, contacts);
    if (c0 != null && nodes.containsKey(c0.shortId)) {
      _addEdge(edges, seen, 'self', c0.shortId, snr: hops[0].snrDb);
    }

    for (int i = 0; i + 1 < hops.length; i++) {
      final ci = _findByHashHex(hops[i].hashHex, contacts);
      final ci1 = _findByHashHex(hops[i + 1].hashHex, contacts);
      if (ci == null || ci1 == null) continue;
      if (!nodes.containsKey(ci.shortId) || !nodes.containsKey(ci1.shortId)) {
        continue;
      }
      _addEdge(edges, seen, ci.shortId, ci1.shortId, snr: hops[i + 1].snrDb);
    }
  }

  return (
    nodes: nodes,
    edges: edges,
    canvas: canvas,
    totalContacts: totalContacts,
    rings: rings,
  );
}

void _addEdge(
  List<_Edge> list,
  Set<String> seen,
  String a,
  String b, {
  double? snr,
  int hopCount = 0,
}) {
  final key = a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
  if (!seen.add(key)) return;
  list.add(_Edge(fromId: a, toId: b, snr: snr, hopCount: hopCount));
}

// ─── edge painter ─────────────────────────────────────────────────────────────

class _EdgePainter extends CustomPainter {
  const _EdgePainter({
    required this.nodes,
    required this.edges,
    required this.rings,
    required this.hopLabels,
  });

  final Map<String, _Node> nodes;
  final List<_Edge> edges;
  final List<_RingGuide> rings;

  /// Localized labels for each hop bucket (index 0..3).
  final List<String> hopLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // 1. Faint concentric ring guides + a once-per-bucket hop label.
    final ringPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.05)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke;
    final shownLabels = <int>{};
    for (final ring in rings) {
      canvas.drawCircle(Offset(cx, cy), ring.radius, ringPaint);
      if (shownLabels.add(ring.hopBucket)) {
        final label = hopLabels[ring.hopBucket.clamp(0, hopLabels.length - 1)];
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // Place label at top of ring with a small inset.
        tp.paint(
          canvas,
          Offset(cx - tp.width / 2, cy - ring.radius - tp.height - 2),
        );
      }
    }

    // 2. Edges over the guides.
    for (final e in edges) {
      final a = nodes[e.fromId];
      final b = nodes[e.toId];
      if (a == null || b == null) continue;
      canvas.drawLine(
        Offset(a.x, a.y),
        Offset(b.x, b.y),
        Paint()
          ..color = _edgeColor(e.snr, e.hopCount)
          ..strokeWidth = e.hopCount <= 0 ? 2.5 : (e.hopCount == 1 ? 2.0 : 1.5)
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.nodes != nodes ||
      old.edges != edges ||
      old.rings != rings ||
      old.hopLabels != hopLabels;
}

// ─── node widget ──────────────────────────────────────────────────────────────

class _NodeWidget extends StatelessWidget {
  const _NodeWidget({
    required this.node,
    required this.onTap,
    required this.showLabel,
  });

  final _Node node;
  final VoidCallback onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final r = node.radius;
    final sz = r * 2;
    return GestureDetector(
      onTap: node.isSelf ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: math.max(_kLabelW, sz),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: sz,
                height: sz,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: node.color,
                  boxShadow: [
                    BoxShadow(
                      color: node.color.withValues(
                        alpha: node.isSelf ? 0.45 : 0.30,
                      ),
                      blurRadius: node.isSelf ? 10 : 6,
                      spreadRadius: node.isSelf ? 2 : 1,
                    ),
                  ],
                  border:
                      node.isSelf
                          ? Border.all(color: Colors.white, width: 2.5)
                          : null,
                ),
                child:
                    r >= 12
                        ? Icon(
                          node.isSelf
                              ? Icons.radio
                              : _typeIcon(node.contact?.type),
                          color: Colors.white,
                          size: r * 0.85,
                        )
                        : null,
              ),
            ),
            if (showLabel || node.isSelf) ...[
              const SizedBox(height: 4),
              Text(
                node.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── shared empty state ───────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hub_outlined, color: Colors.white24, size: 64),
          const SizedBox(height: 16),
          Text(
            l10n.topologyEmptyTitle,
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.topologyEmptyHint,
            style: const TextStyle(color: Colors.white24, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── legend ───────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC0D1117),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LRow(color: _kSelfColor, dot: true, label: l10n.topologySelf),
          _LRow(
            color: const Color(0xFF3B82F6),
            dot: true,
            label: l10n.discoverTypeCompanion,
          ),
          _LRow(
            color: const Color(0xFFF97316),
            dot: true,
            label: l10n.commonRepeater,
          ),
          _LRow(
            color: const Color(0xFFA855F7),
            dot: true,
            label: l10n.commonRoom,
          ),
          _LRow(
            color: const Color(0xFF14B8A6),
            dot: true,
            label: l10n.commonSensor,
          ),
          const SizedBox(height: 5),
          _LRow(
            color: const Color(0xFF22C55E),
            dot: false,
            label: l10n.topologySnrGood,
          ),
          _LRow(
            color: const Color(0xFFFACC15),
            dot: false,
            label: l10n.topologySnrMid,
          ),
          _LRow(
            color: const Color(0xFFEF4444),
            dot: false,
            label: l10n.topologySnrBad,
          ),
        ],
      ),
    );
  }
}

class _LRow extends StatelessWidget {
  const _LRow({required this.color, required this.dot, required this.label});

  final Color color;
  final bool dot;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot
            ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            )
            : Container(width: 14, height: 2, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 10),
        ),
      ],
    ),
  );
}

// ─── graph tab ────────────────────────────────────────────────────────────────

class _GraphToolbar extends StatelessWidget {
  const _GraphToolbar({
    required this.radioOnly,
    required this.showLabels,
    required this.shown,
    required this.total,
    required this.onToggleRadioOnly,
    required this.onToggleLabels,
  });

  final bool radioOnly;
  final bool showLabels;
  final int shown;
  final int total;
  final VoidCallback onToggleRadioOnly;
  final VoidCallback onToggleLabels;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC0D1117),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            tooltip:
                radioOnly ? l10n.topologyFilterAll : l10n.topologyFilterRecent,
            icon: Icon(
              radioOnly ? Icons.radio : Icons.radio_outlined,
              color: radioOnly ? const Color(0xFFFACC15) : Colors.white60,
            ),
            onPressed: onToggleRadioOnly,
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            tooltip: l10n.topologyToggleLabels,
            icon: Icon(
              showLabels ? Icons.label : Icons.label_outline,
              color: showLabels ? const Color(0xFF22C55E) : Colors.white60,
            ),
            onPressed: onToggleLabels,
          ),
          const SizedBox(width: 6),
          Text(
            l10n.topologyNodesShown(shown, total),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _GraphTab extends ConsumerStatefulWidget {
  const _GraphTab();

  @override
  ConsumerState<_GraphTab> createState() => _GraphTabState();
}

class _GraphTabState extends ConsumerState<_GraphTab> {
  late final TransformationController _tx;
  double _fitScale = 0.38;
  double _lastCanvas = 0;
  Size? _lastViewport;

  // User toggles
  bool _radioOnly = true;
  bool _userLabels = false; // user explicit toggle (overlaid on auto rule)

  @override
  void initState() {
    super.initState();
    _tx = TransformationController();
  }

  void _fitTo(double canvas, Size viewport) {
    if (canvas <= 0 || viewport.isEmpty) return;
    final s = (math.min(viewport.width, viewport.height) * 0.92 / canvas).clamp(
      0.05,
      1.5,
    );
    _fitScale = s;
    final tx = (viewport.width - canvas * s) / 2;
    final ty = (viewport.height - canvas * s) / 2;
    _tx.value =
        Matrix4.identity()
          ..translateByDouble(tx, ty, 0.0, 1.0)
          ..scaleByDouble(s, s, 1.0, 1.0);
  }

  @override
  void dispose() {
    _tx.dispose();
    super.dispose();
  }

  void _resetView() {
    if (_lastViewport != null && _lastCanvas > 0) {
      _fitTo(_lastCanvas, _lastViewport!);
    } else {
      _tx.value =
          Matrix4.identity()..scaleByDouble(_fitScale, _fitScale, 1.0, 1.0);
    }
  }

  void _showContactSheet(BuildContext context, Contact c) {
    final keyHex = _fullKeyHex(c.publicKey);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (ctx) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (_kTypeColors[c.type] ?? _kUnknownColor)
                            .withValues(alpha: 0.2),
                      ),
                      child: Icon(
                        _typeIcon(c.type),
                        color: _kTypeColors[c.type] ?? _kUnknownColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _typeName(c.type, context.l10n),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _InfoRow(label: context.l10n.topologyLabelId, value: c.shortId),
                _InfoRow(
                  label: context.l10n.topologyLabelPath,
                  value: contactPathLabel(c.pathLen),
                ),
                _InfoRow(
                  label: context.l10n.topologyLabelSeen,
                  value: _relTime(c.lastAdvertTimestamp, context.l10n),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      context.push(
                        c.isRoom ? '/room/$keyHex' : '/chat/$keyHex',
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(context.l10n.commonSendMessage),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider);
    final selfInfo = ref.watch(selfInfoProvider);
    final traceHistory = ref.watch(traceHistoryProvider);
    final l10n = context.l10n;
    final radioSnapshot = ref.watch(radioContactsSnapshotProvider);

    if (contacts.isEmpty && selfInfo == null) return const _EmptyState();

    final graph = _buildGraph(
      contacts,
      selfInfo,
      traceHistory,
      l10n.topologySelf,
      radioOnly: _radioOnly,
      radioSnapshot: radioSnapshot,
    );
    final nodes = graph.nodes;
    final edges = graph.edges;
    final canvas = graph.canvas;
    final shownContacts = nodes.length - 1; // minus self
    final hopLabels = [
      l10n.topologyHopDirect,
      l10n.topologyHop1,
      l10n.topologyHop2,
      l10n.topologyHopFlood,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        // Re-fit when canvas size or viewport changes (e.g. filter toggled,
        // contacts added, orientation changed).
        if ((canvas - _lastCanvas).abs() > 0.5 ||
            _lastViewport == null ||
            (_lastViewport!.width - viewport.width).abs() > 0.5 ||
            (_lastViewport!.height - viewport.height).abs() > 0.5) {
          _lastCanvas = canvas;
          _lastViewport = viewport;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _fitTo(canvas, viewport);
          });
        }

        return Stack(
          children: [
            InteractiveViewer(
              constrained: false,
              transformationController: _tx,
              minScale: 0.05,
              maxScale: 4.0,
              boundaryMargin: const EdgeInsets.all(600),
              child: SizedBox(
                width: canvas,
                height: canvas,
                child: AnimatedBuilder(
                  animation: _tx,
                  builder: (context, _) {
                    final scale = _tx.value.getMaxScaleOnAxis();
                    final showLabels = _userLabels || scale >= _kLabelMinScale;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _EdgePainter(
                              nodes: nodes,
                              edges: edges,
                              rings: graph.rings,
                              hopLabels: hopLabels,
                            ),
                          ),
                        ),
                        for (final node in nodes.values)
                          Positioned(
                            left:
                                node.x -
                                math.max(_kLabelW, node.radius * 2) / 2,
                            top: node.y - node.radius,
                            child: _NodeWidget(
                              node: node,
                              showLabel: showLabels,
                              onTap: () {
                                if (node.contact != null) {
                                  _showContactSheet(context, node.contact!);
                                }
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            // Top-right legend
            const Positioned(top: 12, right: 12, child: _Legend()),
            // Top-left toolbar (filter + label toggle + counter)
            Positioned(
              top: 12,
              left: 12,
              child: _GraphToolbar(
                radioOnly: _radioOnly,
                showLabels: _userLabels,
                shown: shownContacts,
                total: graph.totalContacts,
                onToggleRadioOnly:
                    () => setState(() => _radioOnly = !_radioOnly),
                onToggleLabels:
                    () => setState(() => _userLabels = !_userLabels),
              ),
            ),
            // Reset/center FAB
            Positioned(
              bottom: 20,
              right: 20,
              child: FloatingActionButton.small(
                onPressed: _resetView,
                backgroundColor: const Color(0xFF1F2937),
                foregroundColor: Colors.white70,
                heroTag: 'topology_reset',
                tooltip: l10n.topologyResetView,
                child: const Icon(Icons.center_focus_strong),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── info row (used in contact sheet) ────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        Text(
          value,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    ),
  );
}

// ─── paths (trie) tab ─────────────────────────────────────────────────────────

/// Mutable trie node used to merge shared prefixes across all trace results.
class _TrieNode {
  _TrieNode({required this.hashHex, this.depth = 0, this.snr});

  final String hashHex; // '' for the synthetic root (= self)
  final int depth;
  final double? snr; // SNR of the link from parent → this hop
  final Map<String, _TrieNode> children = {};

  /// Set on the deepest node of a path: the resolved destination contact.
  Contact? contact;

  /// Layout slots filled during placement.
  int row = 0;
  double x = 0;
  double y = 0;
}

const double _kPathColW = 56.0; // width of one hop column
const double _kPathRowH = 38.0; // vertical pitch between leaves
const double _kPathDotR = 8.0;
const double _kPathLeafW = 76.0;
const double _kPathPadX = 24.0;
const double _kPathPadY = 24.0;

/// Build a single merged trie from all trace results.
_TrieNode _buildTrie(List<TraceResult> traces, List<Contact> contacts) {
  final root = _TrieNode(hashHex: '', depth: 0);

  for (final t in traces) {
    if (t.hops.isEmpty) continue;
    var cur = root;
    for (int i = 0; i < t.hops.length; i++) {
      final h = t.hops[i];
      final key = h.hashHex.toLowerCase();
      cur = cur.children.putIfAbsent(
        key,
        () => _TrieNode(hashHex: key, depth: i + 1, snr: h.snrDb),
      );
    }
    // Resolve leaf contact via last-hop hash; fall back to silent leaf.
    final last = t.hops.last;
    cur.contact ??= _findByHashHex(last.hashHex, contacts);
  }
  return root;
}

/// DFS leaf-order placement: assigns each leaf a unique row and propagates
/// internal nodes' row as the average of their children (top-aligned look).
int _layoutTrie(_TrieNode node, int nextRow) {
  if (node.children.isEmpty) {
    node.row = nextRow;
    node.x = _kPathPadX + node.depth * _kPathColW;
    node.y = _kPathPadY + nextRow * _kPathRowH;
    return nextRow + 1;
  }
  // Stable order: by hashHex ascending so the layout doesn't reshuffle.
  final keys = node.children.keys.toList()..sort();
  final firstRow = nextRow;
  for (final k in keys) {
    nextRow = _layoutTrie(node.children[k]!, nextRow);
  }
  final lastRow = nextRow - 1;
  node.row = ((firstRow + lastRow) / 2).floor();
  node.x = _kPathPadX + node.depth * _kPathColW;
  node.y = _kPathPadY + node.row * _kPathRowH;
  return nextRow;
}

/// Flatten trie into list of (parent, child) pairs for connector drawing.
void _collectEdges(_TrieNode node, List<({_TrieNode from, _TrieNode to})> out) {
  for (final c in node.children.values) {
    out.add((from: node, to: c));
    _collectEdges(c, out);
  }
}

void _collectNodes(_TrieNode node, List<_TrieNode> out) {
  out.add(node);
  for (final c in node.children.values) {
    _collectNodes(c, out);
  }
}

class _PathsPainter extends CustomPainter {
  const _PathsPainter({required this.edges});

  final List<({_TrieNode from, _TrieNode to})> edges;

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in edges) {
      final a = Offset(e.from.x, e.from.y);
      final b = Offset(e.to.x, e.to.y);
      final paint =
          Paint()
            ..color = _edgeColor(e.to.snr, e.from.depth)
            ..strokeWidth = 1.8
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round;
      // Elbow connector: horizontal first, then vertical to child.
      final mid = Offset(b.dx - _kPathColW * 0.45, a.dy);
      final path =
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(mid.dx, mid.dy)
            ..quadraticBezierTo(b.dx, a.dy, b.dx, b.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_PathsPainter old) => old.edges != edges;
}

class _PathsTab extends ConsumerWidget {
  const _PathsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traces = ref.watch(traceHistoryProvider);
    final contacts = ref.watch(contactsProvider);
    final l10n = context.l10n;

    if (traces.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_tree_outlined,
              color: Colors.white24,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.topologyPathsEmptyTitle,
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.topologyPathsEmptyHint,
              style: const TextStyle(color: Colors.white24, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final root = _buildTrie(traces, contacts);
    final totalLeaves = _layoutTrie(root, 0);
    final allNodes = <_TrieNode>[];
    _collectNodes(root, allNodes);
    final edges = <({_TrieNode from, _TrieNode to})>[];
    _collectEdges(root, edges);

    // Compute canvas size from deepest node + leaf count.
    int maxDepth = 0;
    for (final n in allNodes) {
      if (n.depth > maxDepth) maxDepth = n.depth;
    }
    final canvasW = _kPathPadX * 2 + (maxDepth + 1) * _kPathColW + _kPathLeafW;
    final canvasH = _kPathPadY * 2 + totalLeaves * _kPathRowH;

    return Stack(
      children: [
        Positioned(
          top: 8,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xCC0D1117),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              l10n.topologyPathsCount(traces.length),
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 32),
          child: InteractiveViewer(
            constrained: false,
            minScale: 0.4,
            maxScale: 3.0,
            boundaryMargin: const EdgeInsets.all(80),
            child: SizedBox(
              width: canvasW,
              height: canvasH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _PathsPainter(edges: edges)),
                  ),
                  for (final n in allNodes) _PathsTrieNode(node: n),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PathsTrieNode extends StatelessWidget {
  const _PathsTrieNode({required this.node});
  final _TrieNode node;

  @override
  Widget build(BuildContext context) {
    final isRoot = node.depth == 0;
    final isLeaf = node.children.isEmpty && node.contact != null;
    final color =
        isLeaf
            ? (_kTypeColors[node.contact!.type] ?? _kUnknownColor)
            : (isRoot ? _kSelfColor : Colors.white60);

    final dot = Container(
      width: _kPathDotR * 2,
      height: _kPathDotR * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 4,
            spreadRadius: 0.5,
          ),
        ],
      ),
    );

    Widget content;
    if (isLeaf) {
      // Leaf badge: coloured pill with contact short name, like the screenshot.
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot,
          const SizedBox(width: 4),
          Container(
            constraints: const BoxConstraints(maxWidth: _kPathLeafW),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Text(
              node.contact!.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      );
    } else {
      // Hop or root: dot + monospace hash byte under it.
      final label = isRoot ? '●' : node.hashHex;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot,
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 10,
              fontFamily: 'monospace',
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }

    // Anchor: dot centre = (node.x, node.y); leaf row keeps dot at left.
    return Positioned(
      left: isLeaf ? node.x - _kPathDotR : node.x - 30,
      top: node.y - _kPathDotR,
      child: SizedBox(
        width: isLeaf ? (_kPathDotR * 2 + 4 + _kPathLeafW + 6) : 60,
        child: isLeaf ? content : Center(child: content),
      ),
    );
  }
}

// ─── timeline tab ─────────────────────────────────────────────────────────────

class _TimelineTab extends ConsumerWidget {
  const _TimelineTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);
    if (contacts.isEmpty) return const _EmptyState();
    final l10n = context.l10n;

    final sorted = [...contacts]
      ..sort((a, b) => b.lastAdvertTimestamp.compareTo(a.lastAdvertTimestamp));

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      itemCount: sorted.length,
      separatorBuilder:
          (_, __) =>
              const Divider(color: Color(0xFF1F2937), height: 1, indent: 52),
      itemBuilder: (_, i) {
        final c = sorted[i];
        final color = _kTypeColors[c.type] ?? _kUnknownColor;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            vertical: 4,
            horizontal: 4,
          ),
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(_typeIcon(c.type), color: color, size: 20),
          ),
          title: Text(
            c.displayName,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: Text(
            '${_typeName(c.type, l10n)} · ${contactPathLabel(c.pathLen)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: Text(
            _relTime(c.lastAdvertTimestamp, l10n),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        );
      },
    );
  }
}

// ─── screen ───────────────────────────────────────────────────────────────────

/// Mesh topology viewer.
///
/// **Grafo tab** — interactive pan/zoom graph showing all radio contacts as
/// nodes arranged in concentric rings by hop distance.  Edges are coloured
/// by SNR (from accumulated trace results) or dimmed by hop count when no
/// trace data is available.  Tap a node to open a contact detail sheet.
///
/// **Cronologia tab** — contacts sorted by last-heard timestamp, showing
/// node type and path length at a glance.
class TopologyScreen extends ConsumerWidget {
  const TopologyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D1117),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(context.l10n.topologyScreenTitle),
          bottom: TabBar(
            tabs: [
              Tab(
                icon: const Icon(Icons.hub_outlined),
                text: context.l10n.topologyTabGraph,
              ),
              Tab(
                icon: const Icon(Icons.account_tree_outlined),
                text: context.l10n.topologyTabPaths,
              ),
              Tab(
                icon: const Icon(Icons.access_time),
                text: context.l10n.topologyTabTimeline,
              ),
            ],
          ),
        ),
        body: const TabBarView(
          // Disable swipe to avoid conflicting with graph pan gestures.
          physics: NeverScrollableScrollPhysics(),
          children: [_GraphTab(), _PathsTab(), _TimelineTab()],
        ),
      ),
    );
  }
}

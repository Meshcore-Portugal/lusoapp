import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/l10n.dart';
import '../../../protocol/models.dart';
import '../../../providers/radio_providers.dart';
import '../../widgets/path_sheet.dart';

// ─── layout & style constants ─────────────────────────────────────────────────
const double _kCanvas = 900.0;
const double _kNodeR = 22.0;
const double _kSelfR = 30.0;
const double _kLabelW = 84.0;

/// Ring radius for each hop bucket: 0 = direct, 1 = 1 hop, 2 = 2 hops, 3 = flood/3+.
const _kRings = [175.0, 285.0, 370.0, 440.0];

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
    this.contact,
  });

  final String id;
  final String label;
  final Color color;
  final bool isSelf;
  final double x;
  final double y;
  final int pathLen;
  final Contact? contact;
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

({Map<String, _Node> nodes, List<_Edge> edges}) _buildGraph(
  List<Contact> contacts,
  SelfInfo? selfInfo,
  List<TraceResult> history,
  String selfLabel,
) {
  final nodes = <String, _Node>{};
  final seen = <String>{};
  final edges = <_Edge>[];

  // Self at canvas centre
  nodes['self'] = _Node(
    id: 'self',
    label: selfInfo?.name ?? selfLabel,
    color: _kSelfColor,
    isSelf: true,
    x: _kCanvas / 2,
    y: _kCanvas / 2,
    pathLen: 0,
  );

  // Group contacts by hop bucket [0, 1, 2, 3+/flood]
  final groups = <int, List<Contact>>{};
  for (final c in contacts) {
    final hops = c.pathLen == 0xFF ? 3 : (c.pathLen & 0x3F).clamp(0, 3);
    (groups[hops] ??= []).add(c);
  }

  for (final entry in groups.entries) {
    final bucket = entry.key;
    final list = entry.value;
    final radius = _kRings[bucket];
    for (int i = 0; i < list.length; i++) {
      final c = list[i];
      final angle = (2 * math.pi * i / list.length) - math.pi / 2;
      final id = c.shortId;
      nodes[id] = _Node(
        id: id,
        label: c.displayName,
        color: _kTypeColors[c.type] ?? _kUnknownColor,
        isSelf: false,
        x: _kCanvas / 2 + radius * math.cos(angle),
        y: _kCanvas / 2 + radius * math.sin(angle),
        pathLen: c.pathLen,
        contact: c,
      );
      _addEdge(edges, seen, 'self', id, hopCount: bucket);
    }
  }

  // Overlay trace-derived inter-relay edges
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
      if (!nodes.containsKey(ci.shortId) || !nodes.containsKey(ci1.shortId))
        continue;
      _addEdge(edges, seen, ci.shortId, ci1.shortId, snr: hops[i + 1].snrDb);
    }
  }

  return (nodes: nodes, edges: edges);
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
  const _EdgePainter({required this.nodes, required this.edges});

  final Map<String, _Node> nodes;
  final List<_Edge> edges;

  @override
  void paint(Canvas canvas, Size size) {
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
      old.nodes != nodes || old.edges != edges;
}

// ─── node widget ──────────────────────────────────────────────────────────────

class _NodeWidget extends StatelessWidget {
  const _NodeWidget({required this.node, required this.onTap});

  final _Node node;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = node.isSelf ? _kSelfR : _kNodeR;
    final sz = r * 2;
    return GestureDetector(
      onTap: node.isSelf ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _kLabelW,
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
                      color: node.color.withValues(alpha: 0.45),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                  border:
                      node.isSelf
                          ? Border.all(color: Colors.white, width: 2.5)
                          : null,
                ),
                child: Icon(
                  node.isSelf ? Icons.radio : _typeIcon(node.contact?.type),
                  color: Colors.white,
                  size: r * 0.85,
                ),
              ),
            ),
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

class _GraphTab extends ConsumerStatefulWidget {
  const _GraphTab();

  @override
  ConsumerState<_GraphTab> createState() => _GraphTabState();
}

class _GraphTabState extends ConsumerState<_GraphTab> {
  late final TransformationController _tx;
  double _fitScale = 0.38;

  @override
  void initState() {
    super.initState();
    _tx = TransformationController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final w = MediaQuery.of(context).size.width;
      _fitScale = (w * 0.9 / _kCanvas).clamp(0.15, 1.0);
      _tx.value =
          Matrix4.identity()..scaleByDouble(_fitScale, _fitScale, 1.0, 1.0);
    });
  }

  @override
  void dispose() {
    _tx.dispose();
    super.dispose();
  }

  void _resetView() =>
      _tx.value =
          Matrix4.identity()..scaleByDouble(_fitScale, _fitScale, 1.0, 1.0);

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

    if (contacts.isEmpty && selfInfo == null) return const _EmptyState();

    final (:nodes, :edges) = _buildGraph(
      contacts,
      selfInfo,
      traceHistory,
      context.l10n.topologySelf,
    );

    return Stack(
      children: [
        InteractiveViewer(
          constrained: false,
          transformationController: _tx,
          minScale: 0.15,
          maxScale: 4.0,
          boundaryMargin: const EdgeInsets.all(400),
          child: SizedBox(
            width: _kCanvas,
            height: _kCanvas,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _EdgePainter(nodes: nodes, edges: edges),
                  ),
                ),
                for (final node in nodes.values)
                  Positioned(
                    left: node.x - _kLabelW / 2,
                    top: node.y - (node.isSelf ? _kSelfR : _kNodeR),
                    child: _NodeWidget(
                      node: node,
                      onTap: () {
                        if (node.contact != null) {
                          _showContactSheet(context, node.contact!);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton.small(
            onPressed: _resetView,
            backgroundColor: const Color(0xFF1F2937),
            foregroundColor: Colors.white70,
            heroTag: 'topology_reset',
            tooltip: context.l10n.topologyResetView,
            child: const Icon(Icons.center_focus_strong),
          ),
        ),
        const Positioned(top: 12, right: 12, child: _Legend()),
      ],
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
      length: 2,
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
                icon: const Icon(Icons.access_time),
                text: context.l10n.topologyTabTimeline,
              ),
            ],
          ),
        ),
        body: const TabBarView(
          // Disable swipe to avoid conflicting with graph pan gestures.
          physics: NeverScrollableScrollPhysics(),
          children: [_GraphTab(), _TimelineTab()],
        ),
      ),
    );
  }
}

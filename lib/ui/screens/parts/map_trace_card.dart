part of '../map_screen.dart';

class _TraceResultCard extends StatefulWidget {
  const _TraceResultCard({
    required this.result,
    required this.onClear,
    required this.onFit,
    required this.theme,
    this.selfPos,
  });

  final TraceResult result;
  final VoidCallback onClear;
  final VoidCallback onFit;
  final ThemeData theme;
  final LatLng? selfPos;

  @override
  State<_TraceResultCard> createState() => _TraceResultCardState();
}

class _TraceResultCardState extends State<_TraceResultCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ts =
        '${widget.result.timestamp.hour.toString().padLeft(2, '0')}:'
        '${widget.result.timestamp.minute.toString().padLeft(2, '0')}:'
        '${widget.result.timestamp.second.toString().padLeft(2, '0')}';

    const collapsedVisibleHops = 4;
    final totalHops = widget.result.hops.length;
    final canCollapse = totalHops > collapsedVisibleHops;
    final visibleHops =
        (_expanded || !canCollapse) ? totalHops : collapsedVisibleHops;
    final hiddenCount = totalHops - visibleHops;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row
            Row(
              children: [
                Icon(
                  Icons.route,
                  size: 16,
                  color: widget.theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Path · $ts · ${widget.result.hopCount} hop${widget.result.hopCount != 1 ? 's' : ''}',
                    style: widget.theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: widget.theme.colorScheme.primary,
                    ),
                  ),
                ),
                InkWell(
                  onTap: widget.onFit,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.fit_screen,
                      size: 16,
                      color: widget.theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                InkWell(
                  onTap: widget.onClear,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: widget.theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            // Hop list
            if (widget.result.hops.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (int i = 0; i < visibleHops; i++)
                Builder(
                  builder: (ctx) {
                    final hop = widget.result.hops[i];
                    // Distance from the previous GPS point (or selfPos) to this hop.
                    double? distM;
                    if (hop.hasGps) {
                      LatLng? prevPt;
                      if (i == 0) {
                        prevPt = widget.selfPos;
                      } else {
                        for (int k = i - 1; k >= 0; k--) {
                          final prev = widget.result.hops[k];
                          if (prev.hasGps) {
                            prevPt = LatLng(prev.latitude!, prev.longitude!);
                            break;
                          }
                        }
                      }
                      if (prevPt != null) {
                        distM = const Distance().as(
                          LengthUnit.Meter,
                          prevPt,
                          LatLng(hop.latitude!, hop.longitude!),
                        );
                      }
                    }
                    return _HopRow(
                      index: i + 1,
                      hop: hop,
                      theme: widget.theme,
                      distanceM: distM,
                    );
                  },
                ),
              if (canCollapse)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                    ),
                    label: Text(
                      _expanded
                          ? context.l10n.mapMinimizeList
                          : '${context.l10n.mapShowMore}$hiddenCount hop${hiddenCount == 1 ? '' : 's'}',
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 2,
                      ),
                    ),
                  ),
                ),
            ],
            // Final SNR
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_downward,
                    size: 12,
                    color: Colors.green.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${context.l10n.mapFinal} ${widget.result.finalSnrDb.toStringAsFixed(1)} dB',
                    style: widget.theme.textTheme.labelSmall?.copyWith(
                      color: Colors.green.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HopRow extends StatelessWidget {
  const _HopRow({
    required this.index,
    required this.hop,
    required this.theme,
    this.distanceM,
  });

  final int index;
  final TraceHop hop;
  final ThemeData theme;
  final double? distanceM;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Text(
              '$index.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Icon(
            hop.hasGps ? Icons.location_on : Icons.location_off,
            size: 12,
            color:
                hop.hasGps
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              hop.name ?? hop.hashHex,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: hop.name == null ? 'monospace' : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (distanceM != null) ...[
            Text(
              _formatDist(distanceM!),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            '${hop.snrDb.toStringAsFixed(1)} dB',
            style: theme.textTheme.labelSmall?.copyWith(
              color: _snrColor(hop.snrDb),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _snrColor(double snr) {
    if (snr > 5) return Colors.green.shade600;
    if (snr > 0) return Colors.orange.shade700;
    return Colors.red.shade600;
  }
}

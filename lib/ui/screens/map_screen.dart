import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../protocol/models.dart';
import '../../providers/radio_providers.dart';

/// Full-screen map showing all contacts with GPS coordinates and the device's
/// own position.  Uses OpenStreetMap tiles via flutter_map (no API key needed).
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = MapController();
  late final TileProvider _tileProvider =
      kIsWeb
          ? NetworkTileProvider()
          : FMTCTileProvider(
            stores: const {'mapStore': BrowseStoreStrategy.readUpdateCreate},
          );

  LatLng? _myLocation;
  bool _loadingLocation = false;
  double _currentZoom = 10.0;
  StreamSubscription<MapEvent>? _mapSub;

  /// Default centre — Portugal
  static const _defaultCenter = LatLng(39.5, -8.0);
  static const _defaultZoom = 6.0;
  static const _detailZoom = 11.0;

  @override
  void dispose() {
    _mapSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onMapReady() {
    _mapSub = _mapController.mapEventStream.listen((event) {
      if (mounted) setState(() => _currentZoom = _mapController.camera.zoom);
    });
  }

  // ---------------------------------------------------------------------------
  // Clustering
  // ---------------------------------------------------------------------------

  /// Minimum geographic distance (degrees) to keep two markers in the same
  /// cluster at the current zoom level.  Roughly 50 screen pixels.
  double _thresholdDeg(double zoom) => 35.15 / math.pow(2, zoom);

  /// Groups [contacts] into clusters based on geographic proximity at the
  /// current zoom level.  Uses a greedy single-pass algorithm: the first
  /// unassigned contact becomes the seed of a new cluster; every subsequent
  /// contact within threshold distance of that seed joins it.
  List<_ContactCluster> _computeClusters(List<Contact> contacts) {
    if (contacts.isEmpty) return [];
    final threshold = _thresholdDeg(_currentZoom);
    final clusters = <_ContactCluster>[];
    final assigned = <int>{};

    for (var i = 0; i < contacts.length; i++) {
      if (assigned.contains(i)) continue;
      final seed = contacts[i];
      final members = [seed];
      assigned.add(i);

      for (var j = i + 1; j < contacts.length; j++) {
        if (assigned.contains(j)) continue;
        final other = contacts[j];
        final dlat = (seed.latitude! - other.latitude!).abs();
        final dlng = (seed.longitude! - other.longitude!).abs();
        if (dlat < threshold && dlng < threshold) {
          members.add(other);
          assigned.add(j);
        }
      }

      final lat =
          members.map((m) => m.latitude!).reduce((a, b) => a + b) /
          members.length;
      final lng =
          members.map((m) => m.longitude!).reduce((a, b) => a + b) /
          members.length;
      clusters.add(_ContactCluster(members: members, center: LatLng(lat, lng)));
    }
    return clusters;
  }

  // ---------------------------------------------------------------------------
  // GPS helpers
  // ---------------------------------------------------------------------------

  /// Returns true only when coordinates represent a real GPS fix.
  /// Rejects null values and the [0, 0] sentinel used when no fix is available.
  static bool _isValidGps(double? lat, double? lng) =>
      lat != null && lng != null && !(lat == 0.0 && lng == 0.0);

  /// True on platforms where Geolocator works.
  bool get _locationSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _locateMe() async {
    if (!_locationSupported) return;
    setState(() => _loadingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('Servico de localizacao desactivado');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnack('Permissao de localizacao negada');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showSnack('Permissao de localizacao negada permanentemente');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      final pt = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() => _myLocation = pt);
        _mapController.move(pt, _detailZoom);
      }
    } catch (_) {
      _showSnack('Erro ao obter localizacao GPS');
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  void _fitAll(List<LatLng> points) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, _detailZoom);
      return;
    }
    final minLat = points.map((p) => p.latitude).reduce(math.min);
    final maxLat = points.map((p) => p.latitude).reduce(math.max);
    final minLng = points.map((p) => p.longitude).reduce(math.min);
    final maxLng = points.map((p) => p.longitude).reduce(math.max);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
        padding: const EdgeInsets.all(52),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider);
    final selfInfo = ref.watch(selfInfoProvider);
    final traceResult = ref.watch(traceResultProvider);
    final theme = Theme.of(context);

    final gpsContacts =
        contacts.where((c) => _isValidGps(c.latitude, c.longitude)).toList();

    // Prefer GPS from radio self-info; fall back to device GPS.
    // Treat [0, 0] as "no fix" — do not snap the map to null-island.
    final radio = selfInfo;
    final selfPos =
        (radio != null && _isValidGps(radio.latitude, radio.longitude))
            ? LatLng(radio.latitude!, radio.longitude!)
            : _myLocation;

    final allPoints = [
      ...gpsContacts.map((c) => LatLng(c.latitude!, c.longitude!)),
      if (selfPos != null) selfPos,
    ];

    final hasAny = allPoints.isNotEmpty;

    final initialCenter =
        selfPos ??
        (gpsContacts.isNotEmpty
            ? LatLng(gpsContacts.first.latitude!, gpsContacts.first.longitude!)
            : _defaultCenter);

    return Stack(
      children: [
        // ---- Main map ----
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: hasAny ? _detailZoom : _defaultZoom,
            interactionOptions: const InteractionOptions(
              flags:
                  InteractiveFlag.drag |
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.doubleTapZoom |
                  InteractiveFlag.scrollWheelZoom,
            ),
            onMapReady: _onMapReady,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'pt.meshcore.mcapppt',
              tileProvider: _tileProvider,
              // On web the browser sets its own User-Agent header;
              // a custom one would be blocked by CORS pre-flight.
            ),
            const RichAttributionWidget(
              showFlutterMapAttribution: false,
              attributions: [
                TextSourceAttribution('MeshCore Portugal'),
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
            // ---- Trace path polyline ----
            if (traceResult != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _tracePoints(traceResult, selfPos),
                    color: theme.colorScheme.primary,
                    strokeWidth: 3,
                    borderColor: theme.colorScheme.primaryContainer,
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
            // ---- Trace hop markers ----
            if (traceResult != null)
              MarkerLayer(
                markers: [
                  for (final hop in traceResult.hops)
                    if (hop.hasGps)
                      Marker(
                        point: LatLng(hop.latitude!, hop.longitude!),
                        width: 90,
                        height: 48,
                        alignment: Alignment.bottomCenter,
                        child: _buildHopMarker(hop, theme),
                      ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final cluster in _computeClusters(gpsContacts))
                  if (cluster.isSingle)
                    Marker(
                      point: cluster.center,
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => _showContactSheet(cluster.members.first),
                        child: _buildContactMarker(
                          cluster.members.first,
                          theme,
                        ),
                      ),
                    )
                  else
                    Marker(
                      point: cluster.center,
                      width: 52,
                      height: 52,
                      child: GestureDetector(
                        onTap: () => _onClusterTap(cluster),
                        child: _buildClusterMarker(cluster, theme),
                      ),
                    ),
                if (selfPos != null)
                  Marker(
                    point: selfPos,
                    width: 44,
                    height: 44,
                    child: _buildSelfMarker(theme),
                  ),
              ],
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Text(
                      'MeshCore Portugal | © OpenStreetMap contributors',
                      style: TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        // ---- Trace result card ----
        if (traceResult != null)
          Positioned(
            top: 16,
            left: 16,
            right: 72,
            child: _TraceResultCard(
              result: traceResult,
              onClear:
                  () => ref.read(traceResultProvider.notifier).state = null,
              onFit: () {
                final pts = _tracePoints(traceResult, selfPos);
                if (pts.length > 1) _fitAll(pts);
              },
              theme: theme,
            ),
          ),

        // ---- No GPS hint ----
        if (!hasAny)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_off, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sem dados GPS. Toca em "Localizar" ou aguarda contactos com coordenadas.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ---- FABs ----
        Positioned(
          right: 16,
          bottom: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (hasAny) ...[
                FloatingActionButton.small(
                  heroTag: 'map_fit_all',
                  onPressed: () => _fitAll(allPoints),
                  tooltip: 'Ver todos',
                  child: const Icon(Icons.fit_screen),
                ),
                const SizedBox(height: 8),
              ],
              // If we already know the position, show a "center" button that
              // just pans without a new GPS fetch.  If position is unknown,
              // the button fetches GPS first.
              FloatingActionButton(
                heroTag: 'map_locate_me',
                onPressed:
                    _loadingLocation
                        ? null
                        : selfPos != null
                        ? () => _mapController.move(selfPos, _detailZoom)
                        : _locationSupported
                        ? _locateMe
                        : null,
                tooltip:
                    selfPos != null
                        ? 'Centrar na minha posição'
                        : 'Obter localização GPS',
                child:
                    _loadingLocation
                        ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : Icon(
                          selfPos != null
                              ? Icons.gps_fixed
                              : Icons.gps_not_fixed,
                        ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Trace helpers
  // ---------------------------------------------------------------------------

  /// Builds the ordered list of LatLng points for the trace polyline.
  /// Includes selfPos as the starting point, then all hops with GPS, in order.
  List<LatLng> _tracePoints(TraceResult result, LatLng? selfPos) {
    final pts = <LatLng>[];
    if (selfPos != null) pts.add(selfPos);
    for (final hop in result.hops) {
      if (hop.hasGps) pts.add(LatLng(hop.latitude!, hop.longitude!));
    }
    return pts;
  }

  Widget _buildHopMarker(TraceHop hop, ThemeData theme) {
    final snr = hop.snrDb.toStringAsFixed(1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Label pill floats above the geographic point / contact icon
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: 1),
          ),
          child: Text(
            '${hop.name ?? hop.hashHex.substring(0, 4)}  $snr dB',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Connector line from label to dot
        Container(width: 2, height: 10, color: theme.colorScheme.primary),
        // Dot — anchor point aligned to the geographic coordinate
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Marker widgets
  // ---------------------------------------------------------------------------

  Widget _buildContactMarker(Contact contact, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: _contactColor(contact),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x50000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Icon(_contactIconData(contact), color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildSelfMarker(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.primary, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x50000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.navigation,
          color: theme.colorScheme.primary,
          size: 22,
        ),
      ),
    );
  }

  Color _contactColor(Contact c) {
    if (c.isChat) return Colors.blue.shade600;
    if (c.isRepeater) return Colors.orange.shade700;
    if (c.isRoom) return Colors.purple.shade600;
    return Colors.teal.shade600;
  }

  IconData _contactIconData(Contact c) {
    if (c.isChat) return Icons.person;
    if (c.isRepeater) return Icons.cell_tower;
    if (c.isRoom) return Icons.meeting_room;
    return Icons.sensors;
  }

  // ---------------------------------------------------------------------------
  // Cluster marker widget
  // ---------------------------------------------------------------------------

  Widget _buildClusterMarker(_ContactCluster cluster, ThemeData theme) {
    // Use the dominant type color of the cluster members
    final dominantColor = _contactColor(cluster.members.first);
    return Container(
      decoration: BoxDecoration(
        color: dominantColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x60000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '${cluster.members.length}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  void _onClusterTap(_ContactCluster cluster) {
    final points =
        cluster.members.map((c) => LatLng(c.latitude!, c.longitude!)).toList();
    final allSameLocation = cluster.members.every(
      (c) =>
          (c.latitude! - cluster.members.first.latitude!).abs() < 0.0001 &&
          (c.longitude! - cluster.members.first.longitude!).abs() < 0.0001,
    );

    if (allSameLocation) {
      // Can't separate by zooming — show list sheet instead
      _showClusterSheet(cluster);
    } else {
      _fitAll(points);
    }
  }

  void _showClusterSheet(_ContactCluster cluster) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (ctx) => _ClusterListSheet(
            cluster: cluster,
            onContactTap: (c) {
              Navigator.pop(ctx);
              _showContactSheet(c);
            },
          ),
    );
  }

  // ---------------------------------------------------------------------------
  // Contact info bottom sheet
  // ---------------------------------------------------------------------------

  void _showContactSheet(Contact contact) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _ContactInfoSheet(contact: contact),
    );
  }
}

/// Bottom sheet shown when tapping a contact marker on the map.
class _ContactInfoSheet extends ConsumerWidget {
  const _ContactInfoSheet({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final keyHex =
        contact.publicKey
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();

    final typeLabel =
        contact.isChat
            ? 'Companheiro'
            : contact.isRepeater
            ? 'Repetidor'
            : contact.isRoom
            ? 'Sala'
            : 'Sensor';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + type chip on one line
          Row(
            children: [
              Icon(
                _iconData(contact),
                color: theme.colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 10),
              Chip(
                label: Text(typeLabel),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Full name — wraps freely, no truncation
          Text(
            contact.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            softWrap: true,
          ),
          const SizedBox(height: 12),

          // Details
          _DetailRow(
            icon: Icons.fingerprint,
            label: 'ID',
            value: contact.shortId,
            monospace: true,
            theme: theme,
          ),
          if (contact.latitude != null && contact.longitude != null)
            _DetailRow(
              icon: Icons.location_on_outlined,
              label: 'GPS',
              value:
                  '${contact.latitude!.toStringAsFixed(5)},  '
                  '${contact.longitude!.toStringAsFixed(5)}',
              theme: theme,
            ),
          const SizedBox(height: 20),

          // Action button — only for chat contacts
          if (contact.isChat)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.chat),
                label: const Text('Enviar mensagem'),
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/chat/$keyHex');
                },
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconData(Contact c) {
    if (c.isChat) return Icons.person;
    if (c.isRepeater) return Icons.cell_tower;
    if (c.isRoom) return Icons.meeting_room;
    return Icons.sensors;
  }
}

/// A labelled detail row used in the contact bottom sheet.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
    this.monospace = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          SizedBox(
            width: 36,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: monospace ? 'monospace' : null,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cluster data model
// ---------------------------------------------------------------------------

class _ContactCluster {
  const _ContactCluster({required this.members, required this.center});
  final List<Contact> members;
  final LatLng center;
  bool get isSingle => members.length == 1;
}

// ---------------------------------------------------------------------------
// Cluster list bottom sheet
// ---------------------------------------------------------------------------

class _ClusterListSheet extends StatelessWidget {
  const _ClusterListSheet({required this.cluster, required this.onContactTap});

  final _ContactCluster cluster;
  final void Function(Contact) onContactTap;

  static Color _typeColor(Contact c) {
    if (c.isChat) return Colors.blue.shade600;
    if (c.isRepeater) return Colors.orange.shade700;
    if (c.isRoom) return Colors.purple.shade600;
    return Colors.teal.shade600;
  }

  static IconData _typeIcon(Contact c) {
    if (c.isChat) return Icons.person;
    if (c.isRepeater) return Icons.cell_tower;
    if (c.isRoom) return Icons.meeting_room;
    return Icons.sensors;
  }

  static String _typeLabel(Contact c) {
    if (c.isChat) return 'Companheiro';
    if (c.isRepeater) return 'Repetidor';
    if (c.isRoom) return 'Sala';
    return 'Sensor';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '${cluster.members.length} nós nesta localização',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final contact in cluster.members)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _typeColor(contact),
                      child: Icon(
                        _typeIcon(contact),
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      contact.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${_typeLabel(contact)}  ·  ${contact.shortId}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onContactTap(contact),
                  ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trace result overlay card
// ---------------------------------------------------------------------------

class _TraceResultCard extends StatelessWidget {
  const _TraceResultCard({
    required this.result,
    required this.onClear,
    required this.onFit,
    required this.theme,
  });

  final TraceResult result;
  final VoidCallback onClear;
  final VoidCallback onFit;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final ts =
        '${result.timestamp.hour.toString().padLeft(2, '0')}:'
        '${result.timestamp.minute.toString().padLeft(2, '0')}:'
        '${result.timestamp.second.toString().padLeft(2, '0')}';

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
                Icon(Icons.route, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Trace · $ts · ${result.hopCount} hop${result.hopCount != 1 ? 's' : ''}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                InkWell(
                  onTap: onFit,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.fit_screen,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                InkWell(
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            // Hop list
            if (result.hops.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (int i = 0; i < result.hops.length; i++)
                _HopRow(index: i + 1, hop: result.hops[i], theme: theme),
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
                    'Final: ${result.finalSnrDb.toStringAsFixed(1)} dB',
                    style: theme.textTheme.labelSmall?.copyWith(
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
  const _HopRow({required this.index, required this.hop, required this.theme});

  final int index;
  final TraceHop hop;
  final ThemeData theme;

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

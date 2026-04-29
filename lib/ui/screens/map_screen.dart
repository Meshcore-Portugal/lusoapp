import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../protocol/models.dart';
import '../../l10n/l10n.dart';
import '../../providers/gps_sharing_provider.dart';
import '../../providers/map_visibility_provider.dart';
import '../../providers/radio_providers.dart';
import '../../services/gps_sharing_service.dart';
import '../../transport/radio_transport.dart' show TransportState;

part 'parts/map_contact_sheets.dart';
part 'parts/map_cluster.dart';
part 'parts/map_trace_card.dart';

/// Full-screen map showing all contacts with GPS coordinates and the device's
/// own position.  Uses OpenStreetMap tiles via flutter_map (no API key needed).
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = MapController();
  final _mapRepaintKey = GlobalKey();
  bool _sharing = false;

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

  /// Lowercase hex of a contact's full 32-byte public key (used as the
  /// stable map-visibility opt-out key).
  static String _pubKeyHex(Uint8List key) =>
      key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// True on platforms where Geolocator works.
  bool get _locationSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _locateMe() async {
    if (!_locationSupported) return;
    final l10n = context.l10n;
    setState(() => _loadingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack(l10n.mapLocationDisabled);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnack(l10n.mapLocationDenied);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showSnack(l10n.mapLocationDeniedPermanently);
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
      _showSnack(l10n.mapLocationError);
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

  Future<void> _shareMap() async {
    if (_sharing) return;
    final l10n = context.l10n;
    setState(() => _sharing = true);
    try {
      // Ensure the latest map frame (tiles + polyline + hop markers) is painted
      // before capturing the RepaintBoundary.
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _mapRepaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        _showSnack(l10n.mapCaptureError);
        return;
      }

      if (!mounted) return;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final pixelRatio = dpr.clamp(1.5, 3.0);
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _showSnack(l10n.mapImageError);
        return;
      }
      final pngBytes = byteData.buffer.asUint8List();

      // Write to a real file on disk — apps like Telegram require an actual
      // file path and freeze/fail when given in-memory XFile.fromData bytes.
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/meshcore_map_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(pngBytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'Mapa MeshCore'),
      );
    } catch (_) {
      _showSnack(l10n.mapShareError);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider);
    final selfInfo = ref.watch(selfInfoProvider);
    final traceResult = ref.watch(traceResultProvider);
    final hidden = ref.watch(mapHiddenContactsProvider);
    final theme = Theme.of(context);

    final gpsContacts =
        contacts
            .where((c) => _isValidGps(c.latitude, c.longitude))
            .where((c) => !hidden.contains(_pubKeyHex(c.publicKey)))
            .toList();

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
        // ---- Capturable area (map + overlays, no FABs) ----
        RepaintBoundary(
          key: _mapRepaintKey,
          child: Stack(
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
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'pt.meshcore.lusoapp',
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
                  // ---- Contact + self markers (below hop labels) ----
                  // When a trace is active, hide contact/cluster markers so only
                  // the hop markers are shown alongside the polyline.
                  MarkerLayer(
                    markers: [
                      if (traceResult == null)
                        for (final cluster in _computeClusters(gpsContacts))
                          if (cluster.isSingle)
                            Marker(
                              point: cluster.center,
                              width: 44,
                              height: 44,
                              child: GestureDetector(
                                onTap:
                                    () => _showContactSheet(
                                      cluster.members.first,
                                    ),
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
                  // ---- Trace hop markers (rendered last = on top of contacts) ----
                  if (traceResult != null)
                    MarkerLayer(
                      markers: [
                        for (int hi = 0; hi < traceResult.hops.length; hi++)
                          if (traceResult.hops[hi].hasGps)
                            Marker(
                              point: LatLng(
                                traceResult.hops[hi].latitude!,
                                traceResult.hops[hi].longitude!,
                              ),
                              width: 140,
                              height: 130,
                              alignment: Alignment.center,
                              child: _buildHopMarker(
                                traceResult.hops[hi],
                                theme,
                                distanceM: _distanceToHop(
                                  traceResult.hops,
                                  hi,
                                  selfPos,
                                ),
                              ),
                            ),
                      ],
                    ),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.55),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
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
                              context.l10n.mapNoGps,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ], // ← close inner Stack.children
          ), // ← close inner Stack
        ), // ← close RepaintBoundary
        // ---- Trace result card (outside RepaintBoundary) ----
        // Keep this outside the captured map so shared images contain only the map.
        if (traceResult != null)
          Positioned(
            top: 16,
            left: 16,
            right: 72,
            child: _TraceResultCard(
              result: traceResult,
              selfPos: selfPos,
              onClear:
                  () => ref.read(traceResultProvider.notifier).state = null,
              onFit: () {
                final pts = _tracePoints(traceResult, selfPos);
                if (pts.length > 1) _fitAll(pts);
              },
              theme: theme,
            ),
          ),

        // ---- FABs (outside RepaintBoundary — not captured in screenshots) ----
        Positioned(
          right: 16,
          bottom: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'map_share',
                onPressed: _sharing ? null : _shareMap,
                tooltip: context.l10n.mapShareMap,
                child:
                    _sharing
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.share),
              ),
              const SizedBox(height: 8),
              if (hasAny) ...[
                FloatingActionButton.small(
                  heroTag: 'map_fit_all',
                  onPressed: () => _fitAll(allPoints),
                  tooltip: context.l10n.mapViewAll,
                  child: const Icon(Icons.fit_screen),
                ),
                const SizedBox(height: 8),
              ],
              // Quick "share my GPS to the radio" — only visible when the user
              // has explicitly enabled GPS sharing in Settings.
              Consumer(
                builder: (context, ref, _) {
                  final settings = ref.watch(gpsSharingProvider);
                  final connected =
                      ref.watch(connectionProvider) == TransportState.connected;
                  if (!settings.isEnabled) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FloatingActionButton.small(
                      heroTag: 'map_share_gps',
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      onPressed:
                          connected
                              ? () async {
                                final svc = ref.read(gpsSharingServiceProvider);
                                final res = await svc.shareNow();
                                if (!context.mounted) return;
                                final l10n = context.l10n;
                                final msg = switch (res.outcome) {
                                  GpsShareOutcome.ok => l10n
                                      .gpsSharingOutcomeOk(
                                        (res.lat ?? 0).toStringAsFixed(4),
                                        (res.lon ?? 0).toStringAsFixed(4),
                                      ),
                                  GpsShareOutcome.noPermission =>
                                    l10n.gpsSharingOutcomeNoPerm,
                                  GpsShareOutcome.serviceDisabled =>
                                    l10n.gpsSharingOutcomeServiceOff,
                                  GpsShareOutcome.notConnected =>
                                    l10n.gpsSharingOutcomeDisconnected,
                                  _ => l10n.gpsSharingOutcomeFailed,
                                };
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(SnackBar(content: Text(msg)));
                              }
                              : null,
                      tooltip: context.l10n.gpsSharingShareNow,
                      child: const Icon(Icons.upload_outlined),
                    ),
                  );
                },
              ),
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
                        ? context.l10n.mapCenterMyPosition
                        : context.l10n.mapGetGps,
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

  /// Distance from the previous GPS point to hop [index], in meters.
  /// The previous point is either [selfPos] (for the first hop) or the
  /// nearest previous hop that has GPS.
  double? _distanceToHop(List<TraceHop> hops, int index, LatLng? selfPos) {
    final hop = hops[index];
    if (!hop.hasGps) return null;

    LatLng? prevPt;
    if (index == 0) {
      prevPt = selfPos;
    } else {
      for (int k = index - 1; k >= 0; k--) {
        final prev = hops[k];
        if (!prev.hasGps) continue;
        prevPt = LatLng(prev.latitude!, prev.longitude!);
        break;
      }
    }

    if (prevPt == null) return null;
    return const Distance().as(
      LengthUnit.Meter,
      prevPt,
      LatLng(hop.latitude!, hop.longitude!),
    );
  }

  Widget _buildHopMarker(TraceHop hop, ThemeData theme, {double? distanceM}) {
    final snr = hop.snrDb.toStringAsFixed(1);
    final distLabel = distanceM != null ? '  ${_formatDist(distanceM)}' : '';
    // Layout (top → bottom):
    //   label (~18px) + dist (~14px) + connector (8px) + icon (36px) + spacer (40px) ≈ 116px.
    // Spacer height balances the content above the icon so the icon CENTER
    // is at the Column midpoint = Marker(alignment: Alignment.center) = LatLng.
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Name + SNR pill
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
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Distance pill (only when GPS available from previous point)
        if (distanceM != null)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              distLabel.trim(),
              style: const TextStyle(color: Colors.white, fontSize: 8),
            ),
          ),
        // Connector line from label to icon
        Container(width: 2, height: 8, color: theme.colorScheme.primary),
        // Repeater icon circle — CENTER is at the LatLng geographic point
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.orange.shade700,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x60000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.cell_tower, color: Colors.white, size: 20),
          ),
        ),
        // Balancing spacer = label + dist-pill + connector height above icon
        // so the icon center lands at the widget midpoint = LatLng anchor.
        const SizedBox(height: 40),
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
    if (c.isRepeater) {
      final name = c.name.toUpperCase();
      if (name.contains('R4')) return Colors.green.shade700; // 433 MHz
      if (name.contains('R8')) return Colors.deepOrange.shade700; // 868 MHz
      return Colors.orange.shade700; // unknown band
    }
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

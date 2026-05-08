// Windows BLE bridge — native (dart.library.io) implementation.
//
// Uses win_ble (WinRT via BLEServer.exe subprocess) directly.
// flutter_blue_plus has no Windows platform registration; this bridge
// replaces the scan/connect/GATT stack for Windows entirely.
//
// Only imported on non-web native builds via win_ble_bridge.dart.
// All call sites are guarded by !kIsWeb && Platform.isWindows.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show BluetoothAdapterState;
import 'package:logger/logger.dart';
import 'package:win_ble/win_ble.dart';
import 'package:win_ble/win_file.dart';

import 'radio_transport.dart';

final _log = Logger(printer: SimplePrinter(printTime: false));

// NUS UUID strings as returned by win_ble (braces stripped, case-normalised).
// Used for case-insensitive service/characteristic discovery matching.
const _nusServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const _nusRxUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
const _nusTxUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

// Generic Access Profile (GAP) service and Device Name characteristic.
// The real node name (e.g. "HEV99 C8/8") lives here — not in the advertisement.
const _gapServiceUuid = '00001800-0000-1000-8000-00805f9b34fb';
const _gapDeviceNameUuid = '00002a00-0000-1000-8000-00805f9b34fb';

/// Normalise a UUID string: strip braces, lowercase.
/// win_ble scan results may include `{UUID}` or plain UUID forms.
String _normUuid(String uuid) =>
    uuid.replaceAll('{', '').replaceAll('}', '').toLowerCase();

class WinBleBridge {
  WinBleBridge._();

  // Cached adapter state — updated by the bleState stream subscription.
  static BluetoothAdapterState _cachedAdapterState =
      BluetoothAdapterState.unknown;

  // Single-subscription guard for the bleState cache updater.
  static StreamSubscription<BleState>? _bleStateSub;

  // Lazy-init Future: shared across concurrent callers so WinBle.initialize
  // is invoked only once even if multiple operations start simultaneously.
  static Future<void>? _initFuture;

  // Addresses for which a background GATT connection was opened to read the
  // real node name.  Cleaned up when the scan ends, or handed off to
  // WindowsBleTransport when the user taps the device mid-scan.
  static final Set<String> _backgroundConnected = {};

  // Guards against launching duplicate background resolves for the same address.
  static final Set<String> _resolvingGattName = {};

  /// Map win_ble BleState to the flutter_blue_plus BluetoothAdapterState
  /// enum so connect_screen.dart can stay unaware of win_ble types.
  static BluetoothAdapterState _mapState(BleState s) => switch (s) {
        BleState.On => BluetoothAdapterState.on,
        BleState.Off => BluetoothAdapterState.off,
        BleState.Disabled || BleState.Unsupported =>
          BluetoothAdapterState.unavailable,
        _ => BluetoothAdapterState.unknown,
      };

  /// Initialise win_ble once.  Concurrent callers share the same Future.
  static Future<void> _ensureInitialized() =>
      _initFuture ??= _doInitialize();

  static Future<void> _doInitialize() async {
    final serverPath = await WinServer.path();
    await WinBle.initialize(serverPath: serverPath, enableLog: false);
    _log.i('WinBle initialised');
  }

  /// BLE adapter state stream, mapped to flutter_blue_plus types.
  ///
  /// Subscribes to win_ble's bleState internally to keep [adapterStateNow]
  /// up to date as a side effect.
  static Stream<BluetoothAdapterState> get adapterState {
    _bleStateSub ??= WinBle.bleState.listen((s) {
      _cachedAdapterState = _mapState(s);
    });
    return WinBle.bleState.map(_mapState);
  }

  /// Synchronous adapter state — last value seen from [adapterState].
  ///
  /// Returns [BluetoothAdapterState.unknown] until the first stream event.
  /// connect_screen.dart treats unknown as "on" so the first scan proceeds.
  static BluetoothAdapterState get adapterStateNow => _cachedAdapterState;

  /// Connects to [address] in the background and reads the GAP Device Name
  /// characteristic (0x2A00) to resolve the real node name (e.g. "HEV99 C8/8").
  ///
  /// Called during scan when a device is found with only a generic "MESHCORE"
  /// advertisement name.  If a better name is found the device is re-emitted
  /// into [controller] so the UI updates automatically.
  ///
  /// The connection is tracked in [_backgroundConnected]; it is either:
  ///   • disconnected at the end of [scan], or
  ///   • handed off to [WindowsBleTransport] if the user taps the device first.
  static Future<void> _resolveGattName(
    String address,
    Map<String, String> bestNames,
    StreamController<RadioDevice> controller,
    int rssi,
  ) async {
    if (_resolvingGattName.contains(address)) return;
    _resolvingGattName.add(address);
    try {
      await WinBle.connect(address).timeout(const Duration(seconds: 8));

      // If scan ended while we were connecting, release immediately.
      if (controller.isClosed) {
        try {
          await WinBle.disconnect(address);
        } catch (_) {}
        return;
      }
      _backgroundConnected.add(address);

      // Locate the GAP service.
      final services = await WinBle.discoverServices(address);
      final gapSvc = services.firstWhere(
        (s) => _normUuid(s) == _gapServiceUuid,
        orElse: () => '',
      );
      if (gapSvc.isEmpty) return;

      // Locate the Device Name characteristic inside GAP.
      final chars = await WinBle.discoverCharacteristics(
        address: address,
        serviceId: gapSvc,
      );
      final nameCharUuid =
          chars
              .where((c) => _normUuid(c.uuid) == _gapDeviceNameUuid)
              .map((c) => c.uuid)
              .firstOrNull;
      if (nameCharUuid == null) return;

      // Read the characteristic value and decode as UTF-8.
      final data = await WinBle.read(
        address: address,
        serviceId: gapSvc,
        characteristicId: nameCharUuid,
      );
      final name = utf8.decode(data.cast<int>(), allowMalformed: true).trim();
      _log.d('GATT name for $address: "$name"');

      if (name.isNotEmpty && !_isGenericName(name) && !controller.isClosed) {
        bestNames[address] = name;
        controller.add(
          RadioDevice(
            id: address,
            name: name,
            type: RadioDeviceType.ble,
            rssi: rssi,
          ),
        );
      }
    } catch (e) {
      _log.d('GATT name resolve failed for $address: $e');
      _backgroundConnected.remove(address);
    } finally {
      _resolvingGattName.remove(address);
    }
  }

  /// Scan for nearby MeshCore BLE devices and emit each as a [RadioDevice].
  ///
  /// win_ble's [WinBle.startScanning] ignores service-UUID filters, so
  /// Dart-layer filtering is applied: a device is kept only when it
  /// advertises the NUS service UUID or its name contains "meshcore".
  ///
  /// WinRT delivers BLE advertisements in two separate events per device:
  ///   1. ADV_IND (primary PDU)  — often contains only "MESHCORE" or no name.
  ///   2. SCAN_RSP (scan response) — often carries the real configured name.
  ///
  /// The bridge re-emits a device whenever a later event brings a better
  /// name, so the UI can replace the "MESHCORE" placeholder with the real one
  /// (e.g., "CT2HEV-NODE") as soon as the scan response arrives.
  static Stream<RadioDevice> scan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    final controller = StreamController<RadioDevice>();

    // Tracks the best name seen so far for each address.
    // null  = never seen.  Non-null = best name from any event so far.
    final Map<String, String> bestNames = {};

    Future<void> doScan() async {
      await _ensureInitialized();

      final sub = WinBle.scanStream.listen((device) {
        final address = device.address.toUpperCase();

        // Candidate name from this advertisement event (null if generic/missing).
        final advName =
            (device.name.isNotEmpty && device.name != 'N/A')
                ? device.name
                : null;

        // Normalise service UUIDs from scan advertisement (strip braces).
        final uuids =
            device.serviceUuids.map((u) => _normUuid(u.toString())).toList();

        final alreadySeen = bestNames.containsKey(address);

        // MeshCore filter: NUS service UUID, "meshcore" in name, or already
        // identified as MeshCore in a prior event for this address.
        final isMeshCore =
            uuids.contains(_nusServiceUuid) ||
            (advName?.toLowerCase().contains('meshcore') ?? false) ||
            alreadySeen;
        if (!isMeshCore) return;

        final currentBest = bestNames[address];

        // Decide whether this event improves the displayed name.
        // A name is "better" when it is non-null and the current best is
        // either absent or the generic firmware default ("MESHCORE").
        final isImprovement =
            advName != null &&
            advName != currentBest &&
            (currentBest == null || _isGenericName(currentBest));

        if (!alreadySeen || isImprovement) {
          // Prefer the new advName; fall back to whatever we had before.
          final name =
              advName ??
              currentBest ??
              'MeshCore (${address.substring(0, min(8, address.length))})';
          bestNames[address] = name;

          final rssi = int.tryParse(device.rssi) ?? 0;
          if (!controller.isClosed) {
            controller.add(
              RadioDevice(
                id: address,
                name: name,
                type: RadioDeviceType.ble,
                rssi: rssi,
              ),
            );
          }

          // Still a generic name — try reading the real name from GATT
          // (e.g. "HEV99 C8/8" from the GAP Device Name characteristic).
          if (_isGenericName(name)) {
            _resolveGattName(address, bestNames, controller, rssi);
          }
        }
      });

      WinBle.startScanning();
      await Future.delayed(timeout);
      WinBle.stopScanning();

      await sub.cancel();

      // Disconnect any background GATT connections opened for name resolution
      // that were not taken over by a WindowsBleTransport (user didn't tap them).
      final bgPending = Set<String>.from(_backgroundConnected);
      _backgroundConnected.clear();
      for (final addr in bgPending) {
        try {
          await WinBle.disconnect(addr);
        } catch (_) {}
      }

      await controller.close();
    }

    doScan();
    return controller.stream;
  }

  /// Create a Windows BLE transport for the given device address.
  ///
  /// [deviceId] is the MAC address string as emitted by [scan]
  /// (e.g. `"AA:BB:CC:DD:EE:FF"`).
  static RadioTransport createTransport(String deviceId) =>
      WindowsBleTransport(deviceId);
}

/// Returns true for the MeshCore firmware's generic advertisement name.
/// These names are placeholders that should be replaced if a more specific
/// name arrives in a subsequent scan-response event.
bool _isGenericName(String name) => name.toUpperCase() == 'MESHCORE';

/// Clamp helper for address truncation — avoids importing dart:math.
int min(int a, int b) => a < b ? a : b;

/// BLE transport implementation for Windows using win_ble (WinRT).
///
/// Uses the BLEServer.exe subprocess to talk to the WinRT BLE stack.
/// Implements the same [RadioTransport] contract as [BleTransport] so the
/// rest of the app (RadioService, ConnectionNotifier) needs no changes.
class WindowsBleTransport implements RadioTransport {
  /// [address] is a MAC address string, e.g. `"AA:BB:CC:DD:EE:FF"`.
  WindowsBleTransport(this._address);

  final String _address;

  // Discovered service / characteristic UUIDs (set during connect).
  String? _serviceId;
  String? _rxCharId;
  String? _txCharId;

  StreamSubscription? _notifySub;
  StreamSubscription<bool>? _connStateSub;
  final _dataController = StreamController<Uint8List>.broadcast();
  final _connectionLostController = StreamController<void>.broadcast();
  bool _connected = false;

  /// True when disconnect() was called by the app so that the connection-state
  /// listener does not fire a spurious connectionLost event on graceful close.
  bool _userDisconnected = false;

  @override
  String get displayName => 'BLE: $_address';

  @override
  bool get isConnected => _connected;

  @override
  bool get usesFraming => false;

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  @override
  Stream<void> get connectionLost => _connectionLostController.stream;

  @override
  Future<bool> connect() async {
    _userDisconnected = false;
    try {
      await WinBleBridge._ensureInitialized();
      _log.i('WindowsBleTransport: connecting to $_address');

      // If a background GATT name-resolution connection already exists for this
      // address, reuse it instead of disconnecting and reconnecting.
      // _backgroundConnected.remove() returns true and removes the entry atomically.
      final reuseBackground = WinBleBridge._backgroundConnected.remove(_address);
      if (reuseBackground) {
        _log.d('WindowsBleTransport: reusing background connection for $_address');
      } else {
        // WinBle.connect() resolves when the WinRT stack reports the device as
        // connected (it internally calls discoverServices to confirm).
        // Wrap with a Dart-level timeout because WinRT ignores any timeout arg.
        await WinBle.connect(_address).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException('WinBle connect timed out'),
        );
      }

      // Fetch the service list.  Since WinBle.connect already called
      // discoverServices(forceRefresh:true) internally, this second call
      // hits BLEServer.exe's cache and returns quickly.
      final services = await WinBle.discoverServices(_address);
      _serviceId = services.firstWhere(
        (s) => _normUuid(s) == _nusServiceUuid,
        orElse: () => throw StateError('NUS service not found'),
      );

      // Discover characteristics for the NUS service.
      final chars = await WinBle.discoverCharacteristics(
        address: _address,
        serviceId: _serviceId!,
      );
      _rxCharId = chars
          .firstWhere((c) => _normUuid(c.uuid) == _nusRxUuid)
          .uuid;
      _txCharId = chars
          .firstWhere((c) => _normUuid(c.uuid) == _nusTxUuid)
          .uuid;

      _log.d('RX: $_rxCharId  TX: $_txCharId');

      // Subscribe to incoming data from TX characteristic BEFORE enabling
      // notifications (mirrors flutter_blue_plus best-practice ordering).
      _notifySub = WinBle.characteristicValueStreamOf(
        address: _address,
        serviceId: _serviceId!,
        characteristicId: _txCharId!,
      ).listen((data) {
        // BLEServer.exe serialises values as JSON arrays; cast to Uint8List.
        final bytes =
            data is Uint8List
                ? data
                : Uint8List.fromList((data as List).cast<int>());
        _dataController.add(bytes);
      });

      // Enable CCCD notifications on the TX characteristic.
      await WinBle.subscribeToCharacteristic(
        address: _address,
        serviceId: _serviceId!,
        characteristicId: _txCharId!,
      );

      _connected = true;
      _log.i('WindowsBleTransport: connected to $_address');

      // Monitor for unexpected disconnects (not caused by dispose/disconnect).
      _connStateSub = WinBle.connectionStreamOf(_address).listen((isConn) {
        if (!isConn && _connected && !_userDisconnected) {
          _log.w('WindowsBleTransport: connection lost unexpectedly');
          _connected = false;
          _connectionLostController.add(null);
        }
      });

      return true;
    } catch (e) {
      _log.e('WindowsBleTransport: connect failed: $e');
      await _notifySub?.cancel();
      _notifySub = null;
      _connected = false;
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _userDisconnected = true;
    _connected = false;
    await _notifySub?.cancel();
    _notifySub = null;
    await _connStateSub?.cancel();
    _connStateSub = null;
    // Unsubscribe from TX notifications before disconnecting.
    if (_serviceId != null && _txCharId != null) {
      try {
        await WinBle.unSubscribeFromCharacteristic(
          address: _address,
          serviceId: _serviceId!,
          characteristicId: _txCharId!,
        );
      } catch (_) {}
    }
    try {
      await WinBle.disconnect(_address);
    } catch (_) {}
    _log.i('WindowsBleTransport: disconnected from $_address');
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_rxCharId == null || !_connected) {
      throw StateError('Not connected');
    }
    // NUS RX always supports Write Without Response; this eliminates the
    // ATT Write Response round-trip so the full reply timeout is preserved.
    await WinBle.write(
      address: _address,
      service: _serviceId!,
      characteristic: _rxCharId!,
      data: data,
      writeWithResponse: false,
    );
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _dataController.close();
    await _connectionLostController.close();
  }
}

/// Unit tests for the Windows BLE scan filter in [BleTransport].
///
/// On Windows, flutter_blue_plus_windows (WinRT) ignores the withServices
/// scan filter and returns every visible BLE advertisement.  [BleTransport.scan]
/// calls [BleTransport.isMeshCoreAdvertisement] per result to discard
/// non-MeshCore devices before they reach the UI.
///
/// These tests exercise [isMeshCoreAdvertisement] directly (using plain
/// [Guid]/[String] values) so no platform channel or real BLE hardware is
/// needed.
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/transport/ble_transport.dart';

void main() {
  // Nordic UART Service UUID used by all MeshCore BLE radios.
  final nusGuid = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');

  // An unrelated GATT service UUID (Generic Access Profile).
  final gapGuid = Guid('00001800-0000-1000-8000-00805F9B34FB');

  group('BleTransport.isMeshCoreAdvertisement — service UUID check', () {
    test('accepts device that advertises the NUS service UUID', () {
      expect(
        BleTransport.isMeshCoreAdvertisement([nusGuid], 'SomeDevice'),
        isTrue,
      );
    });

    test('accepts device with NUS UUID among other service UUIDs', () {
      expect(
        BleTransport.isMeshCoreAdvertisement(
          [gapGuid, nusGuid],
          'MultiServiceDevice',
        ),
        isTrue,
      );
    });

    test('rejects device with only unrelated service UUIDs and generic name', () {
      expect(
        BleTransport.isMeshCoreAdvertisement([gapGuid], 'MyHeadphones'),
        isFalse,
      );
    });
  });

  group('BleTransport.isMeshCoreAdvertisement — name fallback', () {
    test('accepts device named "MeshCore-1A2B" even without service UUID', () {
      expect(
        BleTransport.isMeshCoreAdvertisement([], 'MeshCore-1A2B'),
        isTrue,
      );
    });

    test('accepts device with lowercase "meshcore" in name', () {
      expect(
        BleTransport.isMeshCoreAdvertisement([], 'meshcore-node'),
        isTrue,
      );
    });

    test('accepts device with mixed-case "MeshCore" substring', () {
      expect(
        BleTransport.isMeshCoreAdvertisement([], 'CT2HEV MeshCore Relay'),
        isTrue,
      );
    });

    test('rejects device with empty name and no service UUIDs', () {
      expect(BleTransport.isMeshCoreAdvertisement([], ''), isFalse);
    });

    test('rejects device with unrelated name and no service UUIDs', () {
      expect(
        BleTransport.isMeshCoreAdvertisement([], 'JBL Headset'),
        isFalse,
      );
    });
  });
}

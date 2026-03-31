import 'dart:typed_data';

/// Generates and parses the `meshcore://` deep-link URI scheme used for QR
/// code sharing of contacts and channels.
///
/// Formats (from the official MeshCore QR-codes spec):
///   meshcore://contact/add?name=NAME&public_key=64HEX&type=1-4
///   meshcore://channel/add?name=NAME&secret=32HEX
abstract class MeshCoreUri {
  MeshCoreUri._();

  static const _scheme = 'meshcore';

  // ---------------------------------------------------------------------------
  // Generators
  // ---------------------------------------------------------------------------

  /// Build a `meshcore://contact/add` URI for sharing own identity or any
  /// contact.  [type]: 1 = Companion, 2 = Repeater, 3 = Room Server, 4 = Sensor.
  static String buildContactUri({
    required String name,
    required Uint8List publicKey,
    int type = 1,
  }) {
    final hex =
        publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return Uri(
      scheme: _scheme,
      host: 'contact',
      path: '/add',
      queryParameters: {'name': name, 'public_key': hex, 'type': '$type'},
    ).toString();
  }

  /// Build a `meshcore://channel/add` URI for sharing a channel secret.
  /// [secret] must be exactly 16 bytes.
  static String buildChannelUri({
    required String name,
    required Uint8List secret,
  }) {
    final hex = secret.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return Uri(
      scheme: _scheme,
      host: 'channel',
      path: '/add',
      queryParameters: {'name': name, 'secret': hex},
    ).toString();
  }

  // ---------------------------------------------------------------------------
  // Parser
  // ---------------------------------------------------------------------------

  /// Parse a raw URI string.  Returns a [MeshCoreContactUri] or
  /// [MeshCoreChannelUri] on success, or `null` if the URI is malformed or
  /// has an unrecognised host/path.
  static MeshCoreUriResult? parse(String raw) {
    try {
      final uri = Uri.parse(raw);
      if (uri.scheme != _scheme) return null;

      if (uri.host == 'contact' && uri.path == '/add') {
        final name = uri.queryParameters['name'] ?? '';
        final pkHex = uri.queryParameters['public_key'] ?? '';
        final typeStr = uri.queryParameters['type'] ?? '1';
        if (pkHex.length != 64) return null;
        final pubKey = _hexToBytes(pkHex);
        if (pubKey == null) return null;
        return MeshCoreContactUri(
          name: name,
          publicKey: pubKey,
          type: int.tryParse(typeStr) ?? 1,
        );
      }

      if (uri.host == 'channel' && uri.path == '/add') {
        final name = uri.queryParameters['name'] ?? '';
        final secretHex = uri.queryParameters['secret'] ?? '';
        if (secretHex.length != 32) return null;
        final secret = _hexToBytes(secretHex);
        if (secret == null) return null;
        return MeshCoreChannelUri(name: name, secret: secret);
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static Uint8List? _hexToBytes(String hex) {
    try {
      return Uint8List.fromList(
        List.generate(
          hex.length ~/ 2,
          (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class MeshCoreUriResult {}

class MeshCoreContactUri extends MeshCoreUriResult {
  MeshCoreContactUri({
    required this.name,
    required this.publicKey,
    required this.type,
  });

  final String name;
  final Uint8List publicKey;

  /// 1 = Companion, 2 = Repeater, 3 = Room Server, 4 = Sensor.
  final int type;
}

class MeshCoreChannelUri extends MeshCoreUriResult {
  MeshCoreChannelUri({required this.name, required this.secret});

  final String name;
  final Uint8List secret; // 16 bytes
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/protocol/commands.dart';
import 'package:lusoapp/protocol/companion_decoder.dart';
import 'package:lusoapp/protocol/companion_encoder.dart';
import 'package:lusoapp/protocol/models.dart';

/// Verifies that the app correctly reads and writes the 'favourite' bit
/// (bit 0 of `flags`) used by MeshCore firmware.
///
/// The firmware comment in `examples/companion_radio/MyMesh.cpp` reads:
///   uint8_t cp = contact.flags >> 1; // LSB used as 'favourite' bit
///
/// So bit 0 == 1 means starred, and the upper bits carry permission data
/// that must be preserved across a toggle.
void main() {
  group('Contact.isFavorite / withFavorite', () {
    final pubKey = Uint8List.fromList(List.generate(32, (i) => i));

    Contact make(int flags) => Contact(
      publicKey: pubKey,
      type: 0x01,
      flags: flags,
      pathLen: 0,
      name: 'Alice',
      lastAdvertTimestamp: 123,
    );

    test('isFavorite reflects bit 0 of flags', () {
      expect(make(0x00).isFavorite, isFalse);
      expect(make(0x01).isFavorite, isTrue);
      expect(make(0x02).isFavorite, isFalse);
      expect(make(0x03).isFavorite, isTrue);
      expect(make(0xFE).isFavorite, isFalse);
      expect(make(0xFF).isFavorite, isTrue);
    });

    test('withFavorite(true) sets bit 0 without touching upper bits', () {
      final c = make(0xA2); // upper bits 0b1010_0010, bit 0 clear
      final starred = c.withFavorite(true);
      expect(starred.isFavorite, isTrue);
      expect(starred.flags, 0xA3); // upper bits preserved, bit 0 set
    });

    test('withFavorite(false) clears bit 0 without touching upper bits', () {
      final c = make(0xA3); // upper bits 0b1010_0010, bit 0 set
      final unstarred = c.withFavorite(false);
      expect(unstarred.isFavorite, isFalse);
      expect(unstarred.flags, 0xA2); // upper bits preserved, bit 0 cleared
    });

    test('withFavorite returns identical instance when already in state', () {
      final c = make(0x05);
      expect(identical(c.withFavorite(true), c), isTrue);
    });

    test('toggling twice restores the exact original flags byte', () {
      for (final f in [0x00, 0x01, 0x42, 0xFF, 0x80]) {
        final original = make(f);
        final toggled =
            original.withFavorite(!original.isFavorite).withFavorite(
              original.isFavorite,
            );
        expect(toggled.flags, original.flags, reason: 'f=0x${f.toRadixString(16)}');
      }
    });
  });

  group('flags byte round-trips through encoder/decoder', () {
    final pubKey = Uint8List.fromList(List.generate(32, (i) => 0x10 + i));

    /// Strip the 3-byte frame header (dir + len16) + 1-byte command opcode
    /// to produce the raw payload that matches the decoder's input format.
    Uint8List payloadOf(Uint8List frame) {
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdAddUpdateContact);
      return Uint8List.fromList(frame.sublist(4));
    }

    test('isFavorite=true survives encode → decode', () {
      final original = Contact(
        publicKey: pubKey,
        type: 0x01,
        flags: 0x00,
        pathLen: 0,
        name: 'Bob',
        lastAdvertTimestamp: 42,
      ).withFavorite(true);

      final frame = CompanionEncoder.addUpdateContact(original);
      final decoded = _decodeContact(payloadOf(frame));

      expect(decoded, isNotNull);
      expect(decoded!.flags, original.flags);
      expect(decoded.isFavorite, isTrue);
    });

    test('upper permission bits survive toggling favourite on and off', () {
      final withPerms = Contact(
        publicKey: pubKey,
        type: 0x02,
        flags: 0x5C, // arbitrary upper bits
        pathLen: 0,
        name: 'Repeater',
        lastAdvertTimestamp: 99,
      );

      final toggled = withPerms.withFavorite(true).withFavorite(false);
      expect(toggled.flags, withPerms.flags);

      final frame = CompanionEncoder.addUpdateContact(toggled);
      final decoded = _decodeContact(payloadOf(frame));
      expect(decoded!.flags, withPerms.flags);
    });
  });
}

/// Invoke the same parser the live decoder uses for RESP_CONTACT frames.
/// The addUpdateContact payload layout mirrors the contact struct the
/// firmware emits, so we can decode it directly.
Contact? _decodeContact(Uint8List payload) {
  // Wrap the payload in the decoder's expected stream framing:
  // dirRadioToApp | len16 | respContact | <payload>
  final framed = BytesBuilder();
  final len = payload.length + 1; // +1 for response code
  framed.addByte(dirRadioToApp);
  framed.addByte(len & 0xFF);
  framed.addByte((len >> 8) & 0xFF);
  framed.addByte(respContact);
  framed.add(payload);

  final (frames, _) = CompanionDecoder.extractFrames(framed.toBytes());
  expect(frames, hasLength(1));
  final resp = CompanionDecoder.decode(frames.first);
  if (resp is! ContactResponse) return null;
  return resp.contact;
}

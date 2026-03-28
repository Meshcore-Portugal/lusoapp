import 'dart:typed_data';

import 'models.dart';

/// Parses a [TraceDataPush] raw [data] field into a [TraceResult].
///
/// Binary layout (bytes after the push-code byte 0x89 has been stripped by
/// the decoder, so `data[0]` is the first payload byte):
///
/// ```
/// [0]                         reserved (0x00)
/// [1]                         path_len  — byte count of path_hashes block
/// [2]                         flags     — bits[1:0] = path_sz
///                                         hash_size = 1 << path_sz  (1,2,4,8)
/// [3..6]                      tag        uint32 LE
/// [7..10]                     auth_code  uint32 LE
/// [11 .. 11+path_len-1]       path_hashes  (hop_count × hash_size bytes)
/// [11+path_len .. +hop_count-1] path_snrs  (int8: SNR × 4, one per hop)
/// [11+path_len+hop_count]     final_snr  (int8: SNR × 4, last link)
/// ```
///
/// `hop_count = path_len >> path_sz`  (= path_len / hash_size)
TraceResult? parseTraceDataPush(Uint8List data, List<Contact> knownContacts) {
  // Minimum viable frame: 1+1+1+4+4+1 = 12 bytes
  if (data.length < 12) return null;

  final pathLen = data[1];
  final flags = data[2];
  final pathSz = flags & 0x03;
  final hashSize = 1 << pathSz; // 1, 2, 4, or 8
  final hopCount = pathLen >> pathSz; // = pathLen / hashSize

  final tag = ByteData.sublistView(data, 3, 7).getUint32(0, Endian.little);

  const hashesStart = 11;
  final hashesEnd = hashesStart + pathLen;
  final snrsEnd = hashesEnd + hopCount;

  if (data.length < snrsEnd + 1) return null;

  final hops = <TraceHop>[];
  for (int i = 0; i < hopCount; i++) {
    final hStart = hashesStart + i * hashSize;
    final hEnd = hStart + hashSize;
    if (hEnd > hashesEnd) break;

    final hashBytes = data.sublist(hStart, hEnd);
    final hashHex =
        hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final snrRaw = data[hashesEnd + i];
    final snrDb = (snrRaw > 127 ? snrRaw - 256 : snrRaw) / 4.0;

    // Try to match against a known contact by comparing publicKey prefix
    Contact? matched;
    for (final c in knownContacts) {
      if (c.publicKey.length >= hashSize) {
        var eq = true;
        for (int j = 0; j < hashSize; j++) {
          if (c.publicKey[j] != hashBytes[j]) {
            eq = false;
            break;
          }
        }
        if (eq) {
          matched = c;
          break;
        }
      }
    }

    hops.add(
      TraceHop(
        hashHex: hashHex,
        snrDb: snrDb,
        name: matched?.name,
        latitude: matched?.latitude,
        longitude: matched?.longitude,
      ),
    );
  }

  final finalSnrRaw = data[snrsEnd];
  final finalSnrDb =
      (finalSnrRaw > 127 ? finalSnrRaw - 256 : finalSnrRaw) / 4.0;

  return TraceResult(
    tag: tag,
    hops: hops,
    finalSnrDb: finalSnrDb,
    timestamp: DateTime.now(),
  );
}

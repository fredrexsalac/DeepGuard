import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Single file entry to be written into a standard PKZIP 2.0 `.zip` archive.
class ZipArchiveEntry {
  /// Forward-slash relative path inside the archive (e.g. `manifest.json` or
  /// `evidence/1730001234/sample.mp4`).
  final String name;

  /// Raw uncompressed file bytes.
  final Uint8List bytes;

  /// Whether to apply raw DEFLATE compression (method 8).
  /// Use `true` for JSON/text manifests and `false` (method 0 = STORE) for
  /// already-compressed images/videos so packaging is fast and lossless.
  final bool compress;

  /// Optional modification timestamp recorded in MS-DOS header fields.
  final DateTime? modifiedAt;

  const ZipArchiveEntry({
    required this.name,
    required this.bytes,
    this.compress = false,
    this.modifiedAt,
  });
}

/// Pure-Dart + `dart:io` `zlib` standard PKZIP 2.0 encoder and decoder.
///
/// Produces 100% standard `.zip` archives compatible with Windows Explorer,
/// macOS Finder, Android Files, iOS Files, 7-Zip, and Python `zipfile`, with
/// UTF-8 filenames (general purpose flag bit 11) and IEEE 802.3 CRC-32 checks.
class EvidenceZipCodec {
  EvidenceZipCodec._();

  static const int _lfhSignature = 0x04034b50;
  static const int _cdfhSignature = 0x02014b50;
  static const int _eocdSignature = 0x06054b50;
  static const int _utf8Flag = 0x0800;
  static const int _encryptedFlag = 0x0001;
  static const int _methodStore = 0;
  static const int _methodDeflate = 8;

  static final Uint32List _crcTable = _buildCrcTable();

  static Uint32List _buildCrcTable() {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      table[n] = c;
    }
    return table;
  }

  /// Computes standard unsigned 32-bit IEEE 802.3 CRC-32 checksum.
  static int computeCrc32(Uint8List bytes) {
    var crc = 0xFFFFFFFF;
    for (var i = 0; i < bytes.length; i++) {
      crc = _crcTable[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  /// Returns true when [bytes] begins with a standard PKZIP signature (`PK..`).
  static bool isZipBytes(Uint8List bytes) {
    if (bytes.length < 22) return false;
    return bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07);
  }

  static (int dosTime, int dosDate) _toDosDateTime(DateTime? dt) {
    final d = dt ?? DateTime.now();
    final year = d.year.clamp(1980, 2107);
    final dosTime = ((d.hour & 0x1F) << 11) |
        ((d.minute & 0x3F) << 5) |
        ((d.second ~/ 2) & 0x1F);
    final dosDate = (((year - 1980) & 0x7F) << 9) |
        ((d.month & 0x0F) << 5) |
        (d.day & 0x1F);
    return (dosTime, dosDate);
  }

  /// Encodes [entries] into a standard `.zip` byte buffer.
  static Uint8List encode(List<ZipArchiveEntry> entries) {
    final out = BytesBuilder(copy: false);
    final centralDir = BytesBuilder(copy: false);
    final rawDeflater = ZLibEncoder(raw: true);

    var currentOffset = 0;
    var writtenEntries = 0;

    for (final entry in entries) {
      final cleanName = entry.name
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^/+'), '');
      if (cleanName.isEmpty) continue;

      final nameBytes = Uint8List.fromList(utf8.encode(cleanName));
      final uncompressed = entry.bytes;
      final crc = computeCrc32(uncompressed);

      var method = _methodStore;
      var payload = uncompressed;
      if (entry.compress && uncompressed.isNotEmpty) {
        final deflated = Uint8List.fromList(rawDeflater.convert(uncompressed));
        if (deflated.length < uncompressed.length) {
          method = _methodDeflate;
          payload = deflated;
        }
      }

      final (dosTime, dosDate) = _toDosDateTime(entry.modifiedAt);
      final localHeaderOffset = currentOffset;

      // 1. Local File Header (30 bytes + name)
      final lfh = ByteData(30);
      lfh.setUint32(0, _lfhSignature, Endian.little);
      lfh.setUint16(4, 20, Endian.little); // version needed = 2.0
      lfh.setUint16(6, _utf8Flag, Endian.little);
      lfh.setUint16(8, method, Endian.little);
      lfh.setUint16(10, dosTime, Endian.little);
      lfh.setUint16(12, dosDate, Endian.little);
      lfh.setUint32(14, crc, Endian.little);
      lfh.setUint32(18, payload.length, Endian.little);
      lfh.setUint32(22, uncompressed.length, Endian.little);
      lfh.setUint16(26, nameBytes.length, Endian.little);
      lfh.setUint16(28, 0, Endian.little); // extra length

      final lfhBytes = lfh.buffer.asUint8List();
      out.add(lfhBytes);
      out.add(nameBytes);
      out.add(payload);
      currentOffset += 30 + nameBytes.length + payload.length;

      // 2. Central Directory File Header (46 bytes + name)
      final cdfh = ByteData(46);
      cdfh.setUint32(0, _cdfhSignature, Endian.little);
      cdfh.setUint16(4, 20, Endian.little); // version made by
      cdfh.setUint16(6, 20, Endian.little); // version needed
      cdfh.setUint16(8, _utf8Flag, Endian.little);
      cdfh.setUint16(10, method, Endian.little);
      cdfh.setUint16(12, dosTime, Endian.little);
      cdfh.setUint16(14, dosDate, Endian.little);
      cdfh.setUint32(16, crc, Endian.little);
      cdfh.setUint32(20, payload.length, Endian.little);
      cdfh.setUint32(24, uncompressed.length, Endian.little);
      cdfh.setUint16(28, nameBytes.length, Endian.little);
      cdfh.setUint16(30, 0, Endian.little); // extra length
      cdfh.setUint16(32, 0, Endian.little); // comment length
      cdfh.setUint16(34, 0, Endian.little); // disk number start
      cdfh.setUint16(36, 0, Endian.little); // internal attributes
      cdfh.setUint32(38, 0, Endian.little); // external attributes
      cdfh.setUint32(42, localHeaderOffset, Endian.little);

      centralDir.add(cdfh.buffer.asUint8List());
      centralDir.add(nameBytes);
      writtenEntries++;
    }

    final centralBytes = centralDir.takeBytes();
    final centralOffset = currentOffset;
    out.add(centralBytes);

    // 3. End of Central Directory Record (22 bytes)
    final eocd = ByteData(22);
    eocd.setUint32(0, _eocdSignature, Endian.little);
    eocd.setUint16(4, 0, Endian.little); // disk number
    eocd.setUint16(6, 0, Endian.little); // disk with central dir
    eocd.setUint16(8, writtenEntries, Endian.little);
    eocd.setUint16(10, writtenEntries, Endian.little);
    eocd.setUint32(12, centralBytes.length, Endian.little);
    eocd.setUint32(16, centralOffset, Endian.little);
    eocd.setUint16(20, 0, Endian.little); // comment length
    out.add(eocd.buffer.asUint8List());

    return out.takeBytes();
  }

  /// Decodes a standard `.zip` byte buffer into a map of normalized forward-slash
  /// relative paths to uncompressed file bytes, verifying CRC-32 integrity.
  static Map<String, Uint8List> decode(Uint8List zipBytes) {
    if (!isZipBytes(zipBytes)) {
      throw const FormatException('Not a valid ZIP archive.');
    }

    final view = ByteData.sublistView(zipBytes);
    final minSearch = (zipBytes.length - 65557).clamp(0, zipBytes.length);
    var eocdOffset = -1;

    for (var i = zipBytes.length - 22; i >= minSearch; i--) {
      if (view.getUint32(i, Endian.little) == _eocdSignature) {
        final commentLen = view.getUint16(i + 20, Endian.little);
        if (i + 22 + commentLen <= zipBytes.length) {
          eocdOffset = i;
          break;
        }
      }
    }
    if (eocdOffset < 0) {
      throw const FormatException(
        'Invalid or truncated ZIP archive (missing Central Directory record).',
      );
    }

    final totalEntries = view.getUint16(eocdOffset + 10, Endian.little);
    final cdSize = view.getUint32(eocdOffset + 12, Endian.little);
    final cdOffset = view.getUint32(eocdOffset + 16, Endian.little);

    if (cdOffset + cdSize > eocdOffset) {
      throw const FormatException('Corrupted ZIP Central Directory bounds.');
    }

    final files = <String, Uint8List>{};
    final rawInflater = ZLibDecoder(raw: true);
    var pos = cdOffset;

    for (var idx = 0; idx < totalEntries; idx++) {
      if (pos + 46 > eocdOffset) {
        throw const FormatException('Truncated ZIP Central Directory entry.');
      }
      if (view.getUint32(pos, Endian.little) != _cdfhSignature) {
        throw const FormatException('Invalid ZIP Central Directory signature.');
      }

      final flags = view.getUint16(pos + 8, Endian.little);
      final method = view.getUint16(pos + 10, Endian.little);
      final expectedCrc = view.getUint32(pos + 16, Endian.little);
      final compSize = view.getUint32(pos + 20, Endian.little);
      final uncompSize = view.getUint32(pos + 24, Endian.little);
      final nameLen = view.getUint16(pos + 28, Endian.little);
      final extraLen = view.getUint16(pos + 30, Endian.little);
      final commentLen = view.getUint16(pos + 32, Endian.little);
      final lhOffset = view.getUint32(pos + 42, Endian.little);

      final headerEnd = pos + 46 + nameLen + extraLen + commentLen;
      if (headerEnd > eocdOffset) {
        throw const FormatException('Invalid ZIP entry header length.');
      }

      final rawName = utf8.decode(
        Uint8List.sublistView(zipBytes, pos + 46, pos + 46 + nameLen),
        allowMalformed: true,
      );
      pos = headerEnd;

      final normalizedName = rawName.replaceAll('\\', '/');
      if (normalizedName.isEmpty || normalizedName.endsWith('/')) {
        continue; // Directory entry
      }
      if ((flags & _encryptedFlag) != 0) {
        throw const FormatException(
          'Password-protected ZIP archives are not supported.',
        );
      }

      if (lhOffset + 30 > zipBytes.length ||
          view.getUint32(lhOffset, Endian.little) != _lfhSignature) {
        throw FormatException('Invalid local header for "$normalizedName".');
      }

      final lfhNameLen = view.getUint16(lhOffset + 26, Endian.little);
      final lfhExtraLen = view.getUint16(lhOffset + 28, Endian.little);
      final dataStart = lhOffset + 30 + lfhNameLen + lfhExtraLen;
      final dataEnd = dataStart + compSize;

      if (dataEnd > zipBytes.length) {
        throw FormatException('Truncated file payload for "$normalizedName".');
      }

      final compSlice = Uint8List.sublistView(zipBytes, dataStart, dataEnd);
      final Uint8List decodedBytes;
      if (method == _methodStore) {
        decodedBytes = Uint8List.fromList(compSlice);
      } else if (method == _methodDeflate) {
        decodedBytes = Uint8List.fromList(rawInflater.convert(compSlice));
      } else {
        throw FormatException(
          'Unsupported ZIP compression method ($method) for "$normalizedName".',
        );
      }

      if (decodedBytes.length != uncompSize) {
        throw FormatException(
          'Size mismatch while extracting "$normalizedName".',
        );
      }
      final actualCrc = computeCrc32(decodedBytes);
      if (actualCrc != expectedCrc) {
        throw FormatException(
          'CRC-32 integrity check failed for "$normalizedName".',
        );
      }

      files[normalizedName] = decodedBytes;
    }

    return files;
  }
}

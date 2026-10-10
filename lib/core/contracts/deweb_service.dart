/// DeWeb — fetches on-chain websites stored in Massa smart-contract datastores.
///
/// Standard (verified against massalabs/DeWeb server + live buildnet):
/// - file hash   = sha256(path) where path has NO leading slash
///                 ("" or "/" resolves to `index.html`)
/// - chunk count = datastore `\x01FILE` + hash + `\x04CHUNK_NB`  (u32 LE)
/// - chunk i     = datastore `\x01FILE` + hash + `\x03CHUNK` + u32 LE(i)
///                 (64 KiB chunks, concatenated in order)
/// - newer sites also store `\x02LOCATION` + hash -> path (index)
/// - global metadata: `\x06GM` + KEY (e.g. `TITLE`)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;

import '../api/massa_models.dart';
import '../api/massa_rpc.dart';

/// Datastore tags used by DeWeb sites.
abstract final class DeWebKeys {
  /// `\x01FILE` tag.
  static final Uint8List fileTag =
      Uint8List.fromList([1, ...utf8.encode('FILE')]);

  /// `\x02LOCATION` tag.
  static final Uint8List locationTag =
      Uint8List.fromList([2, ...utf8.encode('LOCATION')]);

  /// `\x03CHUNK` tag.
  static final Uint8List chunkTag =
      Uint8List.fromList([3, ...utf8.encode('CHUNK')]);

  /// `\x04CHUNK_NB` tag.
  static final Uint8List chunkNbTag =
      Uint8List.fromList([4, ...utf8.encode('CHUNK_NB')]);

  /// `\x05FM` file metadata tag.
  static final Uint8List fileMetaTag =
      Uint8List.fromList([5, ...utf8.encode('FM')]);

  /// `\x06GM` global metadata tag.
  static final Uint8List globalMetaTag =
      Uint8List.fromList([6, ...utf8.encode('GM')]);

  /// Builds the chunk-count key for a path hash.
  static Uint8List chunkCountKey(Uint8List hash) =>
      Uint8List.fromList([...fileTag, ...hash, ...chunkNbTag]);

  /// Builds the chunk key for a path hash and chunk index.
  static Uint8List chunkKey(Uint8List hash, int index) {
    final b = ByteData(4)..setUint32(0, index, Endian.little);
    return Uint8List.fromList([
      ...fileTag,
      ...hash,
      ...chunkTag,
      ...b.buffer.asUint8List(),
    ]);
  }

  /// Builds the location key for a path hash (new format).
  static Uint8List locationKey(Uint8List hash) =>
      Uint8List.fromList([...locationTag, ...hash]);

  /// Builds a global metadata key.
  static Uint8List globalMetadataKey(String key) =>
      Uint8List.fromList([...globalMetaTag, ...utf8.encode(key)]);
}

/// SHA-256 of a normalized file path (no leading slash).
Uint8List deWebPathHash(String path) {
  final normalized = _normalizePath(path);
  return Uint8List.fromList(c.sha256.convert(utf8.encode(normalized)).bytes);
}

/// Normalizes a URL path to the on-chain file path convention.
String _normalizePath(String path) {
  var p = path;
  while (p.startsWith('/')) {
    p = p.substring(1);
  }
  if (p.isEmpty) return 'index.html';
  return p;
}

/// Candidate paths to try when fetching a file, in order (deduped).
List<String> deWebPathCandidates(String path) {
  final p = _normalizePath(path);
  final candidates = <String>[p];
  if (!p.endsWith('.html')) {
    candidates.add('$p.html');
    candidates.add('$p/index.html');
  }
  candidates.add('index.html');
  return candidates.toSet().toList();
}

/// A fetched on-chain file.
class DeWebFile {
  /// On-chain path.
  final String path;

  /// File bytes.
  final Uint8List bytes;

  /// Guesses the MIME type from the extension.
  String get mimeType => mimeTypeFor(path);

  /// Creates the file.
  const DeWebFile({required this.path, required this.bytes});
}

/// Exception for missing on-chain files/sites.
class DeWebException implements Exception {
  /// Error message.
  final String message;

  /// Creates the exception.
  const DeWebException(this.message);

  @override
  String toString() => 'DeWebException: $message';
}

/// MIME mapping by extension (same spirit as the DeWeb server).
String mimeTypeFor(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
  const map = {
    'html': 'text/html',
    'htm': 'text/html',
    'css': 'text/css',
    'js': 'application/javascript',
    'mjs': 'application/javascript',
    'json': 'application/json',
    'wasm': 'application/wasm',
    'txt': 'text/plain',
    'md': 'text/plain',
    'xml': 'application/xml',
    'svg': 'image/svg+xml',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'ico': 'image/x-icon',
    'avif': 'image/avif',
    'mp3': 'audio/mpeg',
    'ogg': 'audio/ogg',
    'wav': 'audio/wav',
    'mp4': 'video/mp4',
    'webm': 'video/webm',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'ttf': 'font/ttf',
    'otf': 'font/otf',
    'pdf': 'application/pdf',
    'zip': 'application/zip',
  };
  return map[ext] ?? 'application/octet-stream';
}

/// Fetches DeWeb website files from a smart-contract datastore.
class DeWebService {
  /// Max datastore entries per RPC call (node-friendly batch).
  static const int batchSize = 64;

  final MassaRpcClient Function() _clientFactory;

  /// In-memory cache: `scAddress|path` -> bytes.
  final Map<String, Uint8List> _cache = {};

  /// Creates the service.
  DeWebService({required MassaRpcClient Function() clientFactory})
    : _clientFactory = clientFactory;

  void clearCache() => _cache.clear();

  /// Fetches a file from a site, trying path candidates
  /// (`path`, `path.html`, `path/index.html`, `index.html`).
  Future<DeWebFile> fetchFile(String scAddress, String path) async {
    DeWebException? last;
    for (final candidate in deWebPathCandidates(path)) {
      try {
        return await _fetchExact(scAddress, candidate);
      } on DeWebException catch (e) {
        last = e;
      }
    }
    throw last ?? const DeWebException('file not found');
  }

  Future<DeWebFile> _fetchExact(String scAddress, String path) async {
    final cacheKey = '$scAddress|$path';
    final cached = _cache[cacheKey];
    if (cached != null) {
      return DeWebFile(path: path, bytes: cached);
    }

    final hash = deWebPathHash(path);
    final client = _clientFactory();
    try {
      // 1. chunk count
      final countEntry = await client.getDatastoreEntries([
        DatastoreEntryInput(
          address: scAddress,
          key: DeWebKeys.chunkCountKey(hash).toList(),
        ),
      ]);
      final countValue = countEntry.isEmpty ? null : countEntry.first.value;
      if (countValue == null || countValue.length < 4) {
        throw DeWebException('file "$path" not found (no chunk count)');
      }
      final count = ByteData.sublistView(Uint8List.fromList(countValue))
          .getUint32(0, Endian.little);
      if (count == 0 || count > 4096) {
        throw DeWebException('file "$path" has an invalid chunk count');
      }

      // 2. chunks (batched)
      final builder = BytesBuilder();
      for (var start = 0; start < count; start += batchSize) {
        final end = (start + batchSize).clamp(0, count);
        final requests = <DatastoreEntryInput>[
          for (var i = start; i < end; i++)
            DatastoreEntryInput(
              address: scAddress,
              key: DeWebKeys.chunkKey(hash, i).toList(),
            ),
        ];
        final entries = await client.getDatastoreEntries(requests);
        for (final e in entries) {
          if (e.value.isEmpty) {
            throw DeWebException('missing chunk in "$path"');
          }
          builder.add(e.value);
        }
      }
      final bytes = builder.toBytes();
      _cache[cacheKey] = bytes;
      return DeWebFile(path: path, bytes: bytes);
    } finally {
      client.dispose();
    }
  }

  /// Reads a global metadata string (e.g. `TITLE`) from a site; null if absent.
  Future<String?> readGlobalMetadata(String scAddress, String key) async {
    final client = _clientFactory();
    try {
      final entries = await client.getDatastoreEntries([
        DatastoreEntryInput(
          address: scAddress,
          key: DeWebKeys.globalMetadataKey(key).toList(),
        ),
      ]);
      final v = entries.isEmpty ? null : entries.first.value;
      if (v == null || v.isEmpty) return null;
      return utf8.decode(v, allowMalformed: true);
    } on Exception {
      return null;
    } finally {
      client.dispose();
    }
  }

  /// Maps `location -> hash` entries of a site (new DeWeb format).
  /// Returns a map of path -> hash.
  Future<Map<String, Uint8List>> listFileLocations(String scAddress) async {
    final client = _clientFactory();
    try {
      final info = await client.getAddressInfo(scAddress);
      final map = <String, Uint8List>{};
      final tagLen = DeWebKeys.locationTag.length;
      final locationKeys = <List<int>>[];
      for (final k in info.finalDatastoreKeys) {
        if (k.length <= tagLen) continue;
        var isTag = true;
        for (var i = 0; i < tagLen; i++) {
          if (k[i] != DeWebKeys.locationTag[i]) {
            isTag = false;
            break;
          }
        }
        if (isTag) locationKeys.add(k);
      }
      if (locationKeys.isEmpty) return map;
      final entries = await client.getDatastoreEntries([
        for (final k in locationKeys)
          DatastoreEntryInput(address: scAddress, key: k),
      ]);
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        if (e.value.isEmpty) continue;
        final path = utf8.decode(e.value, allowMalformed: true);
        final hash = Uint8List.fromList(locationKeys[i].sublist(tagLen));
        map[path] = hash;
      }
      return map;
    } finally {
      client.dispose();
    }
  }
}

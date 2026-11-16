import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class AppBundleMetadata {
  const AppBundleMetadata({
    required this.packageName,
    required this.appName,
    required this.versionName,
    required this.versionCode,
    required this.apkPaths,
  });

  final String packageName;
  final String appName;
  final String versionName;
  final int versionCode;
  final List<String> apkPaths;
}

/// A single, integrity-checked transfer item containing an Android base APK
/// and all of its configuration splits. The payload is streamed to disk; APK
/// bytes are never accumulated in memory.
class AppBundle {
  AppBundle._();

  static const String extension = '.plazmaapp';
  static const List<int> _magic = [80, 76, 90, 65, 80, 80, 48, 49]; // PLZAPP01
  static const int _maxHeaderBytes = 1024 * 1024;
  static const int _maxApkParts = 100;
  static const int _chunkSize = 64 * 1024;

  static Future<File> create({
    required File output,
    required String packageName,
    required String appName,
    required String versionName,
    required int versionCode,
    required List<File> apks,
  }) async {
    if (!_validPackage(packageName) || apks.isEmpty || apks.length > _maxApkParts) {
      throw const FormatException('The app package metadata or APK list is invalid.');
    }
    final ordered = List<File>.from(apks);
    ordered.sort((a, b) {
      final an = a.uri.pathSegments.last;
      final bn = b.uri.pathSegments.last;
      if (an == 'base.apk') return -1;
      if (bn == 'base.apk') return 1;
      return an.compareTo(bn);
    });
    if (ordered.first.uri.pathSegments.last != 'base.apk') {
      throw const FormatException('The base APK is missing from this app.');
    }

    final entries = <Map<String, Object>>[];
    final names = <String>{};
    for (final apk in ordered) {
      final name = apk.uri.pathSegments.last;
      final stat = await apk.stat();
      if (!_validApkName(name) || !names.add(name) || stat.type != FileSystemEntityType.file) {
        throw FormatException('An APK part is missing or has an unsafe name: $name');
      }
      final size = stat.size;
      if (size <= 0) throw FormatException('APK part $name is empty.');
      final digest = await sha256.bind(apk.openRead()).first;
      entries.add({'name': name, 'size': size, 'sha256': digest.toString()});
    }

    final header = utf8.encode(jsonEncode({
      'format': 1,
      'packageName': packageName,
      'appName': appName,
      'versionName': versionName,
      'versionCode': versionCode,
      'files': entries,
    }));
    if (header.length > _maxHeaderBytes) {
      throw const FormatException('The app bundle metadata is too large.');
    }

    await output.parent.create(recursive: true);
    final sink = output.openWrite();
    try {
      sink.add(_magic);
      final length = ByteData(4)..setUint32(0, header.length, Endian.big);
      sink.add(length.buffer.asUint8List());
      sink.add(header);
      for (final apk in ordered) {
        await for (final chunk in apk.openRead()) {
          sink.add(chunk);
        }
      }
      await sink.flush();
      await sink.close();
      return output;
    } catch (_) {
      await sink.close();
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  static Future<AppBundleMetadata> extract({
    required File bundle,
    required Directory outputDirectory,
  }) async {
    final input = await bundle.open(mode: FileMode.read);
    final partials = <File>[];
    try {
      final length = await input.length();
      if (length < 12) throw const FormatException('The app bundle is truncated.');
      final magic = await input.read(_magic.length);
      if (!_sameBytes(magic, _magic)) {
        throw const FormatException('This is not a supported Plazma S app bundle.');
      }
      final lengthBytes = await input.read(4);
      final headerLength = ByteData.sublistView(Uint8List.fromList(lengthBytes)).getUint32(0, Endian.big);
      if (headerLength == 0 || headerLength > _maxHeaderBytes || 12 + headerLength > length) {
        throw const FormatException('The app bundle header is invalid.');
      }
      final decoded = jsonDecode(utf8.decode(await input.read(headerLength)));
      if (decoded is! Map<String, dynamic> || decoded['format'] != 1) {
        throw const FormatException('The app bundle version is not supported.');
      }
      final packageName = decoded['packageName'];
      final appName = decoded['appName'];
      final versionName = decoded['versionName'];
      final versionCode = decoded['versionCode'];
      final rawFiles = decoded['files'];
      if (packageName is! String || !_validPackage(packageName) ||
          appName is! String || versionName is! String || versionCode is! int ||
          rawFiles is! List || rawFiles.isEmpty || rawFiles.length > _maxApkParts) {
        throw const FormatException('The app bundle metadata is incomplete.');
      }

      final entries = <Map<String, dynamic>>[];
      final names = <String>{};
      var expectedLength = 12 + headerLength;
      for (final raw in rawFiles) {
        if (raw is! Map) throw const FormatException('An APK entry is invalid.');
        final entry = Map<String, dynamic>.from(raw);
        final name = entry['name'];
        final size = entry['size'];
        final digest = entry['sha256'];
        if (name is! String || !_validApkName(name) || !names.add(name) ||
            size is! int || size <= 0 || digest is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
          throw const FormatException('An APK entry has invalid name, size, or checksum.');
        }
        expectedLength += size;
        entries.add(entry);
      }
      if (entries.first['name'] != 'base.apk' || expectedLength != length) {
        throw const FormatException('The app bundle is incomplete or contains unexpected data.');
      }

      await outputDirectory.create(recursive: true);
      final paths = <String>[];
      for (final entry in entries) {
        final name = entry['name'] as String;
        final size = entry['size'] as int;
        final expectedDigest = entry['sha256'] as String;
        final target = File('${outputDirectory.path}${Platform.pathSeparator}$name');
        final partial = File('${target.path}.plazma-partial');
        partials.add(partial);
        final sink = partial.openWrite();
        var remaining = size;
        try {
          while (remaining > 0) {
            final chunk = await input.read(min(_chunkSize, remaining));
            if (chunk.isEmpty) throw const FormatException('An APK payload is truncated.');
            sink.add(chunk);
            remaining -= chunk.length;
          }
          await sink.flush();
          await sink.close();
        } catch (_) {
          await sink.close();
          rethrow;
        }
        final actualDigest = await sha256.bind(partial.openRead()).first;
        if (actualDigest.toString() != expectedDigest) {
          throw FormatException('Integrity check failed for $name.');
        }
        if (await target.exists()) await target.delete();
        await partial.rename(target.path);
        paths.add(target.path);
      }
      if (await input.position() != length) {
        throw const FormatException('The app bundle contains trailing data.');
      }
      return AppBundleMetadata(
        packageName: packageName,
        appName: appName,
        versionName: versionName,
        versionCode: versionCode,
        apkPaths: List.unmodifiable(paths),
      );
    } catch (_) {
      for (final partial in partials) {
        if (await partial.exists()) await partial.delete();
      }
      rethrow;
    } finally {
      await input.close();
    }
  }

  static bool _validPackage(String value) =>
      RegExp(r'^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$').hasMatch(value);

  static bool _validApkName(String value) =>
      value != '.' && value != '..' &&
      RegExp(r'^[A-Za-z0-9._-]+\.apk$', caseSensitive: false).hasMatch(value) &&
      !value.contains('/') && !value.contains(String.fromCharCode(92));

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

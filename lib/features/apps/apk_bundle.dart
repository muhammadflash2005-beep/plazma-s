import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart' show ZipFileEncoder;
import 'package:crypto/crypto.dart';

/// Stores one Android app's base APK and split APKs in a single, verifiable
/// ZIP-compatible .apks transfer item. APK payloads are stored, not recompressed.
class ApkBundle {
  ApkBundle._();

  static const String manifestName = 'plazma_manifest.json';
  static const String formatName = 'plazma-apk-set';
  static const int maxFiles = 64;
  static const int maxTotalBytes = 32 * 1024 * 1024 * 1024;

  static bool isBundlePath(String path) => path.toLowerCase().endsWith('.apks');
  static bool isApkPath(String path) => path.toLowerCase().endsWith('.apk');

  static bool isValidPackageName(String value) =>
      RegExp(r'^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$').hasMatch(value);

  static bool _isAllowedApkName(String value) =>
      value == 'base.apk' ||
      RegExp(r'^split_[A-Za-z0-9_.-]+\.apk$', caseSensitive: false).hasMatch(value);

  static void _validatePackageName(String packageName) {
    if (!isValidPackageName(packageName)) {
      throw FormatException('Invalid Android package name: $packageName');
    }
  }

  static Future<File> create({
    required String packageName,
    required List<File> apkFiles,
    required Directory outputDirectory,
  }) async {
    _validatePackageName(packageName);
    if (apkFiles.isEmpty || apkFiles.length > maxFiles) {
      throw StateError('An APK bundle must contain between one and $maxFiles APK files.');
    }

    final ordered = List<File>.of(apkFiles);
    ordered.sort((a, b) {
      final aName = a.uri.pathSegments.last;
      final bName = b.uri.pathSegments.last;
      if (aName == 'base.apk') return -1;
      if (bName == 'base.apk') return 1;
      return aName.compareTo(bName);
    });
    if (ordered.first.uri.pathSegments.last != 'base.apk') {
      throw StateError('The base APK is missing from the app bundle.');
    }

    final names = <String>{};
    final manifestFiles = <Map<String, Object>>[];
    var totalBytes = 0;
    for (final file in ordered) {
      final name = file.uri.pathSegments.last;
      if (!_isAllowedApkName(name) || !names.add(name)) {
        throw FormatException('Unexpected or duplicate APK filename: $name');
      }
      if (!await file.exists()) throw FileSystemException('APK file is missing', file.path);
      final size = await file.length();
      if (size <= 0) throw FileSystemException('APK file is empty', file.path);
      totalBytes += size;
      if (totalBytes > maxTotalBytes) {
        throw StateError('The selected APK set is larger than the supported bundle limit.');
      }
      final digest = await sha256.bind(file.openRead()).first;
      manifestFiles.add({
        'name': name,
        'size': size,
        'sha256': digest.toString(),
      });
    }

    await outputDirectory.create(recursive: true);
    final bundle = File(
      '${outputDirectory.path}${Platform.pathSeparator}$packageName.apks',
    );
    final manifestFile = File(
      '${outputDirectory.path}${Platform.pathSeparator}.$packageName.manifest.tmp',
    );
    await manifestFile.writeAsString(
      jsonEncode({
        'format': formatName,
        'version': 1,
        'packageName': packageName,
        'files': manifestFiles,
      }),
      flush: true,
    );
    if (await bundle.exists()) await bundle.delete();

    final encoder = ZipFileEncoder();
    encoder.create(bundle.path, level: ZipFileEncoder.store);
    try {
      for (var index = 0; index < ordered.length; index++) {
        await encoder.addFile(
          ordered[index],
          manifestFiles[index]['name']! as String,
          ZipFileEncoder.store,
        );
      }
      await encoder.addFile(manifestFile, manifestName, ZipFileEncoder.store);
      await encoder.close();
      return bundle;
    } catch (_) {
      try {
        await encoder.close();
      } catch (_) {}
      if (await bundle.exists()) await bundle.delete();
      rethrow;
    } finally {
      if (await manifestFile.exists()) await manifestFile.delete();
    }
  }

  static Future<List<File>> extract({
    required File bundle,
    required String expectedPackageName,
    required Directory destinationDirectory,
  }) async {
    _validatePackageName(expectedPackageName);
    if (!await bundle.exists()) {
      throw FileSystemException('The APK bundle is missing', bundle.path);
    }

    final input = InputFileStream(bundle.path);
    Archive? decoded;
    Directory? staging;
    try {
      decoded = ZipDecoder().decodeStream(input, verify: true);
      final entries = decoded.files;
      if (entries.isEmpty || entries.length > maxFiles + 1) {
        throw FormatException('The APK bundle has an invalid number of entries.');
      }
      if (entries.any((entry) => !entry.isFile || entry.isDirectory || entry.isSymbolicLink)) {
        throw FormatException('The APK bundle contains an unsupported ZIP entry.');
      }

      final manifests = entries.where((entry) => entry.name == manifestName).toList();
      if (manifests.length != 1) {
        throw FormatException('The APK bundle manifest is missing or duplicated.');
      }
      final manifestBytes = manifests.single.readBytes();
      if (manifestBytes == null) throw FormatException('The APK bundle manifest is empty.');
      final decodedManifest = jsonDecode(utf8.decode(manifestBytes));
      if (decodedManifest is! Map) throw FormatException('The APK bundle manifest is invalid.');
      final manifest = Map<String, dynamic>.from(decodedManifest);
      if (manifest['format'] != formatName ||
          manifest['version'] != 1 ||
          manifest['packageName'] != expectedPackageName) {
        throw FormatException('The APK bundle belongs to a different app or format.');
      }

      final rawFiles = manifest['files'];
      if (rawFiles is! List || rawFiles.isEmpty || rawFiles.length > maxFiles) {
        throw FormatException('The APK bundle file list is invalid.');
      }
      final declared = <String, Map<String, dynamic>>{};
      var totalBytes = 0;
      for (final rawFile in rawFiles) {
        if (rawFile is! Map) throw FormatException('An APK bundle entry is invalid.');
        final item = Map<String, dynamic>.from(rawFile);
        final name = item['name'];
        final size = item['size'];
        final digest = item['sha256'];
        if (name is! String || !_isAllowedApkName(name) || declared.containsKey(name)) {
          throw FormatException('The APK bundle contains an unsafe or duplicate filename.');
        }
        if (size is! int || size <= 0 || digest is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
          throw FormatException('The APK bundle contains invalid size or checksum metadata.');
        }
        totalBytes += size;
        if (totalBytes > maxTotalBytes) {
          throw FormatException('The APK bundle exceeds the supported extraction limit.');
        }
        declared[name] = item;
      }
      if (rawFiles.first is! Map || rawFiles.first['name'] != 'base.apk') {
        throw FormatException('The base APK must be the first item in the bundle.');
      }
      if (!declared.containsKey('base.apk')) {
        throw FormatException('The base APK is missing from the bundle.');
      }

      final apkEntries = entries.where((entry) => entry.name != manifestName).toList();
      if (apkEntries.length != declared.length ||
          apkEntries.any((entry) => !declared.containsKey(entry.name))) {
        throw FormatException('The APK bundle entries do not match its manifest.');
      }
      for (final entry in apkEntries) {
        final expected = declared[entry.name]!;
        if (entry.isCompressed || entry.size != expected['size']) {
          throw FormatException('The APK bundle entry size or compression is invalid: ${entry.name}');
        }
      }

      await destinationDirectory.create(recursive: true);
      staging = Directory(
        '${destinationDirectory.path}${Platform.pathSeparator}.apk-bundle-staging',
      );
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);

      final extracted = <File>[];
      for (final rawFile in rawFiles) {
        final item = Map<String, dynamic>.from(rawFile as Map);
        final name = item['name'] as String;
        final entry = apkEntries.singleWhere((value) => value.name == name);
        final outputFile = File('${staging.path}${Platform.pathSeparator}$name');
        final output = OutputFileStream(outputFile.path);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
        final actualSize = await outputFile.length();
        final actualDigest = await sha256.bind(outputFile.openRead()).first;
        if (actualSize != item['size'] || actualDigest.toString() != item['sha256']) {
          throw FormatException('APK checksum verification failed for $name.');
        }
        extracted.add(outputFile);
      }

      await for (final existing in destinationDirectory.list(followLinks: false)) {
        if (existing is File && _isAllowedApkName(existing.uri.pathSegments.last)) {
          await existing.delete();
        }
      }
      final result = <File>[];
      for (final file in extracted) {
        final target = File(
          '${destinationDirectory.path}${Platform.pathSeparator}${file.uri.pathSegments.last}',
        );
        result.add(await file.rename(target.path));
      }
      await staging.delete(recursive: true);
      staging = null;
      return result;
    } finally {
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
      if (decoded != null) {
        try {
          await decoded.clear();
        } catch (_) {}
      }
      await input.close();
    }
  }
}

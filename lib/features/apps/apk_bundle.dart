import 'package:flutter/services.dart';

/// Native Android app-package bundling and installation.
class ApkBundle {
  ApkBundle._();

  static const MethodChannel _channel = MethodChannel('plazma/apk_bundle');

  /// Exports an installed app's base APK and every split into one .apks file.
  static Future<String> bundle(String packageName) async {
    if (packageName.trim().isEmpty) {
      throw ArgumentError.value(packageName, 'packageName', 'Cannot be empty');
    }
    final path = await _channel.invokeMethod<String>(
      'bundle',
      <String, Object>{'packageName': packageName},
    );
    if (path == null || path.isEmpty) {
      throw StateError('Android did not return the APK bundle path.');
    }
    return path;
  }

  /// Installs a standalone APK or an APK set archive using PackageInstaller.
  static Future<void> install(String path) async {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'Cannot be empty');
    }
    await _channel.invokeMethod<void>(
      'install',
      <String, Object>{'path': path},
    );
  }

  static bool isBundle(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.apks') || lower.endsWith('.xapk');
  }
}

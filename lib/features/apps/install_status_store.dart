import 'package:flutter/foundation.dart';

/// Broadcasts confirmed Android PackageInstaller results to app/history UI.
class InstallStatusStore {
  InstallStatusStore._();

  static final ValueNotifier<Map<String, bool>> installed =
      ValueNotifier<Map<String, bool>>(<String, bool>{});

  static void report(String packageName, bool success) {
    if (packageName.trim().isEmpty) return;
    installed.value = <String, bool>{
      ...installed.value,
      packageName: success,
    };
  }

  static bool isInstalled(String packageName) =>
      installed.value[packageName] == true;
}

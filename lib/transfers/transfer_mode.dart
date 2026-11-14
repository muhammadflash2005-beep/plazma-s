enum TransferMode {
  pcToPc,
  androidToAndroid,
  pcToAndroid;

  String get label => switch (this) {
        TransferMode.pcToPc => 'PC to PC',
        TransferMode.androidToAndroid => 'Android to Android',
        TransferMode.pcToAndroid => 'PC to Android',
      };

  String get description => switch (this) {
        TransferMode.pcToPc => 'Computer-to-computer transfers',
        TransferMode.androidToAndroid => 'Android phone and tablet transfers',
        TransferMode.pcToAndroid => 'Computer and Android transfers in either direction',
      };

  bool supportsLocal(String platform) {
    final android = _isAndroid(platform);
    final pc = _isPc(platform);
    return switch (this) {
      TransferMode.pcToPc => pc,
      TransferMode.androidToAndroid => android,
      TransferMode.pcToAndroid => android || pc,
    };
  }

  bool matches(String localPlatform, String remotePlatform) {
    if (!supportsLocal(localPlatform)) return false;
    final localAndroid = _isAndroid(localPlatform);
    final remoteAndroid = _isAndroid(remotePlatform);
    final localPc = _isPc(localPlatform);
    final remotePc = _isPc(remotePlatform);
    return switch (this) {
      TransferMode.pcToPc => localPc && remotePc,
      TransferMode.androidToAndroid => localAndroid && remoteAndroid,
      TransferMode.pcToAndroid =>
        (localPc && remoteAndroid) || (localAndroid && remotePc),
    };
  }

  static bool _isAndroid(String value) =>
      value.toLowerCase().contains('android');

  static bool _isPc(String value) {
    final platform = value.toLowerCase();
    return platform.contains('windows') ||
        platform.contains('macos') ||
        platform.contains('linux') ||
        platform == 'desktop';
  }
}

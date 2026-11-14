import 'package:flutter/services.dart';

class HotspotCredentials {
  const HotspotCredentials({required this.ssid, required this.password});

  final String ssid;
  final String password;
}

class AndroidHotspotService {
  static const _channel = MethodChannel('com.plazma.s/hotspot');

  Future<HotspotCredentials> startHotspot() async {
    final result = await _channel.invokeMapMethod<String, Object?>('startHotspot');
    if (result == null) {
      throw PlatformException(code: 'EMPTY_RESULT', message: 'Android did not return hotspot details.');
    }
    return HotspotCredentials(
      ssid: result['ssid'] as String? ?? '',
      password: result['password'] as String? ?? '',
    );
  }

  Future<void> stopHotspot() => _channel.invokeMethod<void>('stopHotspot');

  Future<void> openWifiSettings() => _channel.invokeMethod<void>('openWifiSettings');
}

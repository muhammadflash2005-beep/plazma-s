import 'package:posthog_flutter/posthog_flutter.dart';

/// Privacy-conscious analytics for Plazma S.
/// No file names, local paths, package identifiers, or file contents are sent.
class PlazmaAnalytics {
  PlazmaAnalytics._();

  static const String _projectToken = String.fromEnvironment('POSTHOG_PROJECT_TOKEN');
  static const String _host = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://us.i.posthog.com',
  );

  static bool _ready = false;

  static Future<void> initialize() async {
    if (_projectToken.trim().isEmpty) return;
    try {
      final config = PostHogConfig(_projectToken)
        ..host = _host
        ..captureApplicationLifecycleEvents = true
        ..debug = false;
      await Posthog().setup(config);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  static Future<void> capture(String eventName, [Map<String, Object>? properties]) async {
    if (!_ready) return;
    try {
      await Posthog().capture(eventName: eventName, properties: properties);
    } catch (_) {
      // Analytics failures must never affect local transfer functionality.
    }
  }
}

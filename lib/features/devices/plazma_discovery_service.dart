import 'dart:async';
import 'dart:math';

import 'package:bonsoir/bonsoir.dart';

class NearbyPlazmaDevice {
  const NearbyPlazmaDevice({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.platform,
  });

  final String id;
  final String name;
  final String address;
  final int port;
  final String platform;
}

class PlazmaDiscoveryService {
  static const serviceType = '_plazmas._tcp';
  static const advertisedPort = 45454;

  final Map<String, NearbyPlazmaDevice> _devices = {};
  final StreamController<List<NearbyPlazmaDevice>> _controller =
      StreamController<List<NearbyPlazmaDevice>>.broadcast();

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  String? _localDeviceId;

  Stream<List<NearbyPlazmaDevice>> get devices => _controller.stream;

  Future<void> start({required String deviceName, required String platform}) async {
    if (_discovery != null) return;
    _localDeviceId = _randomId();
    final service = BonsoirService(
      name: deviceName,
      type: serviceType,
      port: advertisedPort,
      attributes: {
        'app': 'plazma-s',
        'protocol': '1',
        'deviceId': _localDeviceId!,
        'platform': platform,
      },
    );

    final broadcast = BonsoirBroadcast(service: service);
    await broadcast.initialize();
    await broadcast.start();
    _broadcast = broadcast;

    final discovery = BonsoirDiscovery(type: serviceType);
    await discovery.initialize();
    _discovery = discovery;
    _subscription = discovery.eventStream?.listen((event) {
      if (event is BonsoirDiscoveryServiceFoundEvent) {
        final service = event.service;
        unawaited(service.resolve(discovery.serviceResolver));
      } else if (event is BonsoirDiscoveryServiceResolvedEvent) {
        final service = event.service;
        final attributes = service.attributes;
        if (attributes['app'] != 'plazma-s') return;
        final id = attributes['deviceId'] ?? '${service.name}:${service.port}';
        if (id == _localDeviceId) return;
        final addresses = service.hostAddresses;
        final address = addresses.isNotEmpty ? addresses.first : service.hostAddress;
        if (address == null || address.isEmpty) return;
        _devices[id] = NearbyPlazmaDevice(
          id: id,
          name: service.name,
          address: address,
          port: service.port,
          platform: attributes['platform'] ?? 'Unknown',
        );
        _emit();
      } else if (event is BonsoirDiscoveryServiceLostEvent) {
        final service = event.service;
        _devices.removeWhere((_, device) =>
            device.name == service.name && device.port == service.port);
        _emit();
      }
    });
    await discovery.start();
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null && !discovery.isStopped) await discovery.stop();
    final broadcast = _broadcast;
    _broadcast = null;
    if (broadcast != null && !broadcast.isStopped) await broadcast.stop();
    _devices.clear();
    _emit();
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  void _emit() {
    final list = _devices.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!_controller.isClosed) _controller.add(list);
  }

  String _randomId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join();
  }
}

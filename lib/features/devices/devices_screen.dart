import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'plazma_discovery_service.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late final PlazmaDiscoveryService _discovery;
  StreamSubscription<List<NearbyPlazmaDevice>>? _subscription;
  List<NearbyPlazmaDevice> _devices = [];
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _discovery = PlazmaDiscoveryService();
    _subscription = _discovery.devices.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    });
    _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    if (kIsWeb) {
      setState(() => _error = 'Nearby-device discovery requires the native app.');
      return;
    }
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      await _discovery.start(
        deviceName: 'Plazma S device',
        platform: Platform.operatingSystem,
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not start local discovery: $error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    unawaited(_discovery.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Devices', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Text('Find other Plazma S devices advertising on your local network.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 18),
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(_scanning ? Icons.wifi_find_rounded : Icons.wifi_rounded,
              color: theme.colorScheme.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_scanning ? 'Starting discovery…' : 'Local network discovery',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text('${_devices.length} nearby Plazma S device(s) found',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          ])),
          IconButton(
            onPressed: _scanning ? null : _startDiscovery,
            tooltip: 'Restart scan',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ]),
      )),
      if (_error != null)
        Card(child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        )),
      const SizedBox(height: 12),
      if (_devices.isEmpty)
        Card(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 18),
          child: Center(child: Column(children: [
            Icon(Icons.devices_other_rounded, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            const Text('No nearby devices yet', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Open Plazma S on another device connected to the same Wi-Fi or hotspot.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ])),
        ))
      else
        ..._devices.map((device) => Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                device.platform.toLowerCase().contains('android')
                    ? Icons.phone_android_rounded
                    : Icons.computer_rounded,
                color: theme.colorScheme.primary,
              ),
            ),
            title: Text(device.name),
            subtitle: Text('${device.platform} · ${device.address}:${device.port}'),
            trailing: const Icon(Icons.wifi_rounded),
          ),
        )),
      const SizedBox(height: 14),
      Card(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.shield_outlined),
            SizedBox(width: 10),
            Expanded(child: Text(
              'Discovery uses local mDNS service announcements. Device connection, identity verification and room authentication are separate steps and are not enabled by this discovery screen yet.',
              style: TextStyle(fontSize: 12, height: 1.45),
            )),
          ]),
        ),
      ),
    ]);
  }
}

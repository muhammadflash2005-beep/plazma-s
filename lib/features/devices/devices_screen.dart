// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../../network/android_hotspot_service.dart';
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
  final _hotspot = AndroidHotspotService();
  HotspotCredentials? _hotspotCredentials;
  bool _startingHotspot = false;

  @override
  void initState() {
    super.initState();
    _discovery = PlazmaDiscoveryService();
    _subscription = _discovery.devices.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    });
    _startDiscovery();
  }

  Future<void> _createHotspot() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      setState(() => _error = 'Creating a Plazma hotspot is currently supported on Android only.');
      return;
    }
    setState(() { _startingHotspot = true; _error = null; });
    try {
      final credentials = await _hotspot.startHotspot();
      if (mounted) setState(() => _hotspotCredentials = credentials);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Could not start the hotspot.');
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not start the hotspot: $error');
    } finally {
      if (mounted) setState(() => _startingHotspot = false);
    }
  }

  Future<void> _stopHotspot() async {
    try {
      await _hotspot.stopHotspot();
      if (mounted) setState(() => _hotspotCredentials = null);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not stop hotspot: $error');
    }
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
        publish: true,
        deviceName: 'Plazma S device',
        platform: switch (defaultTargetPlatform) {
          TargetPlatform.android => 'Android',
          TargetPlatform.iOS => 'iOS',
          TargetPlatform.windows => 'Windows',
          TargetPlatform.macOS => 'macOS',
          TargetPlatform.linux => 'Linux',
          TargetPlatform.fuchsia => 'Fuchsia',
        },
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not start local discovery: $error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Widget _hotspotCard(ThemeData theme) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.wifi_tethering_rounded, color: theme.colorScheme.primary, size: 26),
              const SizedBox(width: 10),
              const Expanded(child: Text('Connect without a router', style: TextStyle(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 6),
            Text('Create a temporary Wi-Fi hotspot on this phone, then connect the other device to it. Internet access is not required.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 12),
            if (_hotspotCredentials == null)
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: _startingHotspot ? null : _createHotspot,
                  icon: _startingHotspot
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering_rounded),
                  label: Text(_startingHotspot ? 'Starting hotspot…' : 'Create hotspot'),
                ),
                OutlinedButton.icon(
                  onPressed: defaultTargetPlatform == TargetPlatform.android
                      ? _hotspot.openWifiSettings
                      : null,
                  icon: const Icon(Icons.wifi_rounded),
                  label: const Text('Join hotspot'),
                ),
              ])
            else ...[
              SelectableText('Network: ${_hotspotCredentials!.ssid}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              SelectableText('Password: ${_hotspotCredentials!.password}'),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: _hotspot.openWifiSettings, icon: const Icon(Icons.settings_rounded), label: const Text('Wi-Fi settings')),
                TextButton(onPressed: _stopHotspot, child: const Text('Stop hotspot')),
              ]),
            ],
          ]),
        ),
      );

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
      _hotspotCard(theme),
      const SizedBox(height: 14),
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

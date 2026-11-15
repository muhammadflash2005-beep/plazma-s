// The updater uses Flutter's Material widgets across supported Flutter versions.
// Flutter 3.50 marks this import deprecated in favor of a newer package migration.
// Keep the stable Flutter Material API until the app migrates consistently.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateCard extends StatefulWidget {
  const AppUpdateCard({super.key});
  @override
  State<AppUpdateCard> createState() => _AppUpdateCardState();
}

class _AppUpdateCardState extends State<AppUpdateCard> {
  static const _repository = 'muhammadflash2005-beep/plazma-s';
  static const _installer = MethodChannel('com.plazma.s/updater');
  bool _busy = false;
  bool _available = false;
  String _status = 'Check GitHub for the latest Plazma S release.';
  String? _latestVersion, _releaseNotes, _apkUrl, _checksumUrl, _currentVersion, _error;
  File? _downloadedApk;
  double? _progress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    setState(() { _busy = true; _error = null; _progress = null; _status = 'Checking for updates…'; });
    try {
      final package = await PackageInfo.fromPlatform();
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_repository/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'Plazma-S-Updater'},
      ).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) throw Exception('GitHub returned HTTP ${response.statusCode}. Try again later.');
      final release = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = (release['tag_name'] as String? ?? '').trim();
      final latest = tag.startsWith('v') ? tag.substring(1) : tag;
      if (latest.isEmpty) throw Exception('The latest release has no version tag.');
      final assets = (release['assets'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
      final apk = assets.where((a) => (a['name'] as String? ?? '').toLowerCase() == 'app-release.apk').firstOrNull;
      final checksum = assets.where((a) => (a['name'] as String? ?? '').toLowerCase() == 'sha256sums.txt').firstOrNull;
      if (apk == null || checksum == null) throw Exception('The release is missing its APK or SHA256 checksum.');
      final current = package.version;
      final hasUpdate = _compareVersions(latest, current) > 0;
      if (!mounted) return;
      setState(() {
        _currentVersion = current; _latestVersion = latest; _available = hasUpdate;
        _apkUrl = apk['browser_download_url'] as String?;
        _checksumUrl = checksum['browser_download_url'] as String?;
        _releaseNotes = (release['body'] as String? ?? '').trim();
        _status = hasUpdate ? 'Version $latest is available.' : 'You are using the latest version ($current).';
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      final isNetworkError = error is SocketException ||
          error is HttpException ||
          error is HandshakeException ||
          error is TimeoutException ||
          error is http.ClientException;
      setState(() {
        _busy = false;
        _progress = null;
        _error = isNetworkError ? null : error.toString().replaceFirst('Exception: ', '');
        _status = isNetworkError
            ? 'Connect to the internet to check for updates.'
            : 'Could not check for updates.';
      });
    }
  }

  int _compareVersions(String a, String b) {
    List<int> parts(String value) {
      final match = RegExp(r'^\s*v?(\d+(?:\.\d+){0,3})').firstMatch(value);
      if (match == null) return [0];
      return match.group(1)!.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    }
    final left = parts(a), right = parts(b);
    for (var i = 0; i < 4; i++) {
      final x = i < left.length ? left[i] : 0, y = i < right.length ? right[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  Future<void> _downloadAndInstall() async {
    if (_downloadedApk != null) { await _installDownloadedApk(); return; }
    final apkUrl = _apkUrl, checksumUrl = _checksumUrl;
    if (apkUrl == null || checksumUrl == null) return;
    setState(() { _busy = true; _error = null; _progress = 0; _status = 'Downloading update…'; });
    final client = http.Client();
    try {
      final checksumResponse = await client.get(Uri.parse(checksumUrl)).timeout(const Duration(seconds: 25));
      if (checksumResponse.statusCode != 200) throw Exception('Could not retrieve the release checksum.');
      final checksumLine = checksumResponse.body.split('\n').map((line) => line.trim())
          .firstWhere((line) => line.endsWith('app-release.apk'), orElse: () => '');
      final expectedHash = checksumLine.split(RegExp(r'\s+')).first.toLowerCase();
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash)) throw Exception('The release checksum file is invalid.');
      final request = http.Request('GET', Uri.parse(apkUrl));
      request.headers['User-Agent'] = 'Plazma-S-Updater';
      final streamed = await client.send(request).timeout(const Duration(seconds: 60));
      if (streamed.statusCode != 200) throw Exception('APK download failed with HTTP ${streamed.statusCode}.');
      final total = streamed.contentLength ?? 0;
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/plazma-s-update.apk');
      final sink = file.openWrite();
      final digestSink = AccumulatorSink<Digest>();
      final input = sha256.startChunkedConversion(digestSink);
      var received = 0;
      await for (final chunk in streamed.stream) {
        sink.add(chunk); input.add(chunk); received += chunk.length;
        if (mounted && total > 0) setState(() => _progress = received / total);
      }
      input.close(); await sink.flush(); await sink.close();
      if (digestSink.events.single.toString() != expectedHash) {
        await file.delete();
        throw Exception('The downloaded APK failed its SHA256 integrity check.');
      }
      if (!mounted) return;
      setState(() { _downloadedApk = file; _busy = false; _progress = 1; _status = 'Download verified. Ready to install.'; });
      await _installDownloadedApk();
    } catch (error) {
      if (!mounted) return;
      setState(() { _busy = false; _error = error.toString().replaceFirst('Exception: ', ''); _status = 'Update could not be downloaded.'; });
    } finally { client.close(); }
  }

  Future<void> _installDownloadedApk() async {
    final file = _downloadedApk;
    if (file == null) return;
    if (!Platform.isAndroid) { setState(() => _status = 'APK installation is available on Android only.'); return; }
    try {
      await _installer.invokeMethod<void>('installApk', {'path': file.path});
      if (!mounted) return;
      setState(() => _status = 'Android opened the package installer. Follow its prompts to update Plazma S.');
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message ?? 'Android could not open the installer.';
        _status = error.code == 'INSTALL_PERMISSION_REQUIRED'
            ? 'Allow Plazma S to install updates, return here, then tap Install update again.'
            : 'Could not start the Android installer.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = error.toString(); _status = 'Could not start the Android installer.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.system_update_rounded, color: theme.colorScheme.primary, size: 26),
          const SizedBox(width: 10),
          Expanded(child: Text('App updates', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
          if (_busy) const Icon(Icons.sync_rounded, size: 20),
        ]),
        const SizedBox(height: 8),
        Text(_status, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        if (_currentVersion != null) ...[
          const SizedBox(height: 4),
          Text('Installed: $_currentVersion${_latestVersion == null ? '' : '  ·  Latest: $_latestVersion'}', style: theme.textTheme.bodySmall),
        ],
        if (_progress != null) ...[
          const SizedBox(height: 12), LinearProgressIndicator(value: _progress),
          const SizedBox(height: 4), Text('${(_progress! * 100).round()}%', style: theme.textTheme.bodySmall),
        ],
        if (_releaseNotes != null && _releaseNotes!.isNotEmpty && _available) ...[
          const SizedBox(height: 10),
          Text('Release notes', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4), Text(_releaseNotes!, maxLines: 5, overflow: TextOverflow.ellipsis),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8), Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: _busy ? null : _checkForUpdates, icon: const Icon(Icons.refresh_rounded), label: const Text('Check for updates')),
          if (_available) FilledButton.icon(
            onPressed: _busy ? null : _downloadAndInstall,
            icon: const Icon(Icons.download_rounded),
            label: Text(_downloadedApk == null ? 'Download & install' : 'Install update'),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Updates come from official Plazma S GitHub releases and are verified before Android opens the installer. Android will ask you to confirm installation.', style: theme.textTheme.bodySmall),
      ]),
    ));
  }
}

// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../../transfers/transfer_mode.dart';

class FilesScreen extends StatelessWidget {
  const FilesScreen({this.transferMode, this.initialPaths = const [], this.initialAction, super.key});

  final List<String> initialPaths;

  final TransferMode? transferMode;
  final String? initialAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            initialAction == 'create'
                ? 'Create a room: choose content in the installed Plazma S app, then share the QR code or room code with up to seven devices. This Windows web preview shares the same navigation and layout; native LAN transfer requires the installed desktop app.'
                : initialAction == 'join'
                    ? 'Join a room: scan the host QR code on Android or enter its room code in the installed Windows desktop app. All devices must use the same Wi-Fi. This web preview is UI-compatible, but browser-based LAN transfer is not enabled.'
                    : transferMode == null
                        ? 'File transfers are available in the installed Plazma S app. This web preview keeps the same categories and navigation.'
                        : '${transferMode!.label} is selected. Install Plazma S on each device to transfer directly over the same local network.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

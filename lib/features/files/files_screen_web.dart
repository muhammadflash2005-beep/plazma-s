// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../../transfers/transfer_mode.dart';

class FilesScreen extends StatelessWidget {
  const FilesScreen({this.transferMode, super.key});

  final TransferMode? transferMode;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            transferMode == null
                ? 'File transfers are available in the native Plazma S app. '
                    'Open Plazma S on Android or desktop to send files over your local network.'
                : '${transferMode!.label} is selected. '
                    'Install the native Plazma S app on the devices to discover each other and transfer files over your local network.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

import 'package:flutter/material.dart';

class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'File transfers are available in the native Plazma S app. '
            'Open Plazma S on Android or desktop to send files over your local network.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

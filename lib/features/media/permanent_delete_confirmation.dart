// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';

Future<bool> confirmPermanentDelete(
  BuildContext context, {
  required String itemDescription,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _PermanentDeleteDialog(itemDescription: itemDescription),
      ) ??
      false;
}

class _PermanentDeleteDialog extends StatefulWidget {
  const _PermanentDeleteDialog({required this.itemDescription});
  final String itemDescription;

  @override
  State<_PermanentDeleteDialog> createState() => _PermanentDeleteDialogState();
}

class _PermanentDeleteDialogState extends State<_PermanentDeleteDialog> {
  Timer? _timer;
  int _remaining = 5;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining = (_remaining - 1).clamp(0, 5).toInt());
      if (_remaining == 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red),
        title: const Text('Permanently delete?'),
        content: Text(
          'This will permanently erase ${widget.itemDescription}. '
          'There is no Trash or Recycle Bin. This cannot be undone. '
          '${_remaining > 0 ? 'Please wait $_remaining seconds before confirming.' : 'Confirm only if you are sure.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: _remaining > 0 ? null : () => Navigator.of(context).pop(true),
            child: Text(_remaining > 0 ? 'Delete in $_remaining…' : 'Delete permanently'),
          ),
        ],
      );
}

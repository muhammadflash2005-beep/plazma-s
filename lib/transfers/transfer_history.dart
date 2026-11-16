import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TransferHistoryEntry {
  const TransferHistoryEntry({
    required this.id,
    required this.name,
    required this.type,
    required this.direction,
    required this.path,
    this.installPath,
    required this.bytes,
    required this.peer,
    required this.completedAt,
  });

  final String id;
  final String name;
  final String type; // file or app
  final String direction; // sent or received
  final String path;
  final String? installPath;
  final int bytes;
  final String peer;
  final DateTime completedAt;

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'direction': direction,
        'path': path,
        'installPath': installPath,
        'bytes': bytes,
        'peer': peer,
        'completedAt': completedAt.toIso8601String(),
      };

  factory TransferHistoryEntry.fromJson(Map<String, dynamic> json) =>
      TransferHistoryEntry(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Unknown item',
        type: json['type'] as String? ?? 'file',
        direction: json['direction'] as String? ?? 'received',
        path: json['path'] as String? ?? '',
        installPath: json['installPath'] as String?,
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        peer: json['peer'] as String? ?? 'Nearby device',
        completedAt: DateTime.tryParse(json['completedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class TransferHistoryStore {
  static const _key = 'plazma_transfer_history_v1';
  static const _maxEntries = 300;

  static Future<List<TransferHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => TransferHistoryEntry.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList()
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    } catch (_) {
      return [];
    }
  }

  static Future<void> add({
    required String name,
    required String type,
    required String direction,
    required String path,
    String? installPath,
    required int bytes,
    required String peer,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await load();
    final now = DateTime.now();
    entries.insert(
      0,
      TransferHistoryEntry(
        id: now.microsecondsSinceEpoch.toString(),
        name: name,
        type: type,
        direction: direction,
        path: path,
        installPath: installPath,
        bytes: bytes,
        peer: peer,
        completedAt: now,
      ),
    );
    final limited = entries.take(_maxEntries).map((entry) => entry.toJson()).toList();
    await prefs.setString(_key, jsonEncode(limited));
  }

  static Future<void> clear({String? direction}) async {
    final prefs = await SharedPreferences.getInstance();
    if (direction == null) {
      await prefs.remove(_key);
      return;
    }
    final entries = await load();
    entries.removeWhere((entry) => entry.direction == direction);
    await prefs.setString(
      _key,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }
}

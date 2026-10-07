import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CountEntry {
  CountEntry({
    required this.time,
    required this.source,
    required this.nIn,
    required this.nOut,
  });

  final DateTime time;
  final String source;
  final int nIn;
  final int nOut;

  int get balance => nIn - nOut;

  Map<String, dynamic> toJson() => {
        't': time.millisecondsSinceEpoch,
        's': source,
        'in': nIn,
        'out': nOut,
      };

  static CountEntry fromJson(Map<String, dynamic> j) => CountEntry(
        time: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
        source: j['s'] as String,
        nIn: j['in'] as int,
        nOut: j['out'] as int,
      );
}

/// Keeps the last 7 days of counts in local storage (no cloud needed).
class HistoryStore {
  static const _key = 'history_v1';
  static const keepDays = 7;

  Future<List<CountEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final cutoff = DateTime.now().subtract(const Duration(days: keepDays));
    final list = (jsonDecode(raw) as List)
        .map((e) => CountEntry.fromJson(e as Map<String, dynamic>))
        .where((e) => e.time.isAfter(cutoff))
        .toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return list;
  }

  Future<void> add(CountEntry entry) async {
    final all = await load();
    all.add(entry);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(all.map((e) => e.toJson()).toList()));
  }
}

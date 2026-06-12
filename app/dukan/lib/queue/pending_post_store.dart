// Durable storage for the offline posting queue. Backed by
// SharedPreferences as one JSON-encoded list — same pattern as the
// TodaySummaryCache. Fine for our scale (a typical queue has < 20
// items; offline periods drain quickly when connectivity returns).
//
// Read-all / write-all on every mutation. Optimised for correctness
// rather than per-op throughput.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:dukan/queue/pending_post.dart';

class PendingPostStore {
  PendingPostStore({String key = _defaultKey}) : _key = key;

  static const String _defaultKey = 'pending_posts_v1';

  final String _key;

  /// Load the queue. Returns an empty list when the key is missing
  /// or the stored payload is corrupt (we drop the corrupt blob
  /// silently — it can only have come from a now-impossible app
  /// state, and we want to recover, not crash).
  Future<List<PendingPost>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const <PendingPost>[];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((m) => PendingPost.fromJson(Map<String, dynamic>.from(m)))
          .toList(growable: false);
    } catch (_) {
      await prefs.remove(_key);
      return const <PendingPost>[];
    }
  }

  Future<void> writeAll(List<PendingPost> posts) async {
    final prefs = await SharedPreferences.getInstance();
    if (posts.isEmpty) {
      await prefs.remove(_key);
      return;
    }
    final encoded =
        jsonEncode(posts.map((p) => p.toJson()).toList(growable: false));
    await prefs.setString(_key, encoded);
  }

  /// Test helper / dev tool. Drops the queue regardless of state.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

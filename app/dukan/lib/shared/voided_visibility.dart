// Device-level display preference: whether voided transactions appear in the
// history screens (Sales / Receives / Payments / Expenses). Default: SHOW.
//
// Stored via DeviceConfigDao, mirroring the `home_today_expanded` pref
// (lib/home/home_screen.dart). It's a per-device view convenience — not shop
// config — so there's no backend/sync. The setting takes effect the next time a
// history screen mounts (Settings owns the toggle; the history screens read it).

import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/device_config_dao.dart';

class VoidedVisibility {
  VoidedVisibility._();

  static const String key = 'history_show_voided';

  /// Whether voided transactions are shown by default. SHOW is the default: a
  /// missing key or '1' → true; only an explicit '0' hides. Best-effort — any
  /// read error falls back to show.
  static Future<bool> showVoided() async {
    try {
      final raw = await DeviceConfigDao(AppDatabase.instance()).get(key);
      return raw != '0';
    } catch (_) {
      return true;
    }
  }

  /// Persist the preference. Fire-and-forget — errors are swallowed so a failed
  /// write never blocks the UI.
  static Future<void> setShowVoided(bool value) async {
    try {
      await DeviceConfigDao(AppDatabase.instance()).set(key, value ? '1' : '0');
    } catch (_) {
      // Best-effort.
    }
  }
}

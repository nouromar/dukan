// Per-shop, per-type void windows (in days). Source of truth is the shop
// row's `void_settings` jsonb column, projected from the
// `void_window_days_{sale,receive,payment,expense}` keys in shop_setting
// (migration 0085, mirroring scanner_settings/0049). The server enforces the
// same windows inside the void_* RPCs via `_void_window_days`; mobile reads
// these only to pre-gate the VOID button.
//
// Defaults match the column DEFAULT in the migration and the void RPC
// fallbacks (sale 7, receive 1, payment 7, expense 7).

import 'package:flutter/foundation.dart';

@immutable
class VoidSettings {
  const VoidSettings({
    this.saleDays = 7,
    this.receiveDays = 1,
    this.paymentDays = 7,
    this.expenseDays = 7,
  });

  /// The v1 baseline — matches the migration's column default exactly.
  static const VoidSettings defaults = VoidSettings();

  factory VoidSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    return VoidSettings(
      saleDays: _intOr(json['sale'], defaults.saleDays),
      receiveDays: _intOr(json['receive'], defaults.receiveDays),
      paymentDays: _intOr(json['payment'], defaults.paymentDays),
      expenseDays: _intOr(json['expense'], defaults.expenseDays),
    );
  }

  static int _intOr(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return fallback;
  }

  final int saleDays;
  final int receiveDays;
  final int paymentDays;
  final int expenseDays;

  Duration get saleWindow => Duration(days: saleDays);
  Duration get receiveWindow => Duration(days: receiveDays);
  Duration get paymentWindow => Duration(days: paymentDays);
  Duration get expenseWindow => Duration(days: expenseDays);
}

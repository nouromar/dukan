import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DukanOtpDelivery {
  const DukanOtpDelivery._();

  static const channel = OtpChannel.sms;
  static const verifyType = OtpType.sms;
}

class ShopSummary {
  const ShopSummary({
    required this.id,
    required this.name,
    required this.setupStatus,
    required this.currencyCode,
    required this.defaultLanguageCode,
    required this.timezone,
  });

  factory ShopSummary.fromJson(Map<String, dynamic> json) => ShopSummary(
    id: json['id'] as String,
    name: json['name'] as String,
    setupStatus: json['setup_status'] as String,
    currencyCode: json['currency_code'] as String,
    defaultLanguageCode: json['default_language_code'] as String,
    timezone: json['timezone'] as String,
  );

  final String id;
  final String name;
  final String setupStatus;
  final String currencyCode;
  final String defaultLanguageCode;
  final String timezone;
}

class AuthController extends ChangeNotifier {
  AuthController(this._client);

  final SupabaseClient _client;
  StreamSubscription<AuthState>? _authSubscription;

  Session? _session;
  bool _initialized = false;
  bool _shopsLoading = false;
  List<ShopSummary> _shops = const [];
  ShopSummary? _selectedShop;
  String? _pendingPhone;

  Session? get session => _session;
  bool get initialized => _initialized;
  bool get shopsLoading => _shopsLoading;
  List<ShopSummary> get shops => _shops;
  ShopSummary? get selectedShop =>
      _selectedShop ?? (_shops.length == 1 ? _shops.first : null);
  String? get pendingPhone => _pendingPhone;

  Future<void> start() async {
    if (_initialized) return;

    _session = _client.auth.currentSession;
    _authSubscription = _client.auth.onAuthStateChange.listen((state) async {
      _session = state.session;
      if (_session == null) {
        _shops = const [];
        _selectedShop = null;
      } else {
        await loadShops();
      }
      notifyListeners();
    });

    if (_session != null) {
      await loadShops();
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> sendOtp(String rawPhone) async {
    final phone = normalizePhoneNumber(rawPhone);
    await _client.auth.signInWithOtp(
      phone: phone,
      channel: DukanOtpDelivery.channel,
    );
    _pendingPhone = phone;
    notifyListeners();
  }

  Future<void> verifyOtp(String token) async {
    final phone = _pendingPhone;
    if (phone == null) {
      throw const FormatException('Start with your phone number first.');
    }

    await _client.auth.verifyOTP(
      phone: phone,
      token: token.trim(),
      type: DukanOtpDelivery.verifyType,
    );
  }

  Future<void> loadShops() async {
    _shopsLoading = true;
    notifyListeners();

    try {
      final rows = await _client
          .from('shop')
          .select(
            'id, name, setup_status, currency_code, default_language_code, timezone',
          )
          .order('name');

      _shops = rows
          .map<ShopSummary>(
            (row) => ShopSummary.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false);

      if (_selectedShop != null &&
          !_shops.any((shop) => shop.id == _selectedShop!.id)) {
        _selectedShop = null;
      }
    } finally {
      _shopsLoading = false;
      notifyListeners();
    }
  }

  Future<void> createFirstShop({
    required String businessName,
    required String shopName,
  }) async {
    final cleanBusinessName = businessName.trim();
    final cleanShopName = shopName.trim();

    if (cleanBusinessName.isEmpty || cleanShopName.isEmpty) {
      throw const FormatException('Enter both business name and shop name.');
    }

    await _client.rpc(
      'create_organization',
      params: {
        'p_organization_name': cleanBusinessName,
        'p_shop_name': cleanShopName,
      },
    );
    await loadShops();
  }

  void selectShop(ShopSummary shop) {
    _selectedShop = shop;
    notifyListeners();
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    _pendingPhone = null;
    _shops = const [];
    _selectedShop = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

String normalizePhoneNumber(String rawPhone) {
  var phone = rawPhone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

  if (phone.startsWith('00')) {
    phone = '+${phone.substring(2)}';
  } else if (phone.startsWith('0')) {
    phone = '+252${phone.substring(1)}';
  } else if (!phone.startsWith('+')) {
    phone = '+252$phone';
  }

  final isValidE164 = RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone);
  if (!isValidE164) {
    throw const FormatException(
      'Enter a valid phone number, for example +252612345678.',
    );
  }

  return phone;
}

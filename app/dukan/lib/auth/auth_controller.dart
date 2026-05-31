import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DukanOtpDelivery {
  const DukanOtpDelivery._();

  static const channel = OtpChannel.sms;
  static const verifyType = OtpType.sms;
}

enum AuthInputIssue { invalidPhone, missingPendingPhone, missingShopNames }

class AuthInputException implements Exception {
  const AuthInputException(this.issue);

  final AuthInputIssue issue;
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

  bool get isReady => setupStatus == 'ready';
  bool get isTemplateApplied =>
      setupStatus == 'template_applied' || setupStatus == 'opening_stock_done';
}

class TemplateOption {
  const TemplateOption({
    required this.id,
    required this.code,
    required this.name,
  });

  factory TemplateOption.fromJson(Map<String, dynamic> json) => TemplateOption(
    id: json['id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
  );

  final String id;
  final String code;
  final String name;
}

class ShopItem {
  const ShopItem({
    required this.id,
    required this.code,
    required this.name,
    required this.baseUnitCode,
    required this.baseUnitLabel,
  });

  factory ShopItem.fromJson(Map<String, dynamic> json) {
    final unit = json['base_unit'] as Map<String, dynamic>;
    return ShopItem(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      baseUnitCode: unit['code'] as String,
      baseUnitLabel: unit['default_label'] as String,
    );
  }

  final String id;
  final String code;
  final String name;
  final String baseUnitCode;
  final String baseUnitLabel;
}

class CatalogSearchResult {
  const CatalogSearchResult({
    required this.id,
    required this.name,
    required this.baseUnitCode,
    required this.baseUnitLabel,
    required this.shopItemId,
  });

  factory CatalogSearchResult.fromJson(Map<String, dynamic> json) {
    return CatalogSearchResult(
      id: json['catalog_item_id'] as String,
      name: json['name'] as String,
      baseUnitCode: json['base_unit_code'] as String,
      baseUnitLabel: json['base_unit_label'] as String,
      shopItemId: json['shop_item_id'] as String?,
    );
  }

  final String id;
  final String name;
  final String baseUnitCode;
  final String baseUnitLabel;
  final String? shopItemId;

  bool get isActivated => shopItemId != null;
}

class ReferenceOption {
  const ReferenceOption({required this.code, required this.label});

  factory ReferenceOption.fromJson(Map<String, dynamic> json) =>
      ReferenceOption(
        code: json['code'] as String,
        label: (json['name'] ?? json['symbol'] ?? json['code']) as String,
      );

  final String code;
  final String label;
}

class AuthController extends ChangeNotifier {
  AuthController(this._client);

  final SupabaseClient _client;
  StreamSubscription<AuthState>? _authSubscription;

  Session? _session;
  bool _initialized = false;
  bool _shopsLoading = false;
  bool _shopLoadFailed = false;
  List<ShopSummary> _shops = const [];
  ShopSummary? _selectedShop;
  String? _pendingPhone;

  Session? get session => _session;
  bool get initialized => _initialized;
  bool get shopsLoading => _shopsLoading;
  bool get shopLoadFailed => _shopLoadFailed;
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
        _shopLoadFailed = false;
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
      throw const AuthInputException(AuthInputIssue.missingPendingPhone);
    }

    await _client.auth.verifyOTP(
      phone: phone,
      token: token.trim(),
      type: DukanOtpDelivery.verifyType,
    );
    _pendingPhone = null;
    notifyListeners();
  }

  void cancelOtp() {
    if (_pendingPhone == null) return;
    _pendingPhone = null;
    notifyListeners();
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
      _shopLoadFailed = false;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan auth',
          context: ErrorDescription('loading authorized shops'),
        ),
      );
      _shopLoadFailed = true;
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
      throw const AuthInputException(AuthInputIssue.missingShopNames);
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

  Future<List<TemplateOption>> listAvailableTemplates() async {
    final rows = await _client
        .from('template')
        .select('id, code, name')
        .eq('is_active', true)
        .order('name');
    return rows
        .map<TemplateOption>(
          (row) => TemplateOption.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<void> applyTemplate({
    required String shopId,
    required String templateId,
  }) async {
    await _client.rpc(
      'apply_template',
      params: {'p_shop_id': shopId, 'p_template_id': templateId},
    );
    await _refreshShop(shopId);
  }

  Future<List<ShopItem>> listShopItems({required String shopId}) async {
    final rows = await _client
        .from('item')
        .select('id, code, name, base_unit:base_unit_id(code, default_label)')
        .eq('shop_id', shopId)
        .order('name');
    return rows
        .map<ShopItem>(
          (row) => ShopItem.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<String> ensureShopItem({
    required String shopId,
    required String catalogItemId,
  }) async {
    final result = await _client.rpc(
      'ensure_shop_item',
      params: {'p_shop_id': shopId, 'p_catalog_item_id': catalogItemId},
    );
    return result as String;
  }

  Future<void> completeSetup({required String shopId}) async {
    await _client.rpc('complete_shop_setup', params: {'p_shop_id': shopId});
    await _refreshShop(shopId);
  }

  Future<List<ReferenceOption>> listLanguages() async {
    final rows = await _client
        .from('language')
        .select('code, name')
        .eq('is_active', true)
        .order('name');
    return rows
        .map<ReferenceOption>(
          (row) => ReferenceOption.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<List<ReferenceOption>> listCurrencies() async {
    final rows = await _client
        .from('currency')
        .select('code, symbol')
        .eq('is_active', true)
        .order('code');
    return rows
        .map<ReferenceOption>(
          (row) => ReferenceOption.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<void> updateShopDefaults({
    required String shopId,
    String? name,
    String? currencyCode,
    String? defaultLanguageCode,
    String? timezone,
  }) async {
    final patch = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) patch['name'] = name.trim();
    if (currencyCode != null) patch['currency_code'] = currencyCode;
    if (defaultLanguageCode != null) {
      patch['default_language_code'] = defaultLanguageCode;
    }
    if (timezone != null && timezone.trim().isNotEmpty) {
      patch['timezone'] = timezone.trim();
    }
    if (patch.isEmpty) return;
    await _client.from('shop').update(patch).eq('id', shopId);
    await _refreshShop(shopId);
  }

  Future<void> _refreshShop(String shopId) async {
    final row = await _client
        .from('shop')
        .select(
          'id, name, setup_status, currency_code, default_language_code, timezone',
        )
        .eq('id', shopId)
        .maybeSingle();
    if (row == null) {
      await loadShops();
      return;
    }
    final updated = ShopSummary.fromJson(Map<String, dynamic>.from(row));
    _shops = _shops
        .map((shop) => shop.id == shopId ? updated : shop)
        .toList(growable: false);
    if (_selectedShop?.id == shopId) {
      _selectedShop = updated;
    }
    notifyListeners();
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
    throw const AuthInputException(AuthInputIssue.invalidPhone);
  }

  return phone;
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/auth/auth_state_cache.dart';
import 'package:dukan/auth/capabilities.dart';
import 'package:dukan/config/business_rules.dart';
import 'package:dukan/scanner/scanner_settings.dart';

class DukanOtpDelivery {
  const DukanOtpDelivery._();

  static const channel = OtpChannel.sms;
  static const verifyType = OtpType.sms;
}

enum AuthInputIssue {
  invalidPhone,
  invalidEmail,
  missingPendingPhone,
  missingPendingDestination,
  missingShopNames,
}

class AuthInputException implements Exception {
  const AuthInputException(this.issue);

  final AuthInputIssue issue;
}

class AuthController extends ChangeNotifier {
  AuthController({required SupabaseClient client, required ShopApi shopApi})
    : _client = client,
      _shopApi = shopApi;

  final SupabaseClient _client;
  final ShopApi _shopApi;
  StreamSubscription<AuthState>? _authSubscription;

  Session? _session;
  bool _initialized = false;
  bool _shopsLoading = false;
  bool _shopLoadFailed = false;
  List<ShopSummary> _shops = const [];
  ShopSummary? _selectedShop;
  String? _pendingPhone;
  String? _pendingEmail;
  Capabilities _capabilities = Capabilities.empty();
  String? _capabilitiesShopId;
  /// Held so cache writes (selectShop, refreshSelectedShop) don't have
  /// to re-fetch the currency reference table. Updated by loadShops
  /// and by the cache-hit branch of start().
  Map<String, String> _currencySymbols = const {};

  Session? get session => _session;
  bool get initialized => _initialized;
  bool get shopsLoading => _shopsLoading;
  bool get shopLoadFailed => _shopLoadFailed;
  List<ShopSummary> get shops => _shops;
  ShopSummary? get selectedShop =>
      _selectedShop ?? (_shops.length == 1 ? _shops.first : null);
  String? get pendingPhone => _pendingPhone;
  String? get pendingEmail => _pendingEmail;

  /// Capability set for the currently-selected shop. Empty when no
  /// shop is selected or while the first load is in flight — UI
  /// gates default to "denied" in that state.
  Capabilities get capabilities => _capabilities;

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
        // Pending-invite auto-claim runs before shop load so any
        // freshly-claimed shop shows up in the first loadShops()
        // call — no extra refresh from the UI side.
        await _claimPendingInvitesSilently();
        await loadShops();
      }
      notifyListeners();
    });

    if (_session != null) {
      // SWR: if there's a cached shop list for this user, paint it
      // synchronously and let AuthRouter mount HomeScreen on the
      // next frame. The source-of-truth refresh (claim invites +
      // loadShops) fires unawaited; when it lands, _shops is
      // replaced and the UI swaps. This is the same SWR pattern as
      // the Today card (lib/shared/today_summary_cache.dart) lifted
      // one level up so the auth chain stops being the gate.
      final userId = _session!.user.id;
      final cached = await AuthStateCache.get(userId);
      if (cached != null && cached.shops.isNotEmpty) {
        _shops = cached.shops;
        _currencySymbols = cached.currencySymbols;
        if (cached.selectedShopId != null) {
          _selectedShop = _shopById(cached.shops, cached.selectedShopId!);
        }
        _initialized = true;
        notifyListeners();
        // Install scanner settings + fire capabilities sync against
        // the cached selection now so the scanner and feature gates
        // are ready before the user taps into Sale/Receive.
        unawaited(_syncCapabilities());
        // Background refresh — same sequence as the cold-cache path.
        unawaited(_claimPendingInvitesSilently().then((_) => loadShops()));
        return;
      }
      // Cold cache — fall through to the serial path (same as before
      // this change). LoadingScreen renders until both calls return.
      await _claimPendingInvitesSilently();
      await loadShops();
    }

    _initialized = true;
    notifyListeners();
  }

  static ShopSummary? _shopById(List<ShopSummary> shops, String id) {
    for (final shop in shops) {
      if (shop.id == id) return shop;
    }
    return null;
  }

  /// Calls claim_pending_invites_for_me() and swallows errors. The RPC
  /// is idempotent and cheap when nothing matches — safe to call on
  /// every sign-in. Failures don't block sign-in: the user can still
  /// access whatever they have without the invite.
  Future<void> _claimPendingInvitesSilently() async {
    try {
      await _client.rpc('claim_pending_invites_for_me');
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan auth',
          context: ErrorDescription('claim_pending_invites_for_me'),
        ),
      );
    }
  }

  Future<void> sendOtp(String rawPhone) async {
    final phone = normalizePhoneNumber(rawPhone);
    await _client.auth.signInWithOtp(
      phone: phone,
      channel: DukanOtpDelivery.channel,
    );
    _pendingPhone = phone;
    _pendingEmail = null;
    notifyListeners();
  }

  /// Sends a 6-digit OTP to the given email. shouldCreateUser:true so a new
  /// email self-onboards: Supabase creates the account, then a signed-in user
  /// with no shops is routed to owner onboarding (create org/shop → pick
  /// template). An *invited* email instead claims its pending invite on
  /// sign-in (see _claimPendingInvitesSilently), joining that shop. For
  /// Supabase to email the code (not a magic link), the "Magic Link" email
  /// template must include {{ .Token }} alongside or instead of
  /// {{ .ConfirmationURL }}.
  Future<void> sendEmailOtp(String rawEmail) async {
    final email = normalizeEmail(rawEmail);
    await _client.auth.signInWithOtp(
      email: email,
      shouldCreateUser: true,
    );
    _pendingEmail = email;
    _pendingPhone = null;
    notifyListeners();
  }

  /// Verifies the code against whichever destination is currently pending
  /// (phone OR email). Throws missingPendingDestination if neither was
  /// initiated — i.e. someone reached the verify screen without first
  /// requesting a code.
  Future<void> verifyOtp(String token) async {
    final phone = _pendingPhone;
    final email = _pendingEmail;
    final trimmed = token.trim();

    if (phone != null) {
      await _client.auth.verifyOTP(
        phone: phone,
        token: trimmed,
        type: DukanOtpDelivery.verifyType,
      );
      _pendingPhone = null;
      notifyListeners();
      return;
    }

    if (email != null) {
      await _client.auth.verifyOTP(
        email: email,
        token: trimmed,
        type: OtpType.email,
      );
      _pendingEmail = null;
      notifyListeners();
      return;
    }

    throw const AuthInputException(AuthInputIssue.missingPendingDestination);
  }

  void cancelOtp() {
    if (_pendingPhone == null && _pendingEmail == null) return;
    _pendingPhone = null;
    _pendingEmail = null;
    notifyListeners();
  }

  Future<void> loadShops() async {
    _shopsLoading = true;
    notifyListeners();

    try {
      final symbols = await _shopApi.currencySymbols();
      final decimals = await _shopApi.currencyDecimals();
      final rows = await _client
          .from('shop')
          .select(
            'id, name, setup_status, currency_code, default_language_code, timezone, onboarding_dismissed_at, scanner_settings',
          )
          .order('name');

      _shops = rows
          .map<ShopSummary>(
            (row) => ShopSummary.fromJson(
              Map<String, dynamic>.from(row),
              currencySymbols: symbols,
              currencyDecimals: decimals,
            ),
          )
          .toList(growable: false);
      _currencySymbols = symbols;

      if (_selectedShop != null &&
          !_shops.any((shop) => shop.id == _selectedShop!.id)) {
        _selectedShop = null;
      }
      _shopLoadFailed = false;
      unawaited(_writeCacheIfSignedIn());
      unawaited(_syncCapabilities());
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

  /// Pulls the currently-selected shop's row from the server and projects it
  /// into local state so listeners (AuthRouter, screens that watch
  /// selectedShop) see the new value. Used by callers after any ShopApi
  /// write that affects shop-row fields — apply_template, complete_shop_setup,
  /// update_shop_defaults, etc.
  Future<void> refreshSelectedShop() async {
    final current = _selectedShop?.id ?? (_shops.length == 1 ? _shops.first.id : null);
    if (current == null) return;
    final updated = await _shopApi.fetchShop(current);
    if (updated == null) {
      await loadShops();
      return;
    }
    _shops = _shops
        .map((shop) => shop.id == current ? updated : shop)
        .toList(growable: false);
    if (_selectedShop?.id == current) {
      _selectedShop = updated;
    }
    notifyListeners();
  }

  void selectShop(ShopSummary shop) {
    _selectedShop = shop;
    notifyListeners();
    unawaited(_syncCapabilities());
    unawaited(_writeCacheIfSignedIn());
  }

  Future<void> signOut() async {
    final userId = _session?.user.id;
    await _client.auth.signOut();
    _pendingPhone = null;
    _pendingEmail = null;
    _shops = const [];
    _selectedShop = null;
    _capabilities = Capabilities.empty();
    _capabilitiesShopId = null;
    _currencySymbols = const {};
    if (userId != null) {
      unawaited(AuthStateCache.clear(userId));
    }
    notifyListeners();
  }

  /// Best-effort SWR write — persisted for the next cold start. Skipped
  /// when no session or no shops, since there's nothing useful to
  /// render-fast on next mount.
  Future<void> _writeCacheIfSignedIn() async {
    final userId = _session?.user.id;
    if (userId == null || _shops.isEmpty) return;
    await AuthStateCache.put(
      userId,
      shops: _shops,
      currencySymbols: _currencySymbols,
      selectedShopId: _selectedShop?.id,
    );
  }

  /// Fetches the capability set for the currently-effective shop
  /// (the resolved `selectedShop`) when it differs from what's
  /// already cached. Diffs on shop id so this is cheap to call any
  /// time the shop state might have changed; the RPC fires at most
  /// once per shop selection. Also pushes the shop's scanner
  /// settings into ScannerSettings.current so the viewfinder sheets
  /// and HID listener read the right tuning for this shop.
  Future<void> _syncCapabilities() async {
    final shop = selectedShop;
    if (shop == null) {
      ScannerSettings.install(ScannerSettings.defaults);
      if (_capabilities.codes.isNotEmpty || _capabilitiesShopId != null) {
        _capabilities = Capabilities.empty();
        _capabilitiesShopId = null;
        notifyListeners();
      }
      return;
    }
    // Scanner settings ride along with the ShopSummary — no extra RPC.
    ScannerSettings.install(shop.scannerSettings);
    if (_capabilitiesShopId == shop.id && _capabilities.codes.isNotEmpty) {
      return;
    }
    try {
      final codes = await _shopApi.listUserShopCapabilities(shopId: shop.id);
      _capabilities = Capabilities(codes.toSet());
      _capabilitiesShopId = shop.id;
      notifyListeners();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan auth',
          context: ErrorDescription('loading shop capabilities'),
        ),
      );
      // Leave capabilities empty so UI gates fail closed.
    }
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
    phone = '$defaultCountryCode${phone.substring(1)}';
  } else if (!phone.startsWith('+')) {
    phone = '$defaultCountryCode$phone';
  }

  final isValidE164 = RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone);
  if (!isValidE164) {
    throw const AuthInputException(AuthInputIssue.invalidPhone);
  }

  return phone;
}

/// Lightweight email validation. Trims surrounding whitespace and
/// lower-cases the address (mirrors Supabase's own normalization on
/// auth.users.email). Throws AuthInputException(invalidEmail) when
/// the result doesn't look like an address. Not RFC 5322 strict —
/// the source of truth is Supabase, which will reject anything we'd
/// otherwise let through.
String normalizeEmail(String rawEmail) {
  final email = rawEmail.trim().toLowerCase();
  final isValid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  if (!isValid) {
    throw const AuthInputException(AuthInputIssue.invalidEmail);
  }
  return email;
}

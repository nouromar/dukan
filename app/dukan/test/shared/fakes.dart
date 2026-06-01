// Hand-rolled AuthController stand-in for widget tests. Implements every
// public method our screens reach for, returning canned data or replaying
// caller-supplied callbacks. Letting each test override exactly the surface
// it exercises keeps the assertions readable and the failure messages
// pointing at the right thing.
//
// We use ChangeNotifier + `implements AuthController` rather than mocktail's
// `Mock` so the value works inside `ChangeNotifierProvider<AuthController>`
// without special-casing the listener plumbing.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/auth/auth_controller.dart';

class FakeAuthController extends ChangeNotifier implements AuthController {
  FakeAuthController({
    List<ShopSummary> shops = const [],
    ShopSummary? selectedShop,
    Session? session,
    bool initialized = true,
    bool shopsLoading = false,
    bool shopLoadFailed = false,
    String? pendingPhone,
  }) : _shops = shops,
       _selectedShop = selectedShop,
       _session = session,
       _initialized = initialized,
       _shopsLoading = shopsLoading,
       _shopLoadFailed = shopLoadFailed,
       _pendingPhone = pendingPhone;

  // --- mutable backing fields ---------------------------------------------

  List<ShopSummary> _shops;
  ShopSummary? _selectedShop;
  Session? _session;
  bool _initialized;
  bool _shopsLoading;
  bool _shopLoadFailed;
  String? _pendingPhone;

  // --- caller-installable hooks (set per test) ----------------------------

  Future<List<TemplateOption>> Function()? onListAvailableTemplates;
  Future<void> Function(String shopId, String templateId)? onApplyTemplate;
  Future<void> Function(String shopId)? onCompleteSetup;
  Future<List<ItemSearchResult>> Function(
    String shopId,
    String query,
    int limit,
    String? screen,
  )?
  onSearchItems;
  Future<List<PartySearchResult>> Function(
    String shopId,
    String query,
    String type,
    int limit,
  )?
  onSearchParties;
  Future<List<UnitOption>> Function()? onListUnits;
  Future<String> Function(
    String shopId,
    List<SaleLine> lines,
    num paidAmount,
    String? partyId,
    String? paymentMethodCode,
    String clientOpId,
    String? notes,
  )?
  onPostSale;
  Future<String> Function(String shopId, String catalogItemId)?
  onEnsureShopItem;
  Future<List<ReferenceOption>> Function()? onListLanguages;
  Future<List<ReferenceOption>> Function()? onListCurrencies;
  Future<void> Function(
    String shopId, {
    String? name,
    String? currencyCode,
    String? defaultLanguageCode,
    String? timezone,
  })?
  onUpdateShopDefaults;
  Future<void> Function(String rawPhone)? onSendOtp;
  Future<void> Function(String token)? onVerifyOtp;
  Future<void> Function(String businessName, String shopName)?
  onCreateFirstShop;
  Future<void> Function()? onSignOut;
  Future<void> Function()? onLoadShops;

  // --- mutation helpers for tests ----------------------------------------

  void setShops(List<ShopSummary> shops) {
    _shops = shops;
    notifyListeners();
  }

  void setSelectedShop(ShopSummary? shop) {
    _selectedShop = shop;
    notifyListeners();
  }

  void setShopsLoading(bool value) {
    _shopsLoading = value;
    notifyListeners();
  }

  void setShopLoadFailed(bool value) {
    _shopLoadFailed = value;
    notifyListeners();
  }

  void setPendingPhone(String? phone) {
    _pendingPhone = phone;
    notifyListeners();
  }

  void setSession(Session? session) {
    _session = session;
    notifyListeners();
  }

  void setInitialized(bool value) {
    _initialized = value;
    notifyListeners();
  }

  // --- AuthController surface --------------------------------------------

  @override
  Session? get session => _session;
  @override
  bool get initialized => _initialized;
  @override
  bool get shopsLoading => _shopsLoading;
  @override
  bool get shopLoadFailed => _shopLoadFailed;
  @override
  List<ShopSummary> get shops => _shops;
  @override
  ShopSummary? get selectedShop =>
      _selectedShop ?? (_shops.length == 1 ? _shops.first : null);
  @override
  String? get pendingPhone => _pendingPhone;

  @override
  Future<void> start() async {
    _initialized = true;
    notifyListeners();
  }

  @override
  Future<void> sendOtp(String rawPhone) async {
    if (onSendOtp != null) return onSendOtp!(rawPhone);
    _pendingPhone = rawPhone;
    notifyListeners();
  }

  @override
  Future<void> verifyOtp(String token) async {
    if (onVerifyOtp != null) return onVerifyOtp!(token);
    _pendingPhone = null;
    notifyListeners();
  }

  @override
  void cancelOtp() {
    if (_pendingPhone == null) return;
    _pendingPhone = null;
    notifyListeners();
  }

  @override
  Future<void> loadShops() async {
    if (onLoadShops != null) return onLoadShops!();
  }

  @override
  Future<void> createFirstShop({
    required String businessName,
    required String shopName,
  }) async {
    if (onCreateFirstShop != null) {
      return onCreateFirstShop!(businessName, shopName);
    }
  }

  @override
  Future<List<TemplateOption>> listAvailableTemplates() async {
    if (onListAvailableTemplates != null) return onListAvailableTemplates!();
    return const [];
  }

  @override
  Future<void> applyTemplate({
    required String shopId,
    required String templateId,
  }) async {
    if (onApplyTemplate != null) {
      return onApplyTemplate!(shopId, templateId);
    }
  }

  @override
  Future<List<ShopItem>> listShopItems({required String shopId}) async {
    return const [];
  }

  @override
  Future<String> ensureShopItem({
    required String shopId,
    required String catalogItemId,
  }) async {
    if (onEnsureShopItem != null) {
      return onEnsureShopItem!(shopId, catalogItemId);
    }
    return 'fake-item-${catalogItemId.hashCode}';
  }

  @override
  Future<List<ItemSearchResult>> searchItems({
    required String shopId,
    String query = '',
    int limit = 50,
    String? screen,
  }) async {
    if (onSearchItems != null) {
      return onSearchItems!(shopId, query, limit, screen);
    }
    return const [];
  }

  @override
  Future<List<PartySearchResult>> searchParties({
    required String shopId,
    String query = '',
    String type = 'customer',
    int limit = 50,
  }) async {
    if (onSearchParties != null) {
      return onSearchParties!(shopId, query, type, limit);
    }
    return const [];
  }

  @override
  Future<List<UnitOption>> listUnits() async {
    if (onListUnits != null) return onListUnits!();
    return const [
      UnitOption(id: 'unit-piece', code: 'piece', label: 'Piece'),
      UnitOption(id: 'unit-kg', code: 'kg', label: 'Kg'),
      UnitOption(id: 'unit-bag', code: 'bag', label: 'Bag'),
      UnitOption(id: 'unit-litre', code: 'litre', label: 'Litre'),
      UnitOption(id: 'unit-bottle', code: 'bottle', label: 'Bottle'),
      UnitOption(id: 'unit-packet', code: 'packet', label: 'Packet'),
      UnitOption(id: 'unit-box', code: 'box', label: 'Box'),
      UnitOption(id: 'unit-carton', code: 'carton', label: 'Carton'),
    ];
  }

  @override
  Future<String> postSale({
    required String shopId,
    required List<SaleLine> lines,
    required num paidAmount,
    String? partyId,
    String? paymentMethodCode,
    required String clientOpId,
    String? notes,
  }) async {
    if (onPostSale != null) {
      return onPostSale!(
        shopId,
        lines,
        paidAmount,
        partyId,
        paymentMethodCode,
        clientOpId,
        notes,
      );
    }
    return 'fake-txn-${clientOpId.hashCode}';
  }

  @override
  Future<void> completeSetup({required String shopId}) async {
    if (onCompleteSetup != null) return onCompleteSetup!(shopId);
  }

  @override
  Future<List<ReferenceOption>> listLanguages() async {
    if (onListLanguages != null) return onListLanguages!();
    return const [
      ReferenceOption(code: 'en', label: 'English'),
      ReferenceOption(code: 'so', label: 'Somali'),
    ];
  }

  @override
  Future<List<ReferenceOption>> listCurrencies() async {
    if (onListCurrencies != null) return onListCurrencies!();
    return const [
      ReferenceOption(code: 'USD', label: '\$'),
      ReferenceOption(code: 'SLSH', label: 'SLSH'),
    ];
  }

  @override
  Future<void> updateShopDefaults({
    required String shopId,
    String? name,
    String? currencyCode,
    String? defaultLanguageCode,
    String? timezone,
  }) async {
    if (onUpdateShopDefaults != null) {
      return onUpdateShopDefaults!(
        shopId,
        name: name,
        currencyCode: currencyCode,
        defaultLanguageCode: defaultLanguageCode,
        timezone: timezone,
      );
    }
  }

  @override
  void selectShop(ShopSummary shop) {
    _selectedShop = shop;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    if (onSignOut != null) return onSignOut!();
    _session = null;
    _shops = const [];
    _selectedShop = null;
    _pendingPhone = null;
    notifyListeners();
  }
}

// --- Fixture builders -----------------------------------------------------

ShopSummary fakeShop({
  String id = 'shop-1',
  String name = 'Hodan Shop',
  String setupStatus = 'ready',
  String currencyCode = 'USD',
  String defaultLanguageCode = 'so',
  String timezone = 'Africa/Mogadishu',
}) => ShopSummary(
  id: id,
  name: name,
  setupStatus: setupStatus,
  currencyCode: currencyCode,
  defaultLanguageCode: defaultLanguageCode,
  timezone: timezone,
);

TemplateOption fakeTemplate({
  String id = 'template-1',
  String code = 'grocery',
  String name = 'Grocery',
}) => TemplateOption(id: id, code: code, name: name);

ItemSearchResult fakeActivatedItem({
  String itemId = 'item-1',
  String? catalogItemId = 'catalog-1',
  String name = 'Bariis Basmati',
  String baseUnitCode = 'kg',
  String baseUnitLabel = 'Kg',
  double? salePrice = 1.5,
  double? currentStock = 50,
}) => ItemSearchResult(
  itemId: itemId,
  catalogItemId: catalogItemId,
  name: name,
  baseUnitCode: baseUnitCode,
  baseUnitLabel: baseUnitLabel,
  salePrice: salePrice,
  currentStock: currentStock,
  isActivated: true,
);

PartySearchResult fakeCustomer({
  String id = 'party-1',
  String name = 'Ahmed',
  String? phone = '+252600000000',
  double receivable = 12.5,
}) => PartySearchResult(
  id: id,
  name: name,
  phone: phone,
  typeCode: 'customer',
  receivable: receivable,
  payable: 0,
);

ItemSearchResult fakeCatalogCandidate({
  String catalogItemId = 'catalog-2',
  String name = 'Caano qalaylan',
  String baseUnitCode = 'packet',
  String baseUnitLabel = 'Packet',
  double? salePrice = 3.0,
}) => ItemSearchResult(
  itemId: null,
  catalogItemId: catalogItemId,
  name: name,
  baseUnitCode: baseUnitCode,
  baseUnitLabel: baseUnitLabel,
  salePrice: salePrice,
  currentStock: null,
  isActivated: false,
);

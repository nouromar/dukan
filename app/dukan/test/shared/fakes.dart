// Test stand-ins for AuthController + ShopApi. Each implements the same
// surface the production code does so widget tests can drop them into the
// providers wrapWithApp installs. Callers install per-test hooks
// (onSearchItems, onPostSale, ...) to drive specific code paths and
// assert what flowed through.
//
// We use plain ChangeNotifier / class extensions rather than mocktail's
// Mock so the fakes work inside the same Provider plumbing the real app
// uses (Mock<ChangeNotifier> breaks listener tracking).

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/auth/auth_controller.dart';

// --- FakeAuthController ---------------------------------------------------

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

  List<ShopSummary> _shops;
  ShopSummary? _selectedShop;
  Session? _session;
  bool _initialized;
  bool _shopsLoading;
  bool _shopLoadFailed;
  String? _pendingPhone;

  Future<void> Function(String rawPhone)? onSendOtp;
  Future<void> Function(String token)? onVerifyOtp;
  Future<void> Function(String businessName, String shopName)?
  onCreateFirstShop;
  Future<void> Function()? onSignOut;
  Future<void> Function()? onLoadShops;
  Future<void> Function()? onRefreshSelectedShop;

  int refreshSelectedShopCalls = 0;

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
  Future<void> refreshSelectedShop() async {
    refreshSelectedShopCalls++;
    if (onRefreshSelectedShop != null) return onRefreshSelectedShop!();
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

// --- FakeShopApi ----------------------------------------------------------

class FakeShopApi implements ShopApi {
  FakeShopApi();

  Future<List<TemplateOption>> Function()? onListAvailableTemplates;
  Future<void> Function(String shopId, String templateId)? onApplyTemplate;
  Future<void> Function(String shopId)? onCompleteSetup;
  Future<String> Function(String shopId, String catalogItemId)?
  onEnsureShopItem;
  Future<void> Function(String shopId, String itemId, num salePrice)?
  onSetItemSalePrice;
  final List<({String itemId, num salePrice})> setItemSalePriceCalls = [];
  Future<List<ReceiveUnitOption>> Function(
    String shopId,
    String? itemId,
    String? catalogItemId,
    String screen,
  )?
  onListItemUnits;
  Future<List<ItemSearchResult>> Function(
    String shopId,
    String query,
    int limit,
    String? screen,
    String? locale,
    String? partyId,
  )?
  onSearchItems;
  Future<List<PartySearchResult>> Function(
    String shopId,
    String query,
    String type,
    int limit,
  )?
  onSearchParties;
  Future<String> Function(
    String shopId,
    String name,
    String? phone,
    String typeCode,
  )?
  onCreateParty;
  final List<
    ({String name, String? phone, String typeCode})
  > createPartyCalls = [];
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
  Future<String> Function(
    String shopId,
    String partyId,
    List<ReceiveLinePayload> lines,
    num paidAmount,
    String? paymentMethodCode,
    String? documentId,
    String clientOpId,
    String? notes,
  )?
  onPostReceive;
  Future<String> Function(
    String shopId,
    String partyId,
    String direction,
    num amount,
    String paymentMethodCode,
    String clientOpId,
    String? notes,
  )?
  onPostPayment;
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
  Future<ShopSummary?> Function(String shopId)? onFetchShop;

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
  Future<void> completeSetup({required String shopId}) async {
    if (onCompleteSetup != null) return onCompleteSetup!(shopId);
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
  Future<void> setItemSalePrice({
    required String shopId,
    required String itemId,
    required num salePrice,
  }) async {
    setItemSalePriceCalls.add((itemId: itemId, salePrice: salePrice));
    if (onSetItemSalePrice != null) {
      return onSetItemSalePrice!(shopId, itemId, salePrice);
    }
  }

  @override
  Future<List<ReceiveUnitOption>> listItemUnits({
    required String shopId,
    String? itemId,
    String? catalogItemId,
    String screen = 'receive',
  }) async {
    if (onListItemUnits != null) {
      return onListItemUnits!(shopId, itemId, catalogItemId, screen);
    }
    // Sensible default: two units (base + a receive unit) so tests not
    // explicitly setting onListItemUnits still exercise the picker.
    return const [
      ReceiveUnitOption(
        unitId: 'unit-kg',
        unitCode: 'kg',
        unitLabel: 'Kg',
        conversionToBase: 1,
        isDefault: false,
      ),
      ReceiveUnitOption(
        unitId: 'unit-bag',
        unitCode: 'bag',
        unitLabel: 'Bag',
        conversionToBase: 25,
        isDefault: true,
      ),
    ];
  }

  @override
  Future<List<ItemSearchResult>> searchItems({
    required String shopId,
    String query = '',
    int limit = 50,
    String? screen,
    String? locale,
    String? partyId,
  }) async {
    if (onSearchItems != null) {
      return onSearchItems!(shopId, query, limit, screen, locale, partyId);
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
  Future<String> createParty({
    required String shopId,
    required String name,
    required String typeCode,
    String? phone,
  }) async {
    createPartyCalls.add((name: name, phone: phone, typeCode: typeCode));
    if (onCreateParty != null) {
      return onCreateParty!(shopId, name, phone, typeCode);
    }
    return 'fake-party-${name.hashCode}';
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
  Future<String> postPayment({
    required String shopId,
    required String partyId,
    required String direction,
    required num amount,
    required String paymentMethodCode,
    required String clientOpId,
    String? notes,
  }) async {
    if (onPostPayment != null) {
      return onPostPayment!(
        shopId,
        partyId,
        direction,
        amount,
        paymentMethodCode,
        clientOpId,
        notes,
      );
    }
    return 'fake-payment-${clientOpId.hashCode}';
  }

  @override
  Future<String> postReceive({
    required String shopId,
    required String partyId,
    required List<ReceiveLinePayload> lines,
    required num paidAmount,
    String? paymentMethodCode,
    String? documentId,
    required String clientOpId,
    String? notes,
  }) async {
    if (onPostReceive != null) {
      return onPostReceive!(
        shopId,
        partyId,
        lines,
        paidAmount,
        paymentMethodCode,
        documentId,
        clientOpId,
        notes,
      );
    }
    return 'fake-receive-${clientOpId.hashCode}';
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
  Future<Map<String, String>> currencySymbols() async {
    final currencies = await listCurrencies();
    return {for (final c in currencies) c.code: c.label};
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
  Future<ShopSummary?> fetchShop(String shopId) async {
    if (onFetchShop != null) return onFetchShop!(shopId);
    return null;
  }
}

// --- Fixture builders -----------------------------------------------------

ShopSummary fakeShop({
  String id = 'shop-1',
  String name = 'Hodan Shop',
  String setupStatus = 'ready',
  String currencyCode = 'USD',
  String currencySymbol = '\$',
  String defaultLanguageCode = 'so',
  String timezone = 'Africa/Mogadishu',
}) => ShopSummary(
  id: id,
  name: name,
  setupStatus: setupStatus,
  currencyCode: currencyCode,
  currencySymbol: currencySymbol,
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
  String receiveUnitCode = 'bag',
  String receiveUnitLabel = 'Bag',
  double? salePrice = 1.5,
  double? lastCost,
  double? currentStock = 50,
}) => ItemSearchResult(
  itemId: itemId,
  catalogItemId: catalogItemId,
  name: name,
  baseUnitCode: baseUnitCode,
  baseUnitLabel: baseUnitLabel,
  receiveUnitCode: receiveUnitCode,
  receiveUnitLabel: receiveUnitLabel,
  salePrice: salePrice,
  lastCost: lastCost,
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
  String receiveUnitCode = 'carton',
  String receiveUnitLabel = 'Carton',
  double? salePrice = 3.0,
  double? lastCost,
}) => ItemSearchResult(
  itemId: null,
  catalogItemId: catalogItemId,
  name: name,
  baseUnitCode: baseUnitCode,
  baseUnitLabel: baseUnitLabel,
  receiveUnitCode: receiveUnitCode,
  receiveUnitLabel: receiveUnitLabel,
  salePrice: salePrice,
  lastCost: lastCost,
  currentStock: null,
  isActivated: false,
);

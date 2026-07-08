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
import 'dart:async';

import 'package:dukan/auth/capabilities.dart';
import 'package:dukan/config/config_keys.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/device_config_dao.dart';
import 'package:dukan/sync/local_repository.dart';

// --- FakeConfigResolver ---------------------------------------------------

/// Test stand-in for ConfigResolver. Defaults to production values
/// (e.g. `use_local_db = true`); pass [values] to override specific
/// keys (e.g. `{'use_local_db': false}` for OFF-mode tests).
class FakeConfigResolver extends ConfigResolver {
  /// Uses a never-completing database future so the underlying
  /// DeviceConfigDao never actually opens a connection. Tests
  /// only exercise [resolve] / [rawOverride], which we override
  /// directly off the in-memory [values] map.
  FakeConfigResolver({Map<String, dynamic>? values})
    : _values = values ?? const {},
      super(
        shopApi: FakeShopApi(),
        deviceConfigDao: DeviceConfigDao(Completer().future.then((v) => v)),
      );

  final Map<String, dynamic> _values;

  @override
  T resolve<T>(ConfigKey<T> key) {
    if (_values.containsKey(key.name)) return _values[key.name] as T;
    return key.defaultValue;
  }

  @override
  Object? rawOverride(String keyName) {
    if (_values.containsKey(keyName)) return _values[keyName];
    return null;
  }
}

// --- FakeLocalRepository --------------------------------------------------

/// Thin test stand-in for [LocalRepository]. Delegates reads to the
/// supplied [FakeShopApi] so queue-path tests can opt into the
/// useLocalDb=true branch without wiring a real sqflite database
/// or seeding mirror rows.
///
/// The screens' read path calls:
///   - `searchItems(query, shopId)` → forwards to FakeShopApi.onSearchItems
///   - `toItemSearchResult(item, screen)` → reuses the cached
///     ItemSearchResult from the most recent searchItems call (so
///     prices/units round-trip exactly)
///   - `searchParties(query, shopId, typeCode)` → forwards
///   - `expenseCategories(shopId)` → forwards
///   - `applyProjectionLines` → no-op (queue tests don't assert on
///     projections)
///
/// Everything else falls back to the base [LocalRepository], which
/// will throw if you try to call it (no real DB). Add overrides
/// only when a test actually needs them.
class FakeLocalRepository extends LocalRepository {
  // Back onto the per-test seeded in-memory AppDatabase (flutter_test_config)
  // so non-overridden writes (e.g. the #390 optimistic mirror writes the
  // mutation path makes) complete as no-ops against empty tables instead of
  // hanging on a never-completing future. Reads stay overridden below.
  FakeLocalRepository({required this.shopApi}) : super(AppDatabase.instance());

  final FakeShopApi shopApi;

  final Map<String, ItemSearchResult> _itemCache = {};

  @override
  Future<List<LocalShopItem>> searchItems(
    String query, {
    required String shopId,
    int limit = 50,
    String rankBy = 'name',
  }) async {
    final results = await shopApi.searchItems(
      shopId: shopId,
      query: query,
      screen: 'sale',
      locale: 'en',
    );
    final out = <LocalShopItem>[];
    for (final r in results) {
      final id = r.shopItemId;
      if (id == null) continue; // global-catalog hits aren't usable here
      _itemCache[id] = r;
      out.add(
        LocalShopItem(
          shopItemId: id,
          shopId: shopId,
          itemId: r.itemId,
          displayName: r.displayName,
          categoryId: null,
          baseUnitCode: r.baseUnitCode,
          currentStock: r.currentStock ?? 0,
          avgCost: 0,
          reorderThreshold: r.reorderThreshold,
          isActive: true,
          serverUpdatedAtMs: 0,
        ),
      );
    }
    return out;
  }

  @override
  Future<ItemSearchResult> toItemSearchResult(
    LocalShopItem item, {
    required String screen,
  }) async {
    final cached = _itemCache[item.shopItemId];
    if (cached != null) return cached;
    return ItemSearchResult(
      shopItemId: item.shopItemId,
      itemId: item.itemId,
      displayName: item.displayName,
      baseUnitCode: item.baseUnitCode,
      baseUnitLabel: item.baseUnitCode,
      defaultShopItemUnitId: '${item.shopItemId}-base',
      defaultUnitCode: item.baseUnitCode,
      defaultUnitLabel: item.baseUnitCode,
      defaultUnitConversionToBase: 1,
      defaultUnitSalePrice: null,
      defaultUnitLastCost: null,
      currentStock: item.currentStock.toDouble(),
      reorderThreshold: item.reorderThreshold?.toDouble(),
      packagingLabel: item.baseUnitCode,
      isActivated: true,
      rankReason: null,
    );
  }

  @override
  Future<List<LocalParty>> searchParties(
    String query, {
    required String shopId,
    required String typeCode,
    int limit = 50,
    String rankBy = 'balance',
  }) async {
    final results = await shopApi.searchParties(
      shopId: shopId,
      query: query,
      type: typeCode,
      limit: limit,
      rankBy: rankBy,
    );
    return results
        .map(
          (p) => LocalParty(
            partyId: p.id,
            shopId: shopId,
            name: p.name,
            phone: p.phone,
            typeCode: p.typeCode,
            receivable: p.receivable,
            payable: p.payable,
            isActive: true,
            serverUpdatedAtMs: 0,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<LocalExpenseCategory>> expenseCategories({
    required String shopId,
  }) async {
    final cats = await shopApi.listExpenseCategories(
      shopId: shopId,
      locale: 'en',
    );
    return cats
        .map(
          (c) => LocalExpenseCategory(
            categoryId: c.id,
            shopId: shopId,
            code: c.code,
            name: c.name,
            isActive: true,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> applyProjectionLines({
    required String pendingPostId,
    required List<ProjectionLine> lines,
  }) async {
    // No-op — queue-path tests don't assert on projection rows.
  }
}

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
    String? pendingEmail,
    Capabilities? capabilities,
  }) : _shops = shops,
       _selectedShop = selectedShop,
       _session = session,
       _initialized = initialized,
       _shopsLoading = shopsLoading,
       _shopLoadFailed = shopLoadFailed,
       _pendingPhone = pendingPhone,
       _pendingEmail = pendingEmail,
       _capabilities = capabilities ?? Capabilities.empty();

  List<ShopSummary> _shops;
  ShopSummary? _selectedShop;
  Session? _session;
  bool _initialized;
  bool _shopsLoading;
  bool _shopLoadFailed;
  String? _pendingPhone;
  String? _pendingEmail;
  Capabilities _capabilities;

  Future<void> Function(String rawPhone)? onSendOtp;
  Future<void> Function(String rawEmail)? onSendEmailOtp;
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

  void setPendingEmail(String? email) {
    _pendingEmail = email;
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
  String? get pendingEmail => _pendingEmail;
  @override
  Capabilities get capabilities => _capabilities;

  /// Test helper for capability-gated widget tests.
  void setCapabilities(Capabilities capabilities) {
    _capabilities = capabilities;
    notifyListeners();
  }

  @override
  Future<void> start() async {
    _initialized = true;
    notifyListeners();
  }

  @override
  Future<void> sendOtp(String rawPhone) async {
    if (onSendOtp != null) return onSendOtp!(rawPhone);
    _pendingPhone = rawPhone;
    _pendingEmail = null;
    notifyListeners();
  }

  @override
  Future<void> sendEmailOtp(String rawEmail) async {
    if (onSendEmailOtp != null) return onSendEmailOtp!(rawEmail);
    _pendingEmail = rawEmail;
    _pendingPhone = null;
    notifyListeners();
  }

  @override
  Future<void> verifyOtp(String token) async {
    if (onVerifyOtp != null) return onVerifyOtp!(token);
    _pendingPhone = null;
    _pendingEmail = null;
    notifyListeners();
  }

  @override
  void cancelOtp() {
    if (_pendingPhone == null && _pendingEmail == null) return;
    _pendingPhone = null;
    _pendingEmail = null;
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
    _pendingEmail = null;
    notifyListeners();
  }
}

// --- FakeShopApi ----------------------------------------------------------

class FakeShopApi implements ShopApi {
  FakeShopApi();

  /// Backdating (#5): the occurredAt of the most recent post* call (null =
  /// today). Lets widget tests assert a backdated date flowed to the post.
  DateTime? lastOccurredAt;

  Future<List<TemplateOption>> Function()? onListAvailableTemplates;
  Future<void> Function(String shopId, String templateId)? onApplyTemplate;
  Future<void> Function(String shopId)? onCompleteSetup;
  Future<void> Function(String shopId)? onDismissOnboarding;
  final List<String> dismissOnboardingCalls = [];
  Future<String> Function(String shopId, String itemId)? onEnsureShopItem;
  Future<void> Function(String shopId, String shopItemUnitId, num? salePrice)?
  onSetShopItemUnitSalePrice;
  final List<({String shopItemUnitId, num? salePrice})>
  setShopItemUnitSalePriceCalls = [];
  Future<List<ReceiveUnitOption>> Function(
    String shopId,
    String shopItemId,
    String screen,
  )?
  onListShopItemUnits;
  Future<CreateShopItemResult> Function(
    String shopId,
    String name,
    String languageCode,
    String baseUnitCode,
    num? salePrice,
    String? categoryId,
    String? soldUnitCode,
    num? soldConversion,
    String defaultSide,
  )?
  onCreateShopItem;
  final List<
    ({
      String name,
      String languageCode,
      String baseUnitCode,
      num? salePrice,
      String? categoryId,
      String? soldUnitCode,
      num? soldConversion,
      String defaultSide,
      String? shopItemId,
      String? baseUnitId,
      String? soldUnitId,
      String? clientOpId,
    })
  >
  createShopItemCalls = [];
  Future<String> Function(
    String shopId,
    String shopItemId,
    String unitCode,
    num conversionToBase,
    num? salePrice,
  )?
  onCreateShopItemUnit;
  final List<
      ({
        String shopItemId,
        String unitCode,
        num conversionToBase,
        String? shopItemUnitId,
        String? clientOpId,
      })> createShopItemUnitCalls = [];
  Future<String> Function(
    String shopId,
    String shopItemId,
    String aliasText,
    String? languageCode,
    bool isDisplay,
    String source,
  )?
  onAddShopItemAlias;
  Future<List<ShopItemSummary>> Function(
    String shopId,
    String? categoryId,
    String? query,
    String? locale,
  )?
  onListShopItems;
  Future<ShopItemDetail> Function(
    String shopId,
    String shopItemId,
    String? locale,
  )?
  onGetShopItem;
  Future<List<PackagingSuggestion>> Function(
    String shopId,
    String shopItemId,
    String baseUnitCode,
    String? categoryId,
    String? locale,
    int limit,
  )?
  onSuggestItemPackagings;
  Future<List<CategoryUnitSuggestion>> Function(
    String categoryId,
    String? locale,
    int limit,
  )?
  onSuggestCategoryUnits;
  Future<NewItemOptions> Function(String? categoryId, String? locale)?
  onFetchNewItemOptions;
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
      ({
        String name,
        String? phone,
        String typeCode,
        String? partyId,
        String? clientOpId,
      })> createPartyCalls = [];
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

  /// Records the client-minted `txnId` passed to each postSale call.
  final List<String?> postSaleTxnIds = <String?>[];
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

  /// Records the client-minted `txnId` passed to each postReceive call.
  final List<String?> postReceiveTxnIds = <String?>[];
  Future<String> Function(
    String shopId,
    String partyId,
    String direction,
    num amount,
    String paymentMethodCode,
    String clientOpId,
    String? notes,
    List<PaymentAllocationInput>? allocations,
  )?
  onPostPayment;

  /// Records the client-minted `paymentId` passed to each postPayment call.
  final List<String?> postPaymentTxnIds = <String?>[];
  Future<List<UnpaidInvoice>> Function(
    String shopId,
    String partyId,
    String direction,
  )?
  onListUnpaidInvoices;
  Future<List<PostedAllocation>> Function(String shopId, String paymentId)?
  onListPaymentAllocations;
  Future<List<ExpenseCategoryOption>> Function(String shopId, String? locale)?
  onListExpenseCategories;
  Future<List<SaleSummary>> Function(
    String shopId,
    DateTime? before,
    int limit,
  )?
  onListSales;
  Future<SaleSummary?> Function(String shopId, String txnId)? onGetSale;
  Future<List<SaleLineDetail>> Function(String shopId, String txnId)?
  onGetSaleLines;
  Future<String> Function(
    String shopId,
    String txnId,
    String clientOpId,
    num? refundAmount,
  )?
  onVoidSale;
  final List<({String txnId, num? refundAmount})> voidSaleCalls = [];
  Future<List<ReceiveSummary>> Function(
    String shopId,
    DateTime? before,
    int limit,
  )?
  onListReceives;
  Future<List<ExpenseSummary>> Function(
    String shopId,
    DateTime? before,
    int limit,
  )?
  onListExpenses;
  Future<List<PaymentSummary>> Function(
    String shopId,
    DateTime? before,
    int limit,
  )?
  onListPayments;
  Future<ReceiveSummary?> Function(String shopId, String txnId)? onGetReceive;
  Future<List<ReceiveLineDetail>> Function(String shopId, String txnId)?
  onGetReceiveLines;
  Future<PaymentDetail?> Function(String shopId, String paymentId)?
  onGetPayment;
  Future<String> Function(String shopId, String paymentId, String clientOpId)?
  onVoidPayment;
  final List<String> voidPaymentCalls = [];
  Future<String> Function(String shopId, String txnId, String clientOpId)?
  onVoidReceive;
  final List<String> voidReceiveCalls = [];
  Future<String> Function(String shopId, String txnId, String clientOpId)?
  onVoidExpense;
  final List<String> voidExpenseCalls = [];
  Future<ExpenseSummary?> Function(String shopId, String txnId)? onGetExpense;
  Future<String> Function(
    String shopId,
    String categoryId,
    num amount,
    String paymentMethodCode,
    String clientOpId,
    String? notes,
  )?
  onPostExpense;

  /// Records the client-minted `txnId` passed to each postExpense call
  /// (the onPostExpense callback keeps its original arg list, so existing
  /// tests compile unchanged).
  final List<String?> postExpenseTxnIds = <String?>[];
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
  Future<void> dismissOnboarding({required String shopId}) async {
    dismissOnboardingCalls.add(shopId);
    if (onDismissOnboarding != null) return onDismissOnboarding!(shopId);
  }

  List<String> listUserShopCapabilitiesResult = const <String>[];

  @override
  Future<List<String>> listUserShopCapabilities({
    required String shopId,
  }) async {
    return List<String>.from(listUserShopCapabilitiesResult);
  }

  Future<List<AuditEntry>> Function(
    String shopId,
    String entityType,
    String entityId,
    int limit,
  )?
  onListAuditEntriesForEntity;

  @override
  Future<List<AuditEntry>> listAuditEntriesForEntity({
    required String shopId,
    required String entityType,
    required String entityId,
    int limit = 5,
  }) async {
    if (onListAuditEntriesForEntity != null) {
      return onListAuditEntriesForEntity!(shopId, entityType, entityId, limit);
    }
    return const <AuditEntry>[];
  }

  @override
  Future<String> ensureShopItem({
    required String shopId,
    required String itemId,
  }) async {
    if (onEnsureShopItem != null) {
      return onEnsureShopItem!(shopId, itemId);
    }
    return 'fake-shop-item-${itemId.hashCode}';
  }

  @override
  Future<void> setShopItemUnitSalePrice({
    required String shopId,
    required String shopItemUnitId,
    required num? salePrice,
    String? clientOpId,
  }) async {
    setShopItemUnitSalePriceCalls.add((
      shopItemUnitId: shopItemUnitId,
      salePrice: salePrice,
    ));
    if (onSetShopItemUnitSalePrice != null) {
      return onSetShopItemUnitSalePrice!(shopId, shopItemUnitId, salePrice);
    }
  }

  @override
  Future<List<ReceiveUnitOption>> listShopItemUnits({
    required String shopId,
    required String shopItemId,
    String screen = 'receive',
  }) async {
    if (onListShopItemUnits != null) {
      return onListShopItemUnits!(shopId, shopItemId, screen);
    }
    // Sensible default: base unit (kg) + a 25 kg bag packaging, so
    // tests not explicitly setting onListShopItemUnits still exercise
    // the picker. The 25 kg bag is the default-for-screen on both
    // 'sale' and 'receive' contexts.
    return const [
      ReceiveUnitOption(
        shopItemUnitId: 'unit-kg',
        unitCode: 'kg',
        unitLabel: 'Kg',
        packagingLabel: 'Kg',
        conversionToBase: 1,
        salePrice: null,
        lastCost: null,
        isDefault: false,
        isBaseUnit: true,
      ),
      ReceiveUnitOption(
        shopItemUnitId: 'unit-bag-25',
        unitCode: 'bag',
        unitLabel: 'Bag',
        packagingLabel: '25 Kg Bag',
        conversionToBase: 25,
        salePrice: null,
        lastCost: null,
        isDefault: true,
        isBaseUnit: false,
      ),
    ];
  }

  @override
  Future<CreateShopItemResult> createShopItem({
    required String shopId,
    required String name,
    required String languageCode,
    required String baseUnitCode,
    num? salePrice,
    String? categoryId,
    String? soldUnitCode,
    num? soldConversion,
    String defaultSide = 'sale',
    String? shopItemId,
    String? baseUnitId,
    String? soldUnitId,
    String? clientOpId,
  }) async {
    createShopItemCalls.add((
      name: name,
      languageCode: languageCode,
      baseUnitCode: baseUnitCode,
      salePrice: salePrice,
      categoryId: categoryId,
      soldUnitCode: soldUnitCode,
      soldConversion: soldConversion,
      defaultSide: defaultSide,
      shopItemId: shopItemId,
      baseUnitId: baseUnitId,
      soldUnitId: soldUnitId,
      clientOpId: clientOpId,
    ));
    if (onCreateShopItem != null) {
      return onCreateShopItem!(
        shopId,
        name,
        languageCode,
        baseUnitCode,
        salePrice,
        categoryId,
        soldUnitCode,
        soldConversion,
        defaultSide,
      );
    }
    // Mimic the server (0095): honour the client-supplied ids when present.
    final id = shopItemId ?? 'fake-shop-item-${name.hashCode}';
    final defaultUnit = soldUnitId ??
        baseUnitId ??
        'fake-default-unit-${name.hashCode}';
    return (shopItemId: id, defaultShopItemUnitId: defaultUnit);
  }

  @override
  Future<String> createShopItemUnit({
    required String shopId,
    required String shopItemId,
    required String unitCode,
    required num conversionToBase,
    num? salePrice,
    String? shopItemUnitId,
    String? clientOpId,
  }) async {
    createShopItemUnitCalls.add((
      shopItemId: shopItemId,
      unitCode: unitCode,
      conversionToBase: conversionToBase,
      shopItemUnitId: shopItemUnitId,
      clientOpId: clientOpId,
    ));
    if (onCreateShopItemUnit != null) {
      return onCreateShopItemUnit!(
        shopId,
        shopItemId,
        unitCode,
        conversionToBase,
        salePrice,
      );
    }
    // Mimic the server (0094): honour the client-supplied id when present.
    return shopItemUnitId ??
        'fake-shop-item-unit-${unitCode.hashCode}-'
            '${conversionToBase.hashCode}';
  }

  final List<
    ({
      String shopItemId,
      String aliasText,
      String? languageCode,
      bool isDisplay,
    })
  >
  addShopItemAliasCalls = [];

  @override
  Future<String> addShopItemAlias({
    required String shopId,
    required String shopItemId,
    required String aliasText,
    String? languageCode,
    bool isDisplay = false,
    String source = 'manual',
    String? clientOpId,
  }) async {
    addShopItemAliasCalls.add((
      shopItemId: shopItemId,
      aliasText: aliasText,
      languageCode: languageCode,
      isDisplay: isDisplay,
    ));
    if (onAddShopItemAlias != null) {
      return onAddShopItemAlias!(
        shopId,
        shopItemId,
        aliasText,
        languageCode,
        isDisplay,
        source,
      );
    }
    return 'fake-alias-${aliasText.hashCode}';
  }

  @override
  Future<List<ShopItemSummary>> listShopItems({
    required String shopId,
    String? categoryId,
    String? query,
    String? locale,
  }) async {
    if (onListShopItems != null) {
      return onListShopItems!(shopId, categoryId, query, locale);
    }
    return const [];
  }

  @override
  Future<ShopItemDetail> getShopItem({
    required String shopId,
    required String shopItemId,
    String? locale,
  }) async {
    if (onGetShopItem != null) {
      return onGetShopItem!(shopId, shopItemId, locale);
    }
    // Default empty detail — tests that exercise getShopItem set the
    // callback explicitly.
    return const ShopItemDetail(
      header: ShopItemSummary(
        shopItemId: 'fake-shop-item',
        itemId: null,
        displayName: 'Fake Item',
        categoryName: null,
        baseUnitCode: 'piece',
        baseUnitLabel: 'Piece',
        currentStock: 0,
        unitCount: 1,
        isActive: true,
      ),
      units: [],
      aliases: [],
      barcodes: [],
    );
  }

  @override
  Future<List<PackagingSuggestion>> suggestItemPackagings({
    required String shopId,
    required String shopItemId,
    required String baseUnitCode,
    String? categoryId,
    String? locale,
    int limit = 8,
  }) async {
    if (onSuggestItemPackagings != null) {
      return onSuggestItemPackagings!(
        shopId,
        shopItemId,
        baseUnitCode,
        categoryId,
        locale,
        limit,
      );
    }
    return const [];
  }

  @override
  Future<List<CategoryUnitSuggestion>> suggestCategoryUnits({
    required String categoryId,
    String? locale,
    int limit = 5,
  }) async {
    if (onSuggestCategoryUnits != null) {
      return onSuggestCategoryUnits!(categoryId, locale, limit);
    }
    return const [];
  }

  @override
  Future<NewItemOptions> fetchNewItemOptions({
    String? categoryId,
    String? locale,
  }) async {
    if (onFetchNewItemOptions != null) {
      return onFetchNewItemOptions!(categoryId, locale);
    }
    return const NewItemOptions(baseUnits: [], packagedUnits: []);
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
    String rankBy = 'balance',
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
    String? partyId,
    String? clientOpId,
  }) async {
    createPartyCalls.add((
      name: name,
      phone: phone,
      typeCode: typeCode,
      partyId: partyId,
      clientOpId: clientOpId,
    ));
    if (onCreateParty != null) {
      return onCreateParty!(shopId, name, phone, typeCode);
    }
    // Mimic the server (0093): honour the client-supplied id when present.
    return partyId ?? 'fake-party-${name.hashCode}';
  }

  Future<void> Function(
    String shopId,
    String partyId,
    String name,
    String? phone,
  )?
  onUpdateParty;
  final List<({String partyId, String name, String? phone})> updatePartyCalls =
      [];

  @override
  Future<void> updateParty({
    required String shopId,
    required String partyId,
    required String name,
    String? phone,
    String? clientOpId,
  }) async {
    updatePartyCalls.add((partyId: partyId, name: name, phone: phone));
    if (onUpdateParty != null) {
      return onUpdateParty!(shopId, partyId, name, phone);
    }
  }

  Future<String> Function(
    String shopId,
    String partyId,
    num amount,
    String direction,
  )?
  onPostOpeningPartyBalance;
  final List<({String partyId, num amount, String direction})>
  postOpeningPartyBalanceCalls = [];

  @override
  Future<String> postOpeningPartyBalance({
    required String shopId,
    required String partyId,
    required num amount,
    required String direction,
    String? clientOpId,
    String? notes,
  }) async {
    postOpeningPartyBalanceCalls.add((
      partyId: partyId,
      amount: amount,
      direction: direction,
    ));
    if (onPostOpeningPartyBalance != null) {
      return onPostOpeningPartyBalance!(shopId, partyId, amount, direction);
    }
    return 'fake-opening-${partyId.hashCode}';
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
    DateTime? occurredAt,
    String? txnId,
  }) async {
    lastOccurredAt = occurredAt;
    postSaleTxnIds.add(txnId);
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
  String bonoStoragePath(
    String shopId,
    String documentId,
    String fileExtension,
  ) => '$shopId/documents/$documentId/image.$fileExtension';

  Future<void> Function(
    String shopId,
    String documentId,
    String storagePath,
    Uint8List bytes,
    String mimeType,
  )?
  onUploadBonoImageAt;
  final List<
    ({String shopId, String documentId, String storagePath, int sizeBytes})
  >
  uploadBonoImageAtCalls = [];

  @override
  Future<void> uploadBonoImageAt({
    required String shopId,
    required String documentId,
    required String storagePath,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    uploadBonoImageAtCalls.add((
      shopId: shopId,
      documentId: documentId,
      storagePath: storagePath,
      sizeBytes: bytes.length,
    ));
    if (onUploadBonoImageAt != null) {
      await onUploadBonoImageAt!(
        shopId,
        documentId,
        storagePath,
        bytes,
        mimeType,
      );
    }
  }

  Future<List<BonoSuggestion>> Function(
    String shopId,
    String documentId,
    String supplierPartyId,
    String? locale,
  )?
  onSuggestReceiveLinesFromBono;

  @override
  Future<List<BonoSuggestion>> suggestReceiveLinesFromBono({
    required String shopId,
    required String documentId,
    required String supplierPartyId,
    String? locale,
  }) async {
    if (onSuggestReceiveLinesFromBono != null) {
      return onSuggestReceiveLinesFromBono!(
        shopId,
        documentId,
        supplierPartyId,
        locale,
      );
    }
    return const [];
  }

  final List<
    ({
      String documentId,
      String supplierPartyId,
      String rawText,
      String shopItemId,
      String shopItemUnitId,
    })
  >
  confirmBonoSuggestionCalls = [];

  @override
  Future<void> confirmBonoSuggestion({
    required String shopId,
    required String documentId,
    required String supplierPartyId,
    required String rawText,
    required String shopItemId,
    required String shopItemUnitId,
    double? confidence,
  }) async {
    confirmBonoSuggestionCalls.add((
      documentId: documentId,
      supplierPartyId: supplierPartyId,
      rawText: rawText,
      shopItemId: shopItemId,
      shopItemUnitId: shopItemUnitId,
    ));
  }

  Future<String?> Function(String storagePath)? onSignBonoUrl;

  @override
  Future<String?> signBonoUrl(String storagePath, {int expiresSeconds = 300}) async {
    if (onSignBonoUrl != null) return onSignBonoUrl!(storagePath);
    return 'https://example.test/signed/$storagePath';
  }

  Future<TodaySummary> Function(String shopId, String? locale)?
  onGetTodaySummary;

  @override
  Future<TodaySummary> getTodaySummary({
    required String shopId,
    String? locale,
  }) async {
    if (onGetTodaySummary != null) return onGetTodaySummary!(shopId, locale);
    return const TodaySummary(
      salesToday: 0,
      receivablesTotal: 0,
      payablesTotal: 0,
      lowStockCount: 0,
    );
  }

  ProfitReport Function(DateTime? from, DateTime? to)? onGetProfitReport;

  @override
  Future<ProfitReport> getProfitReport({
    required String shopId,
    DateTime? from,
    DateTime? to,
  }) async {
    if (onGetProfitReport != null) return onGetProfitReport!(from, to);
    return const ProfitReport(
      revenue: 0,
      cogs: 0,
      grossProfit: 0,
      expenseTotal: 0,
      netProfit: 0,
      saleCount: 0,
      expenseCount: 0,
    );
  }

  StockReport Function()? onGetStockReport;

  @override
  Future<StockReport> getStockReport({required String shopId}) async {
    if (onGetStockReport != null) return onGetStockReport!();
    return const StockReport(itemCount: 0, stockValue: 0, lowStockCount: 0);
  }

  Future<List<PartyBalanceRow>> Function(String shopId, String? locale)?
  onListReceivables;

  @override
  Future<List<PartyBalanceRow>> listReceivables({
    required String shopId,
    String? locale,
  }) async {
    if (onListReceivables != null) return onListReceivables!(shopId, locale);
    return const [];
  }

  Future<List<PartyBalanceRow>> Function(String shopId, String? locale)?
  onListPayables;

  @override
  Future<List<PartyBalanceRow>> listPayables({
    required String shopId,
    String? locale,
  }) async {
    if (onListPayables != null) return onListPayables!(shopId, locale);
    return const [];
  }

  Future<List<LowStockRow>> Function(String shopId, String? locale)?
  onListLowStock;

  @override
  Future<List<LowStockRow>> listLowStock({
    required String shopId,
    String? locale,
  }) async {
    if (onListLowStock != null) return onListLowStock!(shopId, locale);
    return const [];
  }

  Future<PartyDetail> Function(String shopId, String partyId, int limit)?
  onGetPartyDetail;

  @override
  Future<PartyDetail> getPartyDetail({
    required String shopId,
    required String partyId,
    int limit = 20,
  }) async {
    if (onGetPartyDetail != null) {
      return onGetPartyDetail!(shopId, partyId, limit);
    }
    return PartyDetail(
      header: PartyDetailHeader(
        id: partyId,
        name: 'Test Party',
        phone: null,
        typeCode: 'customer',
        receivable: 0,
        payable: 0,
        isActive: true,
      ),
      sales: const [],
      receives: const [],
      payments: const [],
    );
  }

  Future<List<CategoryOption>> Function(String? locale)? onListCategories;

  @override
  Future<String> createShopCategory({
    required String shopId,
    required String categoryId,
    required String name,
    String? clientOpId,
  }) async => categoryId;

  @override
  Future<void> renameShopCategory({
    required String shopId,
    required String categoryId,
    required String name,
    String? clientOpId,
  }) async {}

  @override
  Future<void> setShopCategoryActive({
    required String shopId,
    required String categoryId,
    required bool isActive,
    String? clientOpId,
  }) async {}

  Future<void> Function(String partyId, bool isActive)? onSetPartyActive;

  @override
  Future<void> setPartyActive({
    required String shopId,
    required String partyId,
    required bool isActive,
    String? clientOpId,
  }) async {
    await onSetPartyActive?.call(partyId, isActive);
  }

  Future<void> Function(String shopItemId, bool isActive)? onSetShopItemActive;

  @override
  Future<void> setShopItemActive({
    required String shopId,
    required String shopItemId,
    required bool isActive,
  }) async {
    await onSetShopItemActive?.call(shopItemId, isActive);
  }

  @override
  Future<String> createExpenseCategory({
    required String shopId,
    required String categoryId,
    required String name,
    String? clientOpId,
  }) async => categoryId;

  @override
  Future<void> renameExpenseCategory({
    required String shopId,
    required String categoryId,
    required String name,
    String? clientOpId,
  }) async {}

  @override
  Future<void> setExpenseCategoryActive({
    required String shopId,
    required String categoryId,
    required bool isActive,
    String? clientOpId,
  }) async {}

  @override
  Future<List<CategoryOption>> listCategories({
    String? locale,
    String? shopId,
  }) async {
    if (onListCategories != null) return onListCategories!(locale);
    return const [
      CategoryOption(id: 'cat-grocery', code: 'grocery', name: 'Grocery'),
      CategoryOption(id: 'cat-staples', code: 'staples', name: 'Staples'),
    ];
  }

  @override
  Future<List<ExpenseCategoryOption>> listExpenseCategories({
    required String shopId,
    String? locale,
  }) async {
    if (onListExpenseCategories != null) {
      return onListExpenseCategories!(shopId, locale);
    }
    return const [
      ExpenseCategoryOption(id: 'cat-rent', code: 'rent', name: 'Rent'),
      ExpenseCategoryOption(
        id: 'cat-electricity',
        code: 'electricity',
        name: 'Electricity',
      ),
      ExpenseCategoryOption(id: 'cat-other', code: 'other', name: 'Other'),
    ];
  }

  @override
  Future<String> postExpense({
    required String shopId,
    required String expenseCategoryId,
    required num amount,
    required String paymentMethodCode,
    required String clientOpId,
    String? notes,
    DateTime? occurredAt,
    String? txnId,
  }) async {
    lastOccurredAt = occurredAt;
    postExpenseTxnIds.add(txnId);
    if (onPostExpense != null) {
      return onPostExpense!(
        shopId,
        expenseCategoryId,
        amount,
        paymentMethodCode,
        clientOpId,
        notes,
      );
    }
    return 'fake-expense-${clientOpId.hashCode}';
  }

  @override
  Future<List<SaleSummary>> listSales({
    required String shopId,
    DateTime? before,
    int limit = 50,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? partyId,
  }) async {
    if (onListSales != null) return onListSales!(shopId, before, limit);
    return const [];
  }

  @override
  Future<SaleSummary?> getSale({
    required String shopId,
    required String txnId,
  }) async {
    if (onGetSale != null) return onGetSale!(shopId, txnId);
    return null;
  }

  @override
  Future<List<SaleLineDetail>> getSaleLines({
    required String shopId,
    required String txnId,
  }) async {
    if (onGetSaleLines != null) return onGetSaleLines!(shopId, txnId);
    return const [];
  }

  @override
  Future<String> voidSale({
    required String shopId,
    required String txnId,
    required String clientOpId,
    num? refundAmount,
  }) async {
    voidSaleCalls.add((txnId: txnId, refundAmount: refundAmount));
    if (onVoidSale != null) {
      return onVoidSale!(shopId, txnId, clientOpId, refundAmount);
    }
    return 'fake-reversal-${clientOpId.hashCode}';
  }

  @override
  Future<List<ReceiveSummary>> listReceives({
    required String shopId,
    DateTime? before,
    int limit = 50,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? partyId,
  }) async {
    if (onListReceives != null) return onListReceives!(shopId, before, limit);
    return const [];
  }

  @override
  Future<List<ExpenseSummary>> listExpenses({
    required String shopId,
    DateTime? before,
    int limit = 50,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? categoryId,
    String? locale,
  }) async {
    if (onListExpenses != null) return onListExpenses!(shopId, before, limit);
    return const [];
  }

  @override
  Future<List<PaymentSummary>> listPayments({
    required String shopId,
    DateTime? before,
    int limit = 50,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? partyId,
    String? direction,
  }) async {
    if (onListPayments != null) return onListPayments!(shopId, before, limit);
    return const [];
  }

  Future<List<PartySearchResult>> Function(
    String shopId,
    String query,
    String? type,
    bool hasBalanceOnly,
  )?
  onListParties;

  @override
  Future<List<PartySearchResult>> listParties({
    required String shopId,
    String query = '',
    String? type,
    bool hasBalanceOnly = false,
    int limit = 200,
  }) async {
    if (onListParties != null) {
      return onListParties!(shopId, query, type, hasBalanceOnly);
    }
    return const [];
  }

  @override
  Future<ReceiveSummary?> getReceive({
    required String shopId,
    required String txnId,
  }) async {
    if (onGetReceive != null) return onGetReceive!(shopId, txnId);
    return null;
  }

  @override
  Future<List<ReceiveLineDetail>> getReceiveLines({
    required String shopId,
    required String txnId,
  }) async {
    if (onGetReceiveLines != null) return onGetReceiveLines!(shopId, txnId);
    return const [];
  }

  @override
  Future<PaymentDetail?> getPayment({
    required String shopId,
    required String paymentId,
  }) async {
    if (onGetPayment != null) return onGetPayment!(shopId, paymentId);
    return null;
  }

  @override
  Future<String> voidPayment({
    required String shopId,
    required String paymentId,
    required String clientOpId,
  }) async {
    voidPaymentCalls.add(paymentId);
    if (onVoidPayment != null) {
      return onVoidPayment!(shopId, paymentId, clientOpId);
    }
    return 'fake-pay-marker-${clientOpId.hashCode}';
  }

  @override
  Future<String> voidReceive({
    required String shopId,
    required String txnId,
    required String clientOpId,
  }) async {
    voidReceiveCalls.add(txnId);
    if (onVoidReceive != null) {
      return onVoidReceive!(shopId, txnId, clientOpId);
    }
    return 'fake-reversal-${clientOpId.hashCode}';
  }

  @override
  Future<String> voidExpense({
    required String shopId,
    required String txnId,
    required String clientOpId,
  }) async {
    voidExpenseCalls.add(txnId);
    if (onVoidExpense != null) {
      return onVoidExpense!(shopId, txnId, clientOpId);
    }
    return 'fake-exp-reversal-${clientOpId.hashCode}';
  }

  @override
  Future<ExpenseSummary?> getExpense({
    required String shopId,
    required String txnId,
    String? locale,
  }) async {
    if (onGetExpense != null) return onGetExpense!(shopId, txnId);
    return null;
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
    List<PaymentAllocationInput>? allocations,
    DateTime? occurredAt,
    String? paymentId,
  }) async {
    lastOccurredAt = occurredAt;
    postPaymentTxnIds.add(paymentId);
    if (onPostPayment != null) {
      return onPostPayment!(
        shopId,
        partyId,
        direction,
        amount,
        paymentMethodCode,
        clientOpId,
        notes,
        allocations,
      );
    }
    return 'fake-payment-${clientOpId.hashCode}';
  }

  @override
  Future<List<UnpaidInvoice>> listUnpaidInvoices({
    required String shopId,
    required String partyId,
    required String direction,
  }) async {
    if (onListUnpaidInvoices != null) {
      return onListUnpaidInvoices!(shopId, partyId, direction);
    }
    return const [];
  }

  @override
  Future<List<PostedAllocation>> listPaymentAllocations({
    required String shopId,
    required String paymentId,
  }) async {
    if (onListPaymentAllocations != null) {
      return onListPaymentAllocations!(shopId, paymentId);
    }
    return const [];
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
    DateTime? occurredAt,
    String? txnId,
  }) async {
    lastOccurredAt = occurredAt;
    postReceiveTxnIds.add(txnId);
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
  Future<Map<String, int>> currencyDecimals() async {
    final currencies = await listCurrencies();
    return {for (final c in currencies) c.code: 2};
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

  Future<void> Function(
    String shopId,
    String shopItemId,
    num? reorderThreshold,
  )?
  onSetShopItemReorderThreshold;
  final List<({String shopItemId, num? reorderThreshold})>
  setShopItemReorderThresholdCalls = [];

  @override
  Future<void> setShopItemReorderThreshold({
    required String shopId,
    required String shopItemId,
    required num? reorderThreshold,
  }) async {
    setShopItemReorderThresholdCalls.add((
      shopItemId: shopItemId,
      reorderThreshold: reorderThreshold,
    ));
    if (onSetShopItemReorderThreshold != null) {
      return onSetShopItemReorderThreshold!(
        shopId,
        shopItemId,
        reorderThreshold,
      );
    }
  }

  Future<void> Function(
    String shopId,
    String shopItemUnitId,
    bool isDefaultSale,
    bool isDefaultReceive,
  )?
  onSetShopItemUnitDefaultFlags;
  final List<
    ({String shopItemUnitId, bool isDefaultSale, bool isDefaultReceive})
  >
  setShopItemUnitDefaultFlagsCalls = [];

  @override
  Future<void> setShopItemUnitDefaultFlags({
    required String shopId,
    required String shopItemUnitId,
    required bool isDefaultSale,
    required bool isDefaultReceive,
    String? clientOpId,
  }) async {
    setShopItemUnitDefaultFlagsCalls.add((
      shopItemUnitId: shopItemUnitId,
      isDefaultSale: isDefaultSale,
      isDefaultReceive: isDefaultReceive,
    ));
    if (onSetShopItemUnitDefaultFlags != null) {
      return onSetShopItemUnitDefaultFlags!(
        shopId,
        shopItemUnitId,
        isDefaultSale,
        isDefaultReceive,
      );
    }
  }

  @override
  Future<ShopSummary?> fetchShop(String shopId) async {
    if (onFetchShop != null) return onFetchShop!(shopId);
    return null;
  }

  Future<void> Function(String shopId, String shopItemId, String? categoryId)?
  onSetShopItemCategory;
  final List<({String shopItemId, String? categoryId})>
  setShopItemCategoryCalls = [];

  @override
  Future<void> setShopItemCategory({
    required String shopId,
    required String shopItemId,
    required String? categoryId,
    String? clientOpId,
  }) async {
    setShopItemCategoryCalls.add((
      shopItemId: shopItemId,
      categoryId: categoryId,
    ));
    if (onSetShopItemCategory != null) {
      return onSetShopItemCategory!(shopId, shopItemId, categoryId);
    }
  }

  Future<void> Function(String shopId, String shopItemUnitId)?
  onDeactivateShopItemUnit;
  final List<String> deactivateShopItemUnitCalls = [];

  @override
  Future<void> deactivateShopItemUnit({
    required String shopId,
    required String shopItemUnitId,
  }) async {
    deactivateShopItemUnitCalls.add(shopItemUnitId);
    if (onDeactivateShopItemUnit != null) {
      return onDeactivateShopItemUnit!(shopId, shopItemUnitId);
    }
  }

  /// Recorded calls from #350 (mobile switched the product detail's
  /// trash icon from deactivateShopItemUnit to this RPC). Defaults to
  /// returning 'removed' so tests see the "empty packaging hard-
  /// deleted" path; override `removeOrDisableShopItemUnitResult` to
  /// simulate the soft-disable branch.
  final List<String> removeOrDisableShopItemUnitCalls = [];
  String removeOrDisableShopItemUnitResult = 'removed';

  @override
  Future<String> removeOrDisableShopItemUnit({
    required String shopId,
    required String shopItemUnitId,
    String? clientOpId,
  }) async {
    removeOrDisableShopItemUnitCalls.add(shopItemUnitId);
    return removeOrDisableShopItemUnitResult;
  }

  final List<String> removeShopItemAliasCalls = [];

  @override
  Future<void> removeShopItemAlias({
    required String shopId,
    required String aliasId,
    String? clientOpId,
  }) async {
    removeShopItemAliasCalls.add(aliasId);
  }

  final List<({String shopItemUnitId, String barcode, bool isPrimary})>
  addShopItemBarcodeCalls = [];
  Future<String> Function(
    String shopId,
    String shopItemUnitId,
    String barcode,
    bool isPrimary,
  )?
  onAddShopItemBarcode;

  @override
  Future<String> addShopItemBarcode({
    required String shopId,
    required String shopItemUnitId,
    required String barcode,
    bool isPrimary = false,
    String? symbology,
    String? clientOpId,
  }) async {
    addShopItemBarcodeCalls.add((
      shopItemUnitId: shopItemUnitId,
      barcode: barcode,
      isPrimary: isPrimary,
    ));
    if (onAddShopItemBarcode != null) {
      return onAddShopItemBarcode!(shopId, shopItemUnitId, barcode, isPrimary);
    }
    return 'fake-barcode-${barcode.hashCode}';
  }

  final List<String> removeShopItemBarcodeCalls = [];

  @override
  Future<void> removeShopItemBarcode({
    required String shopId,
    required String barcodeId,
    String? clientOpId,
  }) async {
    removeShopItemBarcodeCalls.add(barcodeId);
  }

  final List<String> setPrimaryShopItemBarcodeCalls = [];

  @override
  Future<void> setPrimaryShopItemBarcode({
    required String shopId,
    required String barcodeId,
    String? clientOpId,
  }) async {
    setPrimaryShopItemBarcodeCalls.add(barcodeId);
  }

  Future<ProductVelocity> Function(
    String shopId,
    int periodDays,
    int limit,
    String? locale,
  )?
  onListProductVelocity;

  @override
  Future<ProductVelocity> listProductVelocity({
    required String shopId,
    int periodDays = 7,
    int limit = 10,
    String? locale,
  }) async {
    if (onListProductVelocity != null) {
      return onListProductVelocity!(shopId, periodDays, limit, locale);
    }
    return const ProductVelocity(top: [], dead: []);
  }

  final List<
    ({
      String reasonCode,
      String shopItemId,
      num quantityDelta,
      num? unitCost,
      String? notes,
    })
  >
  postInventoryAdjustmentCalls = [];
  Future<String> Function(
    String shopId,
    String reasonCode,
    String shopItemId,
    num quantityDelta,
    num? unitCost,
    String? notes,
  )?
  onPostInventoryAdjustment;

  @override
  Future<String> postInventoryAdjustment({
    required String shopId,
    required String reasonCode,
    required String shopItemId,
    required num quantityDelta,
    num? unitCost,
    String? clientOpId,
    String? notes,
  }) async {
    postInventoryAdjustmentCalls.add((
      reasonCode: reasonCode,
      shopItemId: shopItemId,
      quantityDelta: quantityDelta,
      unitCost: unitCost,
      notes: notes,
    ));
    if (onPostInventoryAdjustment != null) {
      return onPostInventoryAdjustment!(
        shopId,
        reasonCode,
        shopItemId,
        quantityDelta,
        unitCost,
        notes,
      );
    }
    return 'fake-adj-${shopItemId.hashCode}';
  }

  // ----- Onboarding-form RPCs (0065 + 0066) ---------------------------------
  // Default stubs; tests can override the on... hooks below.

  Future<void> Function({
    required String shopId,
    required String partyId,
    required String shopItemUnitId,
    required num unitCost,
  })?
  onSetSupplierItemUnitCost;
  final List<({String partyId, String shopItemUnitId, num unitCost})>
  setSupplierItemUnitCostCalls = [];

  @override
  Future<void> setSupplierItemUnitCost({
    required String shopId,
    required String partyId,
    required String shopItemUnitId,
    required num unitCost,
  }) async {
    setSupplierItemUnitCostCalls.add((
      partyId: partyId,
      shopItemUnitId: shopItemUnitId,
      unitCost: unitCost,
    ));
    if (onSetSupplierItemUnitCost != null) {
      await onSetSupplierItemUnitCost!(
        shopId: shopId,
        partyId: partyId,
        shopItemUnitId: shopItemUnitId,
        unitCost: unitCost,
      );
    }
  }

  Future<List<SimilarShopItem>> Function({
    required String shopId,
    required String query,
    String? baseUnitCode,
    String locale,
  })?
  onFindSimilarShopItems;

  @override
  Future<List<SimilarShopItem>> findSimilarShopItems({
    required String shopId,
    required String query,
    String? baseUnitCode,
    String locale = 'en',
  }) async {
    if (onFindSimilarShopItems != null) {
      return onFindSimilarShopItems!(
        shopId: shopId,
        query: query,
        baseUnitCode: baseUnitCode,
        locale: locale,
      );
    }
    return const [];
  }

  Future<void> Function({
    required String shopId,
    required String shopItemId,
    required String? imagePath,
  })?
  onSetShopItemImagePath;
  final List<({String shopItemId, String? imagePath})>
  setShopItemImagePathCalls = [];

  @override
  Future<void> setShopItemImagePath({
    required String shopId,
    required String shopItemId,
    required String? imagePath,
  }) async {
    setShopItemImagePathCalls.add((
      shopItemId: shopItemId,
      imagePath: imagePath,
    ));
    if (onSetShopItemImagePath != null) {
      await onSetShopItemImagePath!(
        shopId: shopId,
        shopItemId: shopItemId,
        imagePath: imagePath,
      );
    }
  }

  Future<String> Function({
    required String shopId,
    required String shopItemId,
    required Uint8List bytes,
    required String mimeType,
    required String fileExtension,
  })?
  onUploadShopItemImage;

  @override
  Future<String> uploadShopItemImage({
    required String shopId,
    required String shopItemId,
    required Uint8List bytes,
    required String mimeType,
    required String fileExtension,
  }) async {
    if (onUploadShopItemImage != null) {
      return onUploadShopItemImage!(
        shopId: shopId,
        shopItemId: shopItemId,
        bytes: bytes,
        mimeType: mimeType,
        fileExtension: fileExtension,
      );
    }
    return '$shopId/items/$shopItemId/image.$fileExtension';
  }

  @override
  Future<String> postOpeningStockAdjustment({
    required String shopId,
    required String shopItemId,
    required num baseQuantity,
    num? unitCost,
    String? clientOpId,
    String? notes,
  }) => postInventoryAdjustment(
    shopId: shopId,
    reasonCode: 'opening',
    shopItemId: shopItemId,
    quantityDelta: baseQuantity,
    unitCost: unitCost,
    clientOpId: clientOpId,
    notes: notes,
  );

  // ----- Hierarchical config (Phase 3) ---------------------------------
  /// Pre-populate the rows the resolver will see. Empty list = no
  /// org-scoped overrides (resolver falls through to defaults).
  List<PlatformConfigEntry> platformConfigEntries =
      const <PlatformConfigEntry>[];

  /// Records of every call to setPlatformConfig.
  final List<({String? orgId, String key, Object value})>
  setPlatformConfigCalls = [];

  @override
  Future<List<PlatformConfigEntry>> getPlatformConfigForShop({
    required String shopId,
  }) async {
    return platformConfigEntries;
  }

  @override
  Future<void> setPlatformConfig({
    required String? orgId,
    required String key,
    required Object value,
  }) async {
    setPlatformConfigCalls.add((orgId: orgId, key: key, value: value));
  }

  /// Records of every call to setAuditOriginalActor (#368).
  final List<({String shopId, String entityId, String originalActorUserId})>
  setAuditOriginalActorCalls = [];

  @override
  Future<void> setAuditOriginalActor({
    required String shopId,
    required String entityId,
    required String originalActorUserId,
  }) async {
    setAuditOriginalActorCalls.add((
      shopId: shopId,
      entityId: entityId,
      originalActorUserId: originalActorUserId,
    ));
  }

  // --- Sync RPCs (#373) ---------------------------------------------------

  Future<Map<String, dynamic>> Function({required String shopId, bool force})?
  onGetShopFullSync;
  final List<({String shopId, bool force})> getShopFullSyncCalls = [];

  Future<Map<String, dynamic>> Function({
    required String shopId,
    required DateTime since,
  })?
  onGetShopItemsDelta;
  final List<({String shopId, DateTime since})> getShopItemsDeltaCalls = [];

  Future<Map<String, dynamic>> Function({
    required String shopId,
    required DateTime since,
  })?
  onGetPartiesDelta;
  final List<({String shopId, DateTime since})> getPartiesDeltaCalls = [];

  Future<Map<String, dynamic>> Function({
    required String shopId,
    required DateTime since,
  })?
  onGetCategoriesDelta;
  final List<({String shopId, DateTime since})> getCategoriesDeltaCalls = [];

  Future<Map<String, dynamic>> Function({
    required String shopId,
    required DateTime since,
    int limit,
  })?
  onGetTransactionsDelta;
  final List<({String shopId, DateTime since, int limit})>
  getTransactionsDeltaCalls = [];

  Future<Map<String, dynamic>> Function({
    required String shopId,
    required DateTime since,
  })?
  onGetUnpaidInvoicesDelta;
  final List<({String shopId, DateTime since})> getUnpaidInvoicesDeltaCalls =
      [];

  @override
  Future<Map<String, dynamic>> getShopFullSync({
    required String shopId,
    bool force = false,
  }) async {
    getShopFullSyncCalls.add((shopId: shopId, force: force));
    final hook = onGetShopFullSync;
    if (hook == null) return const <String, dynamic>{};
    return hook(shopId: shopId, force: force);
  }

  @override
  Future<Map<String, dynamic>> getShopItemsDelta({
    required String shopId,
    required DateTime since,
  }) async {
    getShopItemsDeltaCalls.add((shopId: shopId, since: since));
    final hook = onGetShopItemsDelta;
    if (hook == null) return const <String, dynamic>{};
    return hook(shopId: shopId, since: since);
  }

  @override
  Future<Map<String, dynamic>> getPartiesDelta({
    required String shopId,
    required DateTime since,
  }) async {
    getPartiesDeltaCalls.add((shopId: shopId, since: since));
    final hook = onGetPartiesDelta;
    if (hook == null) return const <String, dynamic>{};
    return hook(shopId: shopId, since: since);
  }

  @override
  Future<Map<String, dynamic>> getCategoriesDelta({
    required String shopId,
    required DateTime since,
  }) async {
    getCategoriesDeltaCalls.add((shopId: shopId, since: since));
    final hook = onGetCategoriesDelta;
    if (hook == null) return const <String, dynamic>{};
    return hook(shopId: shopId, since: since);
  }

  @override
  Future<Map<String, dynamic>> getTransactionsDelta({
    required String shopId,
    required DateTime since,
    int limit = 200,
  }) async {
    getTransactionsDeltaCalls.add((shopId: shopId, since: since, limit: limit));
    final hook = onGetTransactionsDelta;
    if (hook == null) return const <String, dynamic>{};
    return hook(shopId: shopId, since: since, limit: limit);
  }

  @override
  Future<Map<String, dynamic>> getUnpaidInvoicesDelta({
    required String shopId,
    required DateTime since,
  }) async {
    getUnpaidInvoicesDeltaCalls.add((shopId: shopId, since: since));
    final hook = onGetUnpaidInvoicesDelta;
    if (hook == null) return const <String, dynamic>{};
    return hook(shopId: shopId, since: since);
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
  DateTime? onboardingDismissedAt,
  bool hideSettlementLegs = true,
}) => ShopSummary(
  id: id,
  name: name,
  setupStatus: setupStatus,
  currencyCode: currencyCode,
  currencySymbol: currencySymbol,
  defaultLanguageCode: defaultLanguageCode,
  timezone: timezone,
  // Default to "already dismissed" (now). Tests for the onboarding
  // screen pass `onboardingDismissedAt: null` explicitly.
  onboardingDismissedAt:
      onboardingDismissedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
  hideSettlementLegs: hideSettlementLegs,
);

TemplateOption fakeTemplate({
  String id = 'template-1',
  String code = 'grocery',
  String name = 'Grocery',
}) => TemplateOption(id: id, code: code, name: name);

/// Activated shop item search result — has both shopItemId and a
/// default packaging. Use for tests that exercise the fast-tap path.
ItemSearchResult fakeActivatedItem({
  String shopItemId = 'shop-item-1',
  String? itemId = 'item-1',
  String displayName = 'Bariis Basmati',
  String baseUnitCode = 'kg',
  String baseUnitLabel = 'Kg',
  String defaultShopItemUnitId = 'shop-item-unit-1',
  String defaultUnitCode = 'kg',
  String defaultUnitLabel = 'Kg',
  double defaultUnitConversionToBase = 1,
  double? defaultUnitSalePrice = 1.5,
  double? defaultUnitLastCost,
  double? currentStock = 50,
  String? packagingLabel = 'Kg',
  String? rankReason = 'alias_prefix_locale',
}) => ItemSearchResult(
  shopItemId: shopItemId,
  itemId: itemId,
  displayName: displayName,
  baseUnitCode: baseUnitCode,
  baseUnitLabel: baseUnitLabel,
  defaultShopItemUnitId: defaultShopItemUnitId,
  defaultUnitCode: defaultUnitCode,
  defaultUnitLabel: defaultUnitLabel,
  defaultUnitConversionToBase: defaultUnitConversionToBase,
  defaultUnitSalePrice: defaultUnitSalePrice,
  defaultUnitLastCost: defaultUnitLastCost,
  currentStock: currentStock,
  packagingLabel: packagingLabel,
  isActivated: true,
  rankReason: rankReason,
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

/// Unactivated catalog-only result — shopItemId + defaultShopItemUnitId
/// are null, isActivated is false. Use for tests that exercise the
/// "tap auto-activates via ensureShopItem" path.
ItemSearchResult fakeCatalogCandidate({
  String itemId = 'item-2',
  String displayName = 'Caano qalalan',
  String baseUnitCode = 'packet',
  String baseUnitLabel = 'Packet',
}) => ItemSearchResult(
  shopItemId: null,
  itemId: itemId,
  displayName: displayName,
  baseUnitCode: baseUnitCode,
  baseUnitLabel: baseUnitLabel,
  defaultShopItemUnitId: null,
  defaultUnitCode: null,
  defaultUnitLabel: null,
  defaultUnitConversionToBase: null,
  defaultUnitSalePrice: null,
  defaultUnitLastCost: null,
  currentStock: null,
  packagingLabel: null,
  isActivated: false,
  rankReason: 'alias_prefix_locale',
);

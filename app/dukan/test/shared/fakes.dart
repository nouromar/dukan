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
import 'package:dukan/auth/capabilities.dart';

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
    Capabilities? capabilities,
  }) : _shops = shops,
       _selectedShop = selectedShop,
       _session = session,
       _initialized = initialized,
       _shopsLoading = shopsLoading,
       _shopLoadFailed = shopLoadFailed,
       _pendingPhone = pendingPhone,
       _capabilities = capabilities ?? Capabilities.empty();

  List<ShopSummary> _shops;
  ShopSummary? _selectedShop;
  Session? _session;
  bool _initialized;
  bool _shopsLoading;
  bool _shopLoadFailed;
  String? _pendingPhone;
  Capabilities _capabilities;

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
  Future<void> Function(String shopId)? onDismissOnboarding;
  final List<String> dismissOnboardingCalls = [];
  Future<String> Function(String shopId, String itemId)?
  onEnsureShopItem;
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
  final List<({String shopItemId, String unitCode, num conversionToBase})>
  createShopItemUnitCalls = [];
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
  Future<List<ShopItemStock>> Function(
    String shopId,
    List<String> shopItemIds,
    String? locale,
  )?
  onFetchShopItemStocks;
  final List<({String shopId, List<String> shopItemIds})>
  fetchShopItemStocksCalls = [];
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
  Future<String> Function(String shopId, String txnId, String clientOpId)?
  onVoidReceive;
  final List<String> voidReceiveCalls = [];
  Future<String> Function(
    String shopId,
    String categoryId,
    num amount,
    String paymentMethodCode,
    String clientOpId,
    String? notes,
  )?
  onPostExpense;
  Future<List<ReferenceOption>> Function()? onListLanguages;
  Future<List<ReferenceOption>> Function()? onListCurrencies;
  Future<void> Function(
    String shopId, {
    String? name,
    String? currencyCode,
    String? defaultLanguageCode,
    String? timezone,
    bool? lowStockWarningEnabled,
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
  }) async {
    setShopItemUnitSalePriceCalls
        .add((shopItemUnitId: shopItemUnitId, salePrice: salePrice));
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
    final id = 'fake-shop-item-${name.hashCode}';
    return (
      shopItemId: id,
      defaultShopItemUnitId: 'fake-default-unit-${name.hashCode}',
    );
  }

  @override
  Future<String> createShopItemUnit({
    required String shopId,
    required String shopItemId,
    required String unitCode,
    required num conversionToBase,
    num? salePrice,
  }) async {
    createShopItemUnitCalls.add((
      shopItemId: shopItemId,
      unitCode: unitCode,
      conversionToBase: conversionToBase,
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
    return 'fake-shop-item-unit-${unitCode.hashCode}-'
        '${conversionToBase.hashCode}';
  }

  final List<
      ({
        String shopItemId,
        String aliasText,
        String? languageCode,
        bool isDisplay,
      })> addShopItemAliasCalls = [];

  @override
  Future<String> addShopItemAlias({
    required String shopId,
    required String shopItemId,
    required String aliasText,
    String? languageCode,
    bool isDisplay = false,
    String source = 'manual',
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
  Future<List<ShopItemStock>> fetchShopItemStocks({
    required String shopId,
    required List<String> shopItemIds,
    String? locale,
  }) async {
    fetchShopItemStocksCalls
        .add((shopId: shopId, shopItemIds: shopItemIds));
    if (onFetchShopItemStocks != null) {
      return onFetchShopItemStocks!(shopId, shopItemIds, locale);
    }
    return const [];
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
    postOpeningPartyBalanceCalls
        .add((partyId: partyId, amount: amount, direction: direction));
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

  Future<String> Function(
    String shopId,
    Uint8List bytes,
    String mimeType,
    String fileExtension,
  )?
  onUploadBonoImage;
  final List<({String shopId, int sizeBytes, String mimeType})>
  uploadBonoImageCalls = [];

  @override
  Future<String> uploadBonoImage({
    required String shopId,
    required Uint8List bytes,
    required String mimeType,
    required String fileExtension,
  }) async {
    uploadBonoImageCalls.add((
      shopId: shopId,
      sizeBytes: bytes.length,
      mimeType: mimeType,
    ));
    if (onUploadBonoImage != null) {
      return onUploadBonoImage!(shopId, bytes, mimeType, fileExtension);
    }
    return 'fake-doc-id';
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
  Future<List<CategoryOption>> listCategories({String? locale}) async {
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
  }) async {
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
    bool? lowStockWarningEnabled,
  }) async {
    if (onUpdateShopDefaults != null) {
      return onUpdateShopDefaults!(
        shopId,
        name: name,
        currencyCode: currencyCode,
        defaultLanguageCode: defaultLanguageCode,
        timezone: timezone,
        lowStockWarningEnabled: lowStockWarningEnabled,
      );
    }
  }

  Future<void> Function(
    String shopId,
    String shopItemId,
    num? reorderThreshold,
  )?
  onSetShopItemReorderThreshold;
  final List<
    ({String shopItemId, num? reorderThreshold})
  > setShopItemReorderThresholdCalls = [];

  @override
  Future<void> setShopItemReorderThreshold({
    required String shopId,
    required String shopItemId,
    required num? reorderThreshold,
  }) async {
    setShopItemReorderThresholdCalls
        .add((shopItemId: shopItemId, reorderThreshold: reorderThreshold));
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
    ({
      String shopItemUnitId,
      bool isDefaultSale,
      bool isDefaultReceive,
    })
  >
  setShopItemUnitDefaultFlagsCalls = [];

  @override
  Future<void> setShopItemUnitDefaultFlags({
    required String shopId,
    required String shopItemUnitId,
    required bool isDefaultSale,
    required bool isDefaultReceive,
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
  }) async {
    setShopItemCategoryCalls
        .add((shopItemId: shopItemId, categoryId: categoryId));
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

  final List<String> removeShopItemAliasCalls = [];

  @override
  Future<void> removeShopItemAlias({
    required String shopId,
    required String aliasId,
  }) async {
    removeShopItemAliasCalls.add(aliasId);
  }

  final List<
      ({
        String shopItemUnitId,
        String barcode,
        bool isPrimary,
      })> addShopItemBarcodeCalls = [];
  Future<String> Function(
    String shopId,
    String shopItemUnitId,
    String barcode,
    bool isPrimary,
  )? onAddShopItemBarcode;

  @override
  Future<String> addShopItemBarcode({
    required String shopId,
    required String shopItemUnitId,
    required String barcode,
    bool isPrimary = false,
    String? symbology,
  }) async {
    addShopItemBarcodeCalls.add((
      shopItemUnitId: shopItemUnitId,
      barcode: barcode,
      isPrimary: isPrimary,
    ));
    if (onAddShopItemBarcode != null) {
      return onAddShopItemBarcode!(
          shopId, shopItemUnitId, barcode, isPrimary);
    }
    return 'fake-barcode-${barcode.hashCode}';
  }

  final List<String> removeShopItemBarcodeCalls = [];

  @override
  Future<void> removeShopItemBarcode({
    required String shopId,
    required String barcodeId,
  }) async {
    removeShopItemBarcodeCalls.add(barcodeId);
  }

  final List<String> setPrimaryShopItemBarcodeCalls = [];

  @override
  Future<void> setPrimaryShopItemBarcode({
    required String shopId,
    required String barcodeId,
  }) async {
    setPrimaryShopItemBarcodeCalls.add(barcodeId);
  }

  Future<ProductVelocity> Function(
    String shopId,
    int periodDays,
    int limit,
    String? locale,
  )? onListProductVelocity;

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
      })> postInventoryAdjustmentCalls = [];
  Future<String> Function(
    String shopId,
    String reasonCode,
    String shopItemId,
    num quantityDelta,
    num? unitCost,
    String? notes,
  )? onPostInventoryAdjustment;

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
  bool lowStockWarningEnabled = false,
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
  lowStockWarningEnabled: lowStockWarningEnabled,
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

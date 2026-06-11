// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Dukan';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageSomali => 'Somali';

  @override
  String get homeHint => 'Choose today\'s job';

  @override
  String get sale => 'Sale';

  @override
  String get receive => 'Receive';

  @override
  String get payment => 'Payment';

  @override
  String get expense => 'Expense';

  @override
  String get cash => 'CASH';

  @override
  String get debt => 'DEBT';

  @override
  String get confirm => 'CONFIRM';

  @override
  String get searchItems => 'Search items';

  @override
  String get favorites => 'Favorites';

  @override
  String get cart => 'CART';

  @override
  String itemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: '0 items',
    );
    return '$_temp0';
  }

  @override
  String get total => 'Total';

  @override
  String get savedUndo => 'Saved.';

  @override
  String get undo => 'Undo';

  @override
  String get quantity => 'Qty';

  @override
  String get price => 'Price';

  @override
  String get optionalPrice => 'Price override';

  @override
  String get addToCart => 'ADD TO CART';

  @override
  String get cancel => 'Cancel';

  @override
  String get customerDebt => 'Customer for debt';

  @override
  String get searchCustomers => 'Search customers';

  @override
  String get emptySaleHint =>
      'Tap item tiles to add. Long-press for quantity or price.';

  @override
  String get receiveTitle => 'Receive';

  @override
  String get supplierFirst => 'Pick supplier first';

  @override
  String get recentSuppliers => 'Recent suppliers';

  @override
  String get searchSuppliers => 'Search suppliers';

  @override
  String get newSupplier => '+ New supplier';

  @override
  String get newSupplierStub =>
      'New supplier stub — name and phone in production.';

  @override
  String get repeatLastBono => 'Repeat last receive';

  @override
  String get bonoAttached => 'Bono attached';

  @override
  String get bonoAttachTooltip => 'Attach bono photo';

  @override
  String get bonoAttachedTooltip => 'Bono attached — tap to replace';

  @override
  String get bonoAttachCamera => 'Take photo';

  @override
  String get bonoAttachGallery => 'Choose from gallery';

  @override
  String get bonoAttachedToast => 'Bono photo attached';

  @override
  String get bonoAttachFailedMessage => 'Could not attach the bono. Try again.';

  @override
  String get partyDetailTitle => 'Party';

  @override
  String get partyDetailLoadFailedMessage => 'Could not load this party.';

  @override
  String get partyDetailReceivableLabel => 'They owe you';

  @override
  String get partyDetailPayableLabel => 'You owe them';

  @override
  String get partyDetailPayButton => 'PAY';

  @override
  String get partyDetailSalesHeader => 'Sales';

  @override
  String get partyDetailReceivesHeader => 'Receives';

  @override
  String get partyDetailPaymentsHeader => 'Payments';

  @override
  String get homeTodayHeader => 'Today';

  @override
  String get homeSalesTodayLabel => 'Sales today';

  @override
  String get homeReceivablesLabel => 'Customers owe you';

  @override
  String get homePayablesLabel => 'You owe suppliers';

  @override
  String get homeLowStockLabel => 'Low stock';

  @override
  String homeLowStockCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'none',
    );
    return '$_temp0';
  }

  @override
  String get receivablesTitle => 'Customers owe you';

  @override
  String get receivablesEmptyMessage => 'No one owes you right now.';

  @override
  String get payablesTitle => 'You owe suppliers';

  @override
  String get payablesEmptyMessage => 'You don\'t owe anyone right now.';

  @override
  String get lowStockReportTitle => 'Low stock';

  @override
  String get lowStockReportEmptyMessage => 'Nothing is running low.';

  @override
  String get reportLoadFailedMessage =>
      'Could not load. Pull down to try again.';

  @override
  String get filterTooltip => 'Filter';

  @override
  String get filterSheetTitle => 'Filter';

  @override
  String get filterApplyButton => 'APPLY';

  @override
  String get filterResetButton => 'Reset';

  @override
  String get dateRangeToday => 'Today';

  @override
  String get dateRangeWeek => 'Last 7 days';

  @override
  String get dateRangeMonth => 'This month';

  @override
  String get dateRangeAll => 'All time';

  @override
  String get dateRangeCustom => 'Custom…';

  @override
  String get filterPartyLabel => 'Party';

  @override
  String get filterPartyAny => 'Anyone';

  @override
  String get filterIncludeVoided => 'Include voided';

  @override
  String get filterHideVoided => 'Hide voided';

  @override
  String get filterCategoryLabel => 'Category';

  @override
  String get filterCategoryAny => 'All categories';

  @override
  String get filterLowStockOnly => 'Low stock only';

  @override
  String get filterNoPriceOnly => 'No price yet';

  @override
  String get saleHistorySearchHint => 'Search sales';

  @override
  String get receiveHistorySearchHint => 'Search receives';

  @override
  String get receivablesSearchHint => 'Search customer';

  @override
  String get payablesSearchHint => 'Search supplier';

  @override
  String get lowStockSearchHint => 'Search product';

  @override
  String get filterChipDateAll => 'All time';

  @override
  String filterChipParty(String name) {
    return 'Party: $name';
  }

  @override
  String get filterChipVoided => 'Including voided';

  @override
  String get filterChipHideVoided => 'Hiding voided';

  @override
  String filterChipCategory(String name) {
    return '$name';
  }

  @override
  String get filterChipLowStock => 'Low stock';

  @override
  String get filterChipNoPrice => 'No price';

  @override
  String get drawerHistoryHeader => 'HISTORY';

  @override
  String get drawerSalesHistory => 'Sales history';

  @override
  String get drawerReceiveHistory => 'Receive history';

  @override
  String get drawerExpenseHistory => 'Expense history';

  @override
  String get expenseHistoryTitle => 'Expenses';

  @override
  String get expenseHistoryLoadFailedMessage =>
      'Could not load expenses. Pull down to try again.';

  @override
  String get expenseHistoryEmptyMessage => 'No expenses yet.';

  @override
  String get drawerPaymentHistory => 'Payment history';

  @override
  String get paymentHistoryTitle => 'Payments';

  @override
  String get paymentHistoryLoadFailedMessage =>
      'Could not load payments. Pull down to try again.';

  @override
  String get paymentHistoryEmptyMessage => 'No payments yet.';

  @override
  String get paymentHistoryNoParty => 'Cash';

  @override
  String get paymentHistoryRefundBadge => 'refund';

  @override
  String get paymentDirectionLabel => 'Direction';

  @override
  String get paymentDirectionAny => 'Any direction';

  @override
  String get paymentDirectionInbound => 'Customer paid you';

  @override
  String get paymentDirectionOutbound => 'You paid supplier';

  @override
  String get drawerParties => 'Customers & suppliers';

  @override
  String get partiesTitle => 'Customers & suppliers';

  @override
  String get partiesSearchHint => 'Search by name or phone';

  @override
  String get partiesLoadFailedMessage =>
      'Could not load. Pull down to try again.';

  @override
  String get partiesEmptyMessage => 'No customers or suppliers yet.';

  @override
  String partiesEmptyForQuery(String query) {
    return 'No matches for \"$query\".';
  }

  @override
  String get partiesHasBalanceChip => 'Has balance only';

  @override
  String get partyTypeLabel => 'Type';

  @override
  String get partyTypeAny => 'Anyone';

  @override
  String get partyTypeCustomer => 'Customer';

  @override
  String get partyTypeSupplier => 'Supplier';

  @override
  String get partyTypeBoth => 'Customer + supplier';

  @override
  String get partiesAddButton => 'Add';

  @override
  String get partyNewOpeningReceivableLabel => 'Opening balance (they owe you)';

  @override
  String get partyNewOpeningPayableLabel => 'Opening balance (you owe them)';

  @override
  String get partyNewOpeningBalanceHelper =>
      'Optional — for old debts from before this app.';

  @override
  String get partyDetailEditTooltip => 'Edit name & phone';

  @override
  String get drawerPeopleHeader => 'PEOPLE';

  @override
  String get drawerCustomers => 'Customers';

  @override
  String get drawerSuppliers => 'Suppliers';

  @override
  String get customersTitle => 'Customers';

  @override
  String get suppliersTitle => 'Suppliers';

  @override
  String get customersSearchHint => 'Search customer';

  @override
  String get suppliersSearchHint => 'Search supplier';

  @override
  String get customersAddButton => 'Add';

  @override
  String get suppliersAddButton => 'Add';

  @override
  String get customersHasBalanceChip => 'Has receivable only';

  @override
  String get suppliersHasBalanceChip => 'Has payable only';

  @override
  String get customersHeadlineLabel => 'Customers owe you';

  @override
  String get suppliersHeadlineLabel => 'You owe suppliers';

  @override
  String customersHeadlineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count customers with balance',
      one: '1 customer with balance',
      zero: 'No customers with balance',
    );
    return '$_temp0';
  }

  @override
  String suppliersHeadlineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count suppliers with balance',
      one: '1 supplier with balance',
      zero: 'No suppliers with balance',
    );
    return '$_temp0';
  }

  @override
  String get peopleSortLabel => 'Sort';

  @override
  String get peopleSortByReceivable => 'By debt (most first)';

  @override
  String get peopleSortByPayable => 'By debt (most first)';

  @override
  String get peopleSortByName => 'Alphabetical';

  @override
  String stockAdjustTitle(String name) {
    return 'Adjust $name stock';
  }

  @override
  String stockAdjustCurrentLabel(String amount, String unit) {
    return 'Current: $amount $unit';
  }

  @override
  String get stockAdjustModeOpening => 'Opening';

  @override
  String get stockAdjustModeAdd => 'Add';

  @override
  String get stockAdjustModeSubtract => 'Subtract';

  @override
  String get stockAdjustModeSetExact => 'Set exact';

  @override
  String get stockAdjustModeOpeningHelper =>
      'Stock you had on day one — before this app.';

  @override
  String get stockAdjustModeAddHelper =>
      'Stock received outside a bono (e.g. found behind the shelf).';

  @override
  String get stockAdjustModeSubtractHelper =>
      'Spoilage, waste, or any loss you can\'t refund.';

  @override
  String get stockAdjustModeSetExactHelper =>
      'Type the new total after a physical count.';

  @override
  String stockAdjustAmountLabel(String unit) {
    return 'Amount ($unit)';
  }

  @override
  String get stockAdjustNotesLabel => 'Note (optional)';

  @override
  String stockAdjustPreview(String amount, String unit) {
    return 'New stock: $amount $unit';
  }

  @override
  String get stockAdjustSaveButton => 'SAVE';

  @override
  String get stockAdjustFailedMessage =>
      'Could not save the adjustment. Try again.';

  @override
  String get stockAdjustInvalidAmountMessage => 'Enter a valid amount.';

  @override
  String get barcodeAddDialogTitle => 'Add barcode';

  @override
  String get barcodeAddDialogHint => 'e.g. 6291100123456';

  @override
  String get barcodeAddDialogSetPrimary => 'Make primary';

  @override
  String get barcodeChipMakePrimary => 'Make primary';

  @override
  String get barcodeChipRemove => 'Remove';

  @override
  String get barcodeAddTooltip => 'Add barcode';

  @override
  String get barcodeNoneForBase => '— loose / by weight';

  @override
  String get aliasAddDialogTitle => 'Add another name';

  @override
  String get aliasAddDialogHint => 'e.g. Riis (Somali)';

  @override
  String get aliasAddDialogLanguage => 'Language';

  @override
  String get aliasChipRemove => 'Remove';

  @override
  String get aliasAddTooltip => 'Add other name';

  @override
  String get languageNone => 'Any';

  @override
  String productsHeadline(int total, int low, int noPrice) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total products',
      one: '1 product',
      zero: 'No products yet',
    );
    return '$_temp0 · $low low · $noPrice without price';
  }

  @override
  String get productsSortLabel => 'Sort';

  @override
  String get productsSortByName => 'Name (A–Z)';

  @override
  String get productsSortByStockLow => 'Stock (low first)';

  @override
  String get drawerProductsHeader => 'PRODUCTS';

  @override
  String get drawerTopMovers => 'Top movers';

  @override
  String get topMoversTitle => 'Top movers';

  @override
  String topMoversPeriodSubtitle(int days) {
    return 'Last $days days';
  }

  @override
  String get topMoversPeriodTooltip => 'Period';

  @override
  String topMoversPeriodOption(int days) {
    return 'Last $days days';
  }

  @override
  String get topMoversTopSegment => 'Top sellers';

  @override
  String get topMoversDeadSegment => 'Dead stock (no sales)';

  @override
  String get topMoversEmptyMessage => 'No sales in this period.';

  @override
  String get drawerReportsHeader => 'REPORTS';

  @override
  String get drawerReceivables => 'Customers owe you';

  @override
  String get drawerPayables => 'You owe suppliers';

  @override
  String get drawerLowStock => 'Low stock';

  @override
  String get drawerSetupHeader => 'SETUP';

  @override
  String get drawerProducts => 'Products';

  @override
  String get drawerSettings => 'Settings';

  @override
  String get drawerOpenTooltip => 'Menu';

  @override
  String get attachBono => 'Attach bono photo';

  @override
  String receiveFrom(Object supplier) {
    return 'Receive from $supplier';
  }

  @override
  String get item => 'Item';

  @override
  String get searchItem => 'Search item';

  @override
  String get unit => 'Unit';

  @override
  String get cost => 'Cost';

  @override
  String get perUnit => 'per unit';

  @override
  String get line => 'line';

  @override
  String get lineTotal => 'Line total';

  @override
  String get addLine => 'ADD LINE';

  @override
  String linesSoFar(Object count) {
    return 'Lines so far: $count';
  }

  @override
  String get bonoTotal => 'Bono total';

  @override
  String get paidNow => 'Paid now';

  @override
  String get credit => 'Credit';

  @override
  String get paidAll => 'Paid all';

  @override
  String get mismatchWarning =>
      'Bono total differs from lines — OK to continue.';

  @override
  String get chooseItemWarning => 'Choose item, qty, and cost.';

  @override
  String get confirmReceive => 'CONFIRM RECEIVE';

  @override
  String get numberDone => 'DONE';

  @override
  String get clear => 'CLEAR';

  @override
  String get backspace => 'DEL';

  @override
  String get paymentTitle => 'Customer payment';

  @override
  String get pickCustomer => 'Pick customer';

  @override
  String get amount => 'Amount';

  @override
  String get confirmPayment => 'CONFIRM PAYMENT';

  @override
  String get expenseTitle => 'Expense';

  @override
  String get category => 'Category';

  @override
  String get confirmExpense => 'CONFIRM EXPENSE';

  @override
  String get rent => 'Rent';

  @override
  String get power => 'Power';

  @override
  String get salary => 'Salary';

  @override
  String get water => 'Water';

  @override
  String get transport => 'Transport';

  @override
  String get other => 'Other';

  @override
  String get comingSoon => 'Mock screen saved. Undo?';

  @override
  String get supabaseConfigTitle => 'Connect Dukan to Supabase';

  @override
  String get supabaseConfigMessage =>
      'Add Supabase URL and anon key to use login. You can still open the prototype screens.';

  @override
  String get supabaseConfigCommand =>
      'flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...';

  @override
  String get openPrototype => 'Open prototype';

  @override
  String get loginTitle => 'Login';

  @override
  String get loginHeadline => 'Use your phone number';

  @override
  String get loginBody =>
      'We will send a one-time code. Dukan can deliver it by WhatsApp from the backend.';

  @override
  String get phoneNumberLabel => 'Phone number';

  @override
  String get sendOtpButton => 'SEND CODE';

  @override
  String get verifyOtpTitle => 'Enter code';

  @override
  String get verifyOtpHeadline => 'Check your phone';

  @override
  String verifyOtpBody(Object phone) {
    return 'Enter the code sent to $phone.';
  }

  @override
  String get otpCodeLabel => 'Code';

  @override
  String get verifyOtpButton => 'VERIFY';

  @override
  String get changePhoneButton => 'Change phone number';

  @override
  String get ownerOnboardingTitle => 'Create shop';

  @override
  String get ownerOnboardingHeadline => 'Set up your first shop';

  @override
  String get ownerOnboardingBody =>
      'Enter the business and shop names. You can add workers later.';

  @override
  String get businessNameLabel => 'Business name';

  @override
  String get shopNameLabel => 'Shop name';

  @override
  String get createShopButton => 'CREATE SHOP';

  @override
  String get chooseShopTitle => 'Choose shop';

  @override
  String shopSetupStatus(Object status) {
    return 'Setup: $status';
  }

  @override
  String activeShopLabel(Object shop) {
    return 'Shop: $shop';
  }

  @override
  String get signOut => 'Sign out';

  @override
  String get invalidPhoneMessage =>
      'Enter a valid phone number, for example +252612345678.';

  @override
  String get missingPendingPhoneMessage =>
      'Start with your phone number first.';

  @override
  String get missingShopNamesMessage =>
      'Enter both business name and shop name.';

  @override
  String get sendOtpFailedMessage =>
      'We could not send the code. Check the phone number or internet and try again.';

  @override
  String get verifyOtpFailedMessage =>
      'The code is wrong or expired. Check the code and try again.';

  @override
  String get createShopFailedMessage =>
      'We could not create the shop. Check your internet and try again.';

  @override
  String get shopLoadFailedTitle => 'Could not open shops';

  @override
  String get shopLoadFailedMessage =>
      'Check your internet and try again. If this continues, ask the shop owner to check your access.';

  @override
  String get tryAgain => 'TRY AGAIN';

  @override
  String get setupStepTemplateTitle => 'Choose your shop type';

  @override
  String get setupStepTemplateBody =>
      'Pick a starter pack so common items and settings are ready for you.';

  @override
  String setupStepTemplateDone(Object name) {
    return 'Type chosen: $name';
  }

  @override
  String get setupStepFinishTitle => 'Finish setup';

  @override
  String get setupStepFinishBody => 'Confirm and start using your shop.';

  @override
  String get setupStepFinishButton => 'FINISH SETUP';

  @override
  String get templatePickerTitle => 'Choose your shop type';

  @override
  String get applyTemplateButton => 'USE THIS';

  @override
  String get applyTemplateFailedMessage =>
      'Could not apply the template. Check your internet and try again.';

  @override
  String get templatesEmptyMessage =>
      'No shop types are available yet. Contact support if this keeps happening.';

  @override
  String get completeSetupFailedMessage => 'Could not finish setup. Try again.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get openSettings => 'Settings';

  @override
  String get settingsShopNameLabel => 'Shop name';

  @override
  String get settingsCurrencyLabel => 'Currency';

  @override
  String get settingsLanguageLabel => 'Default language';

  @override
  String get settingsTimezoneLabel => 'Timezone';

  @override
  String get settingsLowStockWarningLabel => 'Low-stock warning';

  @override
  String get settingsLowStockWarningHint =>
      'Show a red dot on low items and a toast after a sale that runs them low.';

  @override
  String get settingsSaveButton => 'SAVE';

  @override
  String get settingsSavedToast => 'Settings saved';

  @override
  String get settingsSaveFailedMessage => 'Could not save settings. Try again.';

  @override
  String get productsTitle => 'Products';

  @override
  String get productsSearchHint => 'Search Somali or English';

  @override
  String get productsInYourShop => 'In your shop';

  @override
  String get productsFromCatalog => 'From catalog';

  @override
  String productsStockLabel(Object quantity, Object unit) {
    return '$quantity $unit in stock';
  }

  @override
  String get productsNoStock => 'No stock yet';

  @override
  String get productsAddToShopButton => 'ADD';

  @override
  String get productsAddingToShop => 'Adding…';

  @override
  String productsAddedToShopToast(Object name) {
    return '$name added to your shop';
  }

  @override
  String productsAddToShopFailedMessage(Object name) {
    return 'Could not add $name. Try again.';
  }

  @override
  String get productsNewItemButton => '+ NEW ITEM';

  @override
  String get productsNewItemUnavailable =>
      'Adding off-catalog items comes later.';

  @override
  String get productsEmptyMessage =>
      'No items yet. Add one from the catalog below.';

  @override
  String productsSearchEmptyMessage(Object query) {
    return 'Nothing matches “$query”.';
  }

  @override
  String get productsLoadFailedMessage =>
      'Could not load products. Check your internet and try again.';

  @override
  String get saleTitle => 'Sale';

  @override
  String get saleSearchHint => 'Search Somali or English';

  @override
  String saleCartSummary(num count, Object total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'No items',
    );
    return '$_temp0 · $total';
  }

  @override
  String get saleEmptyFavoritesMessage =>
      'Add products from the catalog to see them here.';

  @override
  String saleSearchEmptyMessage(Object query) {
    return 'Nothing matches “$query”.';
  }

  @override
  String get saleLoadFailedMessage =>
      'Could not load items. Check your internet and try again.';

  @override
  String get saleCash => 'Cash';

  @override
  String get saleDebt => 'Debt';

  @override
  String get salePickCustomerButton => 'Pick customer';

  @override
  String saleCustomerChip(Object amount, Object name) {
    return '$name · owes $amount';
  }

  @override
  String get saleSaveButton => 'SAVE';

  @override
  String get saleSavedToast => 'Saved';

  @override
  String get salePostFailedMessage =>
      'Could not save the sale. Check your internet and try again.';

  @override
  String get saleNeedItemsMessage => 'Add at least one item before saving.';

  @override
  String get saleNeedCustomerMessage => 'Pick the customer for this debt sale.';

  @override
  String saleAddedItemToast(Object name) {
    return '$name added';
  }

  @override
  String saleAddItemFailedMessage(Object name) {
    return 'Could not add $name. Try again.';
  }

  @override
  String get customerPickerTitle => 'Choose customer';

  @override
  String get customerPickerSearchHint => 'Search name or phone';

  @override
  String customerPickerOwesLabel(Object amount) {
    return 'owes $amount';
  }

  @override
  String get customerPickerNoDebtLabel => 'no debt';

  @override
  String get customerPickerEmptyMessage =>
      'No customers yet. Add one when you record a debt sale.';

  @override
  String customerPickerSearchEmptyMessage(Object query) {
    return 'No customers match “$query”.';
  }

  @override
  String get customerPickerLoadFailedMessage =>
      'Could not load customers. Check your internet and try again.';

  @override
  String get customerNewButton => '+ NEW CUSTOMER';

  @override
  String get partyNewCustomerTitle => 'New customer';

  @override
  String get partyNewSupplierTitle => 'New supplier';

  @override
  String get partyNewNameLabel => 'Name';

  @override
  String get partyNewPhoneLabel => 'Phone (optional)';

  @override
  String get partyNewSaveButton => 'ADD';

  @override
  String get partyNewNameRequiredMessage => 'Enter a name';

  @override
  String get partyNewSaveFailedMessage =>
      'Could not add. Check your internet and try again.';

  @override
  String get paymentTypeCustomer => 'Customer';

  @override
  String get paymentTypeSupplier => 'Supplier';

  @override
  String get paymentTypeCustomerHint => 'Customer is paying you back';

  @override
  String get paymentTypeSupplierHint => 'You are paying the supplier';

  @override
  String get paymentPickCustomerButton => 'Pick customer';

  @override
  String get paymentPickSupplierButton => 'Pick supplier';

  @override
  String paymentCustomerOwesLabel(Object amount) {
    return 'Owes you $amount';
  }

  @override
  String paymentSupplierOwedLabel(Object amount) {
    return 'You owe $amount';
  }

  @override
  String get paymentAmountLabel => 'Amount paid';

  @override
  String get paymentSaveButton => 'SAVE';

  @override
  String get paymentSavedToast => 'Payment saved';

  @override
  String paymentNeedPartyMessage(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'supplier': 'supplier',
      'other': 'customer',
    });
    return 'Pick a $_temp0 first.';
  }

  @override
  String get paymentNeedAmountMessage => 'Enter an amount greater than zero.';

  @override
  String paymentExceedsBalanceMessage(Object amount) {
    return 'Amount cannot exceed the outstanding balance ($amount).';
  }

  @override
  String get paymentPostFailedMessage =>
      'Could not save the payment. Check your internet and try again.';

  @override
  String get expenseCategoryLabel => 'Category';

  @override
  String get expenseAmountLabel => 'Amount';

  @override
  String get expenseSaveButton => 'SAVE';

  @override
  String get expenseSavedToast => 'Expense saved';

  @override
  String get expenseNeedCategoryMessage => 'Pick a category first.';

  @override
  String get expenseNeedAmountMessage => 'Enter an amount greater than zero.';

  @override
  String get expenseLoadFailedMessage =>
      'Could not load categories. Check your internet and try again.';

  @override
  String get expensePostFailedMessage =>
      'Could not save the expense. Check your internet and try again.';

  @override
  String get expenseEmptyMessage =>
      'No expense categories yet. Pick a shop type in Settings.';

  @override
  String get saleHistoryTitle => 'Sales';

  @override
  String get historyYesterday => 'Yesterday';

  @override
  String get saleHistoryTooltip => 'Sales history';

  @override
  String get saleHistoryEmptyMessage =>
      'No sales yet. The first SAVE on the Sale screen will land here.';

  @override
  String get saleHistoryLoadFailedMessage =>
      'Could not load sales. Check your internet and try again.';

  @override
  String get saleHistoryCashLabel => 'Cash';

  @override
  String saleHistoryDebtLabel(Object name) {
    return 'Debt · $name';
  }

  @override
  String get saleHistoryVoidedBadge => 'Voided';

  @override
  String get saleDetailTitle => 'Sale';

  @override
  String get saleDetailVoidedHeader => 'Voided';

  @override
  String get saleDetailVoidButton => 'VOID THIS SALE';

  @override
  String saleDetailLineSubtotal(
    Object quantity,
    Object subtotal,
    Object unit,
    Object unitPrice,
  ) {
    return '$quantity $unit × $unitPrice = $subtotal';
  }

  @override
  String get saleDetailTotalLabel => 'Total';

  @override
  String get saleDetailCashLabel => 'Cash';

  @override
  String get saleDetailDebtLabel => 'Debt';

  @override
  String get saleDetailLoadFailedMessage => 'Could not load this sale.';

  @override
  String get saleReceiptShareButton => 'SHARE RECEIPT';

  @override
  String get saleReceiptDoneButton => 'DONE';

  @override
  String get saleReceiptShareTitle => 'Share receipt';

  @override
  String get saleReceiptSharePrint => 'Print';

  @override
  String get saleReceiptShareWhatsApp => 'WhatsApp';

  @override
  String get saleReceiptShareComingSoon =>
      'Coming soon — receipt will print/share here.';

  @override
  String get saleHistoryReceiptTooltip => 'Open receipt';

  @override
  String get saleVoidConfirmTitle => 'Void this sale?';

  @override
  String get saleVoidConfirmBody =>
      'This will reverse the sale, restore the stock, and clear the customer\'s debt for it.';

  @override
  String get saleVoidConfirmYes => 'VOID';

  @override
  String get saleVoidConfirmNo => 'CANCEL';

  @override
  String get saleVoidRefundCheckboxLabel => 'Refund cash to the customer';

  @override
  String get saleVoidRefundAmountLabel => 'Refund amount';

  @override
  String saleVoidRefundPaidHint(Object amount) {
    return 'paid: $amount';
  }

  @override
  String saleVoidRefundExceedsPaidMessage(Object paid) {
    return 'Refund cannot exceed the cash paid ($paid).';
  }

  @override
  String get saleVoidedToast => 'Sale voided';

  @override
  String get saleVoidFailedMessage =>
      'Could not void this sale. Check your internet and try again.';

  @override
  String get historyMenuSales => 'Sales history';

  @override
  String get historyMenuReceives => 'Receive history';

  @override
  String get historyMenuTooltip => 'History';

  @override
  String get receiveHistoryTitle => 'Receives';

  @override
  String get receiveHistoryTooltip => 'Receive history';

  @override
  String get receiveHistoryEmptyMessage =>
      'No receives yet. The first SAVE on the Receive screen will land here.';

  @override
  String get receiveHistoryLoadFailedMessage =>
      'Could not load receives. Check your internet and try again.';

  @override
  String receiveHistorySupplierLabel(Object name) {
    return 'Supplier · $name';
  }

  @override
  String get receiveHistoryVoidedBadge => 'Voided';

  @override
  String get receiveDetailTitle => 'Receive';

  @override
  String get receiveDetailVoidedHeader => 'Voided';

  @override
  String get receiveDetailVoidButton => 'VOID THIS RECEIVE';

  @override
  String receiveDetailLineSubtotal(
    Object quantity,
    Object subtotal,
    Object unit,
    Object unitCost,
  ) {
    return '$quantity $unit × $unitCost = $subtotal';
  }

  @override
  String get receiveDetailTotalLabel => 'Total';

  @override
  String get receiveDetailLoadFailedMessage => 'Could not load this receive.';

  @override
  String get receiveVoidConfirmTitle => 'Void this receive?';

  @override
  String get receiveVoidConfirmBody =>
      'Use this only when you typed the receive wrong. It reverses the receive, removes the stock, and clears what you owe the supplier for it.';

  @override
  String get receiveVoidMistakesOnlyHint =>
      'Mistakes only. For real returns to the supplier, record a Payment instead.';

  @override
  String get receiveVoidConfirmYes => 'VOID';

  @override
  String get receiveVoidConfirmNo => 'CANCEL';

  @override
  String get receiveVoidedToast => 'Receive voided';

  @override
  String get receiveVoidFailedMessage =>
      'Could not void this receive. Check your internet and try again.';

  @override
  String get receiveVoidBlockedStockMessage =>
      'Some items from this receive have already moved. Void blocked.';

  @override
  String cartLineSubtotal(Object quantity, Object subtotal, Object unitPrice) {
    return '$quantity × $unitPrice = $subtotal';
  }

  @override
  String cartRemoveLineTooltip(Object name) {
    return 'Remove $name';
  }

  @override
  String get cartExpandHint => 'Show items';

  @override
  String get cartCollapseHint => 'Hide items';

  @override
  String get cartClearAllButton => 'Clear all';

  @override
  String cartClearConfirmTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return 'Clear $_temp0 from cart?';
  }

  @override
  String get cartClearConfirmBody => 'This won\'t undo any saved sale.';

  @override
  String get cartClearConfirmYes => 'CLEAR';

  @override
  String get cartClearConfirmNo => 'CANCEL';

  @override
  String get lineEditorDoneButton => 'DONE';

  @override
  String get lineEditorPriceRequiredHelper => 'Set a price for this item';

  @override
  String get lineEditorInvalidPriceMessage => 'Enter a number 0 or more';

  @override
  String get lineEditorTilePriceMissing => '—';

  @override
  String get supplierPickerTitle => 'Pick supplier';

  @override
  String get supplierPickerSearchHint => 'Search name or phone';

  @override
  String supplierPickerOwesLabel(Object amount) {
    return 'you owe $amount';
  }

  @override
  String get supplierPickerNoBonosLabel => 'no receives yet';

  @override
  String get supplierPickerEmptyMessage =>
      'No suppliers yet. Add one when you record a receive.';

  @override
  String supplierPickerSearchEmptyMessage(Object query) {
    return 'No suppliers match “$query”.';
  }

  @override
  String get supplierPickerLoadFailedMessage =>
      'Could not load suppliers. Check your internet and try again.';

  @override
  String get supplierNewButton => '+ NEW SUPPLIER';

  @override
  String get receiveSearchHint => 'Search Somali or English';

  @override
  String get receiveLoadFailedMessage =>
      'Could not load items. Check your internet and try again.';

  @override
  String get receiveEmptyMessage =>
      'Tap an item to start the receive. Search if it\'s not in the grid.';

  @override
  String get receiveLineQuantityLabel => 'Qty';

  @override
  String receiveLinePerUnitLabel(Object currency, Object unit) {
    return '$currency per $unit';
  }

  @override
  String receiveLineTotalLabel(Object currency) {
    return '$currency total';
  }

  @override
  String receiveLineDerivedPerUnit(String money, String packaging) {
    return '= $money per $packaging';
  }

  @override
  String get receiveAddLineButton => 'ADD LINE';

  @override
  String receiveLineSubtotal(Object quantity, Object total, Object unit) {
    return '$quantity $unit = $total';
  }

  @override
  String receiveLineRemoveTooltip(Object name) {
    return 'Remove $name';
  }

  @override
  String receiveLinesSummary(num count, Object total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines',
      one: '1 line',
      zero: 'No lines',
    );
    return '$_temp0 · $total';
  }

  @override
  String get receiveLinesClearAllButton => 'Clear all';

  @override
  String receiveLinesClearConfirmTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines',
      one: '1 line',
    );
    return 'Clear $_temp0?';
  }

  @override
  String get receiveLinesClearConfirmBody =>
      'This won\'t undo any saved receive.';

  @override
  String get receiveLinesClearConfirmYes => 'CLEAR';

  @override
  String get receiveLinesClearConfirmNo => 'CANCEL';

  @override
  String get receiveSaveButton => 'SAVE';

  @override
  String get receiveSavedToast => 'Receive saved (on credit)';

  @override
  String get receivePostFailedMessage =>
      'Could not save the receive. Check your internet and try again.';

  @override
  String get receiveNeedSupplierMessage => 'Pick a supplier before saving.';

  @override
  String get receiveNeedLinesMessage => 'Add at least one line before saving.';

  @override
  String get receiveInvalidNumberMessage => 'Enter a positive number';

  @override
  String get unitPickerTitle => 'Choose unit';

  @override
  String get unitPickerDefaultBadge => 'default';

  @override
  String get unitPickerBaseUnit => 'base unit';

  @override
  String unitPickerConversion(Object base, Object multiplier, Object unit) {
    return '$multiplier $base per $unit';
  }

  @override
  String get unitPickerLoadFailedMessage => 'Could not load units. Try again.';

  @override
  String get unitPickerAddPackagingButton => '+ Add packaging';

  @override
  String addNewItemSearchResult(Object query) {
    return '+ Add new item: “$query”';
  }

  @override
  String get addNewItemSheetTitle => 'Add new item';

  @override
  String get addNewItemNameLabel => 'Name';

  @override
  String get addNewItemUnitLabel => 'Unit';

  @override
  String get addNewItemUnitChooseHint => 'Choose';

  @override
  String addNewItemPriceLabel(Object unit) {
    return 'Sale price per $unit';
  }

  @override
  String get addNewItemCategoryLabel => 'Category (optional)';

  @override
  String get addNewItemCategoryChooseHint => 'Choose';

  @override
  String get addNewItemCancelButton => 'CANCEL';

  @override
  String get addNewItemAddToSaleButton => 'ADD TO SALE';

  @override
  String get addNewItemAddToReceiveButton => 'ADD TO RECEIVE';

  @override
  String get addNewItemMissingNameMessage => 'Name is required';

  @override
  String get addNewItemMissingUnitMessage => 'Pick a unit';

  @override
  String get addNewItemInvalidPriceMessage => 'Enter a price (0 or more)';

  @override
  String get addNewItemFailedMessage => 'Could not create the item. Try again.';

  @override
  String get addNewItemHowSoldHeader => 'How is it sold?';

  @override
  String get addNewItemHowDeliveredHeader => 'How did the supplier deliver?';

  @override
  String addNewItemBaseOnlyTile(String base) {
    return 'By $base';
  }

  @override
  String addNewItemPickedPriceLabel(String packaging) {
    return 'Sale price per $packaging';
  }

  @override
  String get addNewItemCustomPackagingEntry => '+ Custom packaging';

  @override
  String get addNewItemCustomBaseUnitLabel => 'Base unit';

  @override
  String get addNewItemCustomSoldUnitLabel => 'Sold as';

  @override
  String addNewItemCustomConversionLabel(String base, String sold) {
    return 'How many $base in 1 $sold?';
  }

  @override
  String get addNewItemMissingPackagingMessage => 'Pick how it is sold';

  @override
  String get addNewItemLoadOptionsFailedHint =>
      'Could not load suggestions. Pick custom packaging.';

  @override
  String get addNewItemUseCustomButton => 'USE THIS PACKAGING';

  @override
  String get addNewItemLooseType => 'Loose';

  @override
  String get addNewItemBackToTypes => '← Back';

  @override
  String get addPackagingSheetTitle => 'Add packaging';

  @override
  String get addPackagingUnitLabel => 'Unit';

  @override
  String addPackagingConversionLabel(Object base, Object unit) {
    return 'How many $base in 1 $unit?';
  }

  @override
  String addPackagingPriceLabel(Object unit) {
    return 'Sale price per $unit (optional)';
  }

  @override
  String get addPackagingSaveButton => 'ADD PACKAGING';

  @override
  String get addPackagingFailedMessage =>
      'Could not add the packaging. Try again.';

  @override
  String addPackagingHeaderBaseUnit(Object unit) {
    return 'Base unit · $unit';
  }

  @override
  String get addPackagingSuggestionsHeader => 'Common packagings';

  @override
  String get addPackagingCustomEntry => '+ Custom packaging';

  @override
  String get addPackagingLessCommonHeader => 'Less common';

  @override
  String packagingConversionPreview(String unit, String qty, String base) {
    return '1 $unit holds $qty $base';
  }

  @override
  String get addPackagingBackToSuggestions => '← Back to suggestions';

  @override
  String addPackagingPickedPriceLabel(Object packaging) {
    return 'Sale price per $packaging (optional)';
  }

  @override
  String get addPackagingNoSuggestionsHint =>
      'No common packagings yet for this base unit — define your own below.';

  @override
  String get addPackagingLoadFailedHint =>
      'Could not load suggestions. Define your own below.';

  @override
  String lineEditorCostHintLabel(String cost) {
    return 'Your last cost: $cost. Add your usual markup.';
  }

  @override
  String lineEditorSiblingHintLabel(String packaging, String price) {
    return '$packaging sells at $price. Use that as a guide.';
  }

  @override
  String negativeStockToast(Object amount, Object item, Object unit) {
    return '$item stock is now $amount $unit. Receive soon.';
  }

  @override
  String negativeStockMoreItems(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more items',
      one: '1 more item',
    );
    return '+ $_temp0 low';
  }

  @override
  String lowStockToast(String amount, String item, String unit) {
    return '$item stock is low — only $amount $unit left. Receive soon.';
  }

  @override
  String lowStockMoreItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more items',
      one: '1 more item',
    );
    return '+ $_temp0 low';
  }

  @override
  String get shopItemEditorTitleCreate => 'Add product';

  @override
  String get shopItemEditorTitleEdit => 'Edit product';

  @override
  String get productEditorLoadFailedMessage =>
      'Could not load this product. Try again.';

  @override
  String get shopItemDetailAliasesHeader => 'Other names';

  @override
  String get shopItemDetailBarcodesHeader => 'Barcodes';

  @override
  String get shopItemEditorNameLabel => 'Name';

  @override
  String get shopItemEditorBaseUnitLabel => 'Base unit';

  @override
  String get shopItemEditorCategoryLabel => 'Category';

  @override
  String get shopItemEditorReorderThresholdLabel =>
      'Warn when stock drops below';

  @override
  String shopItemEditorReorderThresholdHelper(String unit) {
    return 'In $unit. Leave blank for no warning.';
  }

  @override
  String get shopItemEditorPackagingsHeader => 'Packagings';

  @override
  String get shopItemEditorAddPackagingButton => 'Add packaging';

  @override
  String get shopItemEditorBaseBadge => 'BASE';

  @override
  String get removePackagingTooltip => 'Remove packaging';

  @override
  String get shopItemEditorItemSectionHeader => 'Item';

  @override
  String get shopItemEditorEditHint =>
      'Edit prices and defaults from the product detail screen.';

  @override
  String get removePackagingConfirmBody =>
      'Remove this packaging? You can add it back later.';

  @override
  String get removePackagingConfirmAction => 'REMOVE';

  @override
  String get shopItemEditorSaveButton => 'SAVE';

  @override
  String get shopItemEditorSaveAndAddAnotherButton => 'SAVE & ADD ANOTHER';

  @override
  String shopItemEditorSavedAndContinueToast(String name) {
    return '$name saved — add another';
  }

  @override
  String get shopItemDetailEditPrice => 'Edit price';

  @override
  String get shopItemDetailDefaultSaleBadge => 'default sale';

  @override
  String get shopItemDetailDefaultReceiveBadge => 'default receive';

  @override
  String get shopItemDetailNoPriceLabel => 'no price yet';

  @override
  String shopItemDetailCurrentStockLabel(Object amount, Object unit) {
    return '$amount $unit in stock';
  }

  @override
  String shopItemDetailReorderBelowLabel(Object amount, Object unit) {
    return 'Reorder below $amount $unit';
  }

  @override
  String get catalogPickerTitle => 'Browse catalog';

  @override
  String get catalogPickerSearchHint => 'Search global catalog';

  @override
  String get catalogPickerActivatedBadge => 'already added';

  @override
  String catalogPickerAddButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return 'ADD $_temp0';
  }

  @override
  String catalogPickerAddedToast(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0 added';
  }

  @override
  String get setupOnboardingTitle => 'Set up your products';

  @override
  String setupOnboardingBody(Object count, Object template) {
    return 'We added $count items from the $template template. You can start selling now — prices fill in as you sell.\n\nOr take a minute to:';
  }

  @override
  String get setupOnboardingAddItemsTitle => 'Add my own items';

  @override
  String get setupOnboardingAddItemsBody =>
      'Items the template didn\'t include';

  @override
  String get setupOnboardingSetPricesTitle => 'Set prices on top items';

  @override
  String get setupOnboardingSetPricesBody =>
      'So sales don\'t pause for a price prompt';

  @override
  String get setupOnboardingBrowseCatalogTitle => 'Browse the catalog';

  @override
  String get setupOnboardingBrowseCatalogBody =>
      'Activate more items from our list';

  @override
  String get setupOnboardingSkipButton => 'SKIP — START SELLING';

  @override
  String get scanCameraTooltip => 'Scan barcode';

  @override
  String get scannerSheetTitle => 'Scan a barcode';

  @override
  String get scannerTorchTooltip => 'Torch';

  @override
  String get scannerHoldSteady => 'Hold steady — 15 to 25 cm from the code';

  @override
  String scanUnknownPillLabel(String code) {
    return 'Unknown barcode: $code';
  }

  @override
  String get scanUnknownCreateAction => 'Create new';

  @override
  String get scanUnknownDismissAction => 'Dismiss';

  @override
  String get scanLookupFailed => 'Couldn\'t look up that barcode';

  @override
  String multiScanSheetTitle(int count) {
    return 'Multi-scan ($count)';
  }

  @override
  String multiScanUnknownCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unknown codes — review after',
      one: '1 unknown code — review after',
    );
    return '$_temp0';
  }

  @override
  String get multiScanEmptyHint =>
      'Aim at a barcode. Successful scans stage as lines below.';

  @override
  String get multiScanDoneAction => 'DONE';

  @override
  String get multiScanLongPressHint => 'Hold to multi-scan';

  @override
  String multiScanAppliedSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines staged',
      one: '1 line staged',
    );
    return '$_temp0';
  }

  @override
  String get barcodeScanAndBindAction => 'Scan code';

  @override
  String get barcodeBoundToPackagingMessage => 'Code linked to this packaging';
}

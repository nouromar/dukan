// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'DukanPro';

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
  String get paymentInLabel => 'Money In';

  @override
  String get paymentOutLabel => 'Money Out';

  @override
  String get paymentDetailSettledHeader => 'Paid for';

  @override
  String get paymentFromSaleHeader => 'From a cash sale';

  @override
  String get paymentFromReceiveHeader => 'From a stock receive';

  @override
  String paymentEffectIn(String name, String amount) {
    return 'Lowered $name\'s debt by $amount.';
  }

  @override
  String paymentEffectOut(String name, String amount) {
    return 'Reduced what you owe $name by $amount.';
  }

  @override
  String get paymentDetailLoadFailedMessage => 'Couldn\'t load this payment.';

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
  String get total => 'Total';

  @override
  String get undo => 'Undo';

  @override
  String get quantity => 'Qty';

  @override
  String get price => 'Price';

  @override
  String get cancel => 'Cancel';

  @override
  String get receiveTitle => 'Receive';

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
  String get partyHideTooltip => 'Hide';

  @override
  String get partyHideConfirmTitle => 'Hide this contact?';

  @override
  String get partyHideConfirmBody =>
      'They\'ll be removed from your lists. Any balance and history stay. You can ask support to bring them back.';

  @override
  String get partyHideConfirmYes => 'HIDE';

  @override
  String get partyHiddenToast => 'Contact hidden';

  @override
  String get backdateChipToday => 'Today';

  @override
  String get backdateChipTooltip => 'Change date';

  @override
  String backdateBannerLabel(String date) {
    return 'Recording for $date';
  }

  @override
  String get backdateBackToToday => 'TODAY';

  @override
  String get reportsTitle => 'Reports';

  @override
  String get drawerReports => 'Reports';

  @override
  String get reportsSalesTitle => 'Sales';

  @override
  String get reportsProfitTitle => 'Profit';

  @override
  String get reportsStockTitle => 'Stock';

  @override
  String get reportsRevenueLabel => 'Sales total';

  @override
  String get reportsSalesCountLabel => 'Number of sales';

  @override
  String get reportsAvgSaleLabel => 'Average sale';

  @override
  String get reportsCostLabel => 'Cost of goods';

  @override
  String get reportsGrossProfitLabel => 'Gross profit';

  @override
  String get reportsExpensesLabel => 'Expenses';

  @override
  String get reportsNetProfitLabel => 'Net profit';

  @override
  String get reportsMarginLabel => 'Margin';

  @override
  String get reportsItemsLabel => 'Products in stock';

  @override
  String get reportsStockValueLabel => 'Stock value';

  @override
  String get reportsLowStockLabel => 'Low stock';

  @override
  String get reportsLoadFailedMessage =>
      'Could not load reports. Check your internet and try again.';

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
  String get dateRangeAll => 'All';

  @override
  String get dateRangeCustom => 'Custom…';

  @override
  String get filterPartyAny => 'Anyone';

  @override
  String get filterHideVoided => 'Hide voided';

  @override
  String get filterCategoryAny => 'All categories';

  @override
  String get filterLowStockOnly => 'Low stock only';

  @override
  String get filterNoPriceOnly => 'No price yet';

  @override
  String get lowStockSearchHint => 'Search product';

  @override
  String filterChipParty(String name) {
    return 'Party: $name';
  }

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
  String get partiesLoadFailedMessage =>
      'Could not load. Pull down to try again.';

  @override
  String get partiesEmptyMessage => 'No customers or suppliers yet.';

  @override
  String partiesEmptyForQuery(String query) {
    return 'No matches for \"$query\".';
  }

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
  String stockAdjustUnitCostLabel(String unit, String currency) {
    return 'Cost per $unit ($currency)';
  }

  @override
  String get stockAdjustUnitCostRequiredMessage =>
      'Enter the cost per unit so average cost stays correct.';

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
  String get aliasAddDialogTitle => 'Add another name';

  @override
  String get aliasAddDialogHint => 'e.g. Riis (Somali)';

  @override
  String get aliasAddDialogLanguage => 'Language';

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
  String get drawerLowStock => 'Low stock';

  @override
  String get drawerSetupHeader => 'SETUP';

  @override
  String get drawerProducts => 'Products';

  @override
  String get drawerSettings => 'Settings';

  @override
  String receiveFrom(Object supplier) {
    return 'Receive from $supplier';
  }

  @override
  String get item => 'Item';

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
  String get bonoTotal => 'Bono total';

  @override
  String get credit => 'Credit';

  @override
  String get clear => 'CLEAR';

  @override
  String get paymentTitle => 'Payment';

  @override
  String get amount => 'Amount';

  @override
  String get expenseTitle => 'Expense';

  @override
  String get category => 'Category';

  @override
  String get rent => 'Rent';

  @override
  String get salary => 'Salary';

  @override
  String get other => 'Other';

  @override
  String get supabaseConfigTitle => 'Connect DukanPro to Supabase';

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
  String get loginTabPhone => 'Phone';

  @override
  String get loginTabEmail => 'Email';

  @override
  String get loginHeadline => 'Use your phone number';

  @override
  String get loginBody =>
      'We will send a one-time code. DukanPro can deliver it by WhatsApp from the backend.';

  @override
  String get loginEmailHeadline => 'Use your email';

  @override
  String get loginEmailBody => 'We will email you a one-time code.';

  @override
  String get phoneNumberLabel => 'Phone number';

  @override
  String get emailAddressLabel => 'Email';

  @override
  String get sendOtpButton => 'SEND CODE';

  @override
  String get sendEmailOtpButton => 'SEND CODE';

  @override
  String get verifyOtpTitle => 'Enter code';

  @override
  String get verifyOtpHeadline => 'Check your phone';

  @override
  String get verifyOtpHeadlineEmail => 'Check your email';

  @override
  String verifyOtpBody(String phone) {
    return 'Enter the code sent to $phone.';
  }

  @override
  String verifyOtpBodyEmail(String email) {
    return 'Enter the code sent to $email.';
  }

  @override
  String get otpCodeLabel => 'Code';

  @override
  String get verifyOtpButton => 'VERIFY';

  @override
  String get changePhoneButton => 'Change phone number';

  @override
  String get changeEmailButton => 'Change email';

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
  String get queueCapExceededToast =>
      'Some old unsynced data was dropped — your phone was offline too long.';

  @override
  String get signOutPendingDialogTitle => 'Unsynced data';

  @override
  String signOutPendingDialogBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You have $count posts that have not synced yet.',
      one: 'You have 1 post that has not synced yet.',
    );
    return '$_temp0 Sign out anyway? They will sync the next time you sign in.';
  }

  @override
  String get signOutPendingDialogCancel => 'Cancel';

  @override
  String get signOutPendingDialogConfirm => 'Sign out';

  @override
  String get invalidPhoneMessage =>
      'Enter a valid phone number, for example +252612345678.';

  @override
  String get invalidEmailMessage =>
      'Enter a valid email, for example you@example.com.';

  @override
  String get missingPendingPhoneMessage =>
      'Start with your phone number first.';

  @override
  String get missingPendingDestinationMessage =>
      'Start with your phone or email first.';

  @override
  String get missingShopNamesMessage =>
      'Enter both business name and shop name.';

  @override
  String get sendOtpFailedMessage =>
      'We could not send the code. Check the phone number or internet and try again.';

  @override
  String get sendEmailOtpFailedMessage =>
      'We could not email the code. Check the address or your internet and try again.';

  @override
  String get emailAccountNotFoundMessage =>
      'No account found for that email. Ask your shop owner to add you.';

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
  String get setupStepFinishBody => 'Confirm and start using your shop.';

  @override
  String get setupStepFinishButton => 'FINISH SETUP';

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
  String get settingsShopNameLabel => 'Shop name';

  @override
  String get settingsCurrencyLabel => 'Currency';

  @override
  String get settingsLanguageLabel => 'Default language';

  @override
  String get settingsTimezoneLabel => 'Timezone';

  @override
  String get settingsSaveButton => 'SAVE';

  @override
  String get settingsSavedToast => 'Settings saved';

  @override
  String get settingsSaveFailedMessage => 'Could not save settings. Try again.';

  @override
  String get settingsCurrencyLockedMessage =>
      'Currency can\'t be changed once the shop has recorded a transaction. Contact support to change it.';

  @override
  String get productsTitle => 'Products';

  @override
  String get productsSearchHint => 'Search Somali or English';

  @override
  String get productsNewItemButton => 'NEW ITEM';

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
  String get salePostFailedMessage =>
      'Could not save the sale. Check your internet and try again.';

  @override
  String get saleNeedItemsMessage => 'Add at least one item before saving.';

  @override
  String get saleNeedCustomerMessage => 'Pick the customer for this debt sale.';

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
  String get partyNewPhoneLabel => 'Phone';

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
  String get paymentNotesLabel => 'Note';

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
  String get paymentChooseInvoicesChip => 'Choose invoices';

  @override
  String paymentChooseInvoicesChipDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count invoices chosen',
      one: '1 invoice chosen',
    );
    return '$_temp0';
  }

  @override
  String allocationHeader(String party) {
    return '$party · choose invoices';
  }

  @override
  String allocationToAllocate(String amount) {
    return '$amount to allocate';
  }

  @override
  String allocationRowOpen(String open, String original) {
    return 'Open $open of $original';
  }

  @override
  String allocationStillToAllocate(String amount) {
    return 'Still to allocate: $amount';
  }

  @override
  String allocationOverAllocated(String amount) {
    return 'Over by $amount';
  }

  @override
  String get allocationBalanced => 'Balanced';

  @override
  String get allocationApplyButton => 'APPLY';

  @override
  String get allocationNeedAtLeastOne =>
      'Choose at least one invoice to apply.';

  @override
  String get allocationLoadFailed => 'Could not load open invoices.';

  @override
  String get allocationNoOpenInvoices => 'No open invoices for this person.';

  @override
  String get partyDetailOpenInvoicesHeader => 'Open invoices';

  @override
  String partyDetailOpenInvoiceRow(String open, String original) {
    return '$open open of $original';
  }

  @override
  String get expenseCategoryLabel => 'Category';

  @override
  String get expenseAmountLabel => 'Amount';

  @override
  String get expenseSaveButton => 'SAVE';

  @override
  String get expenseNotesLabel => 'Note';

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
  String get historyToday => 'Today';

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
  String get expenseDetailTitle => 'Expense';

  @override
  String get expenseDetailVoidButton => 'VOID THIS EXPENSE';

  @override
  String get expenseDetailLoadFailedMessage => 'Couldn\'t load this expense.';

  @override
  String get expenseVoidConfirmTitle => 'Void this expense?';

  @override
  String get expenseVoidConfirmBody =>
      'This reverses the expense. It can\'t be undone.';

  @override
  String get expenseVoidConfirmYes => 'VOID';

  @override
  String get expenseVoidedToast => 'Expense voided';

  @override
  String get expenseVoidFailedMessage => 'Couldn\'t void this expense.';

  @override
  String get paymentDetailVoidButton => 'VOID THIS PAYMENT';

  @override
  String get paymentVoidConfirmTitle => 'Void this payment?';

  @override
  String get paymentVoidConfirmBody =>
      'This reverses the payment and reopens what it settled. It can\'t be undone.';

  @override
  String get paymentVoidConfirmYes => 'VOID';

  @override
  String get paymentVoidedToast => 'Payment voided';

  @override
  String get paymentVoidedHeader => 'Voided';

  @override
  String get paymentVoidFailedMessage => 'Couldn\'t void this payment.';

  @override
  String get paymentVoidWindowPassedHint => 'Void window passed';

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
  String get receiptNumberLabel => 'Receipt';

  @override
  String get receiptDateLabel => 'Date';

  @override
  String get receiptThankYou => 'Thank you!';

  @override
  String get saleDetailLoadFailedMessage => 'Could not load this sale.';

  @override
  String get saleReceiptShareButton => 'SHARE RECEIPT';

  @override
  String get saleReceiptDoneButton => 'DONE';

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
  String get saleVoidFailedMessage => 'Could not void this sale. Try again.';

  @override
  String get saleVoidErrorOwnerOnly => 'Only the shop owner can void a sale.';

  @override
  String get saleVoidErrorWindowExpired =>
      'Too late to void — sales can only be voided within 7 days of posting.';

  @override
  String get saleVoidErrorAlreadyVoided => 'This sale was already voided.';

  @override
  String get saleVoidErrorRefundNeedsCustomer =>
      'Walk-in sales can\'t be refunded — there\'s no customer to refund to.';

  @override
  String get saleVoidErrorRefundExceedsPaid =>
      'Refund can\'t be more than the cash paid at the till.';

  @override
  String get saleVoidErrorNotFound =>
      'Sale not found. Pull to refresh and try again.';

  @override
  String get saleVoidErrorPartiallyPaid =>
      'The customer has already paid part of this debt, so the sale can\'t be voided. Record a refund instead.';

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
  String get receiveVoidBlockedPaidMessage =>
      'You\'ve already paid part of this bono, so it can\'t be voided. Record a refund instead.';

  @override
  String cartLineSubtotal(Object quantity, Object subtotal, Object unitPrice) {
    return '$quantity × $unitPrice = $subtotal';
  }

  @override
  String cartRemoveLineTooltip(Object name) {
    return 'Remove $name';
  }

  @override
  String get cartClearAllButton => 'Clear';

  @override
  String get drawerExpandTooltip => 'Show all lines';

  @override
  String get drawerShrinkTooltip => 'Shrink';

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
  String get receiveLinesClearAllButton => 'Clear';

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
  String get saleSavedToast => 'Sale saved';

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
  String get unitPickerTitle => 'Choose unit';

  @override
  String get unitPickerDefaultBadge => 'default';

  @override
  String get unitPickerBaseUnit => 'base unit';

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
  String get addNewItemUnitChooseHint => 'Choose';

  @override
  String get addNewItemCategoryLabel => 'Category (optional)';

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
  String get addPackagingCustomEntry => 'Custom packaging';

  @override
  String get addPackagingLessCommonHeader => 'Less common';

  @override
  String packagingConversionPreview(String unit, String qty, String base) {
    return '1 $unit holds $qty $base';
  }

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
  String get shopItemEditorTitleCreate => 'Add product';

  @override
  String get shopItemDetailAliasesHeader => 'Other names';

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
  String get shopItemEditorScanIdentifyButton => 'Scan';

  @override
  String shopItemEditorBarcodeNoMatchToast(String code) {
    return 'Code $code isn\'t in our catalog yet. Fill in the rest and SAVE.';
  }

  @override
  String shopItemEditorPrefillBanner(String name) {
    return 'Found \'$name\' in the catalog — review and tweak anything that\'s different.';
  }

  @override
  String get shopItemEditorSuggestionInShop =>
      'Already in your shop — tap to open';

  @override
  String get shopItemEditorSuggestionInCatalog =>
      'From global catalog — tap to use';

  @override
  String shopItemEditorSessionCounter(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# added',
      one: '1 added',
    );
    return '$_temp0';
  }

  @override
  String get shopItemEditorSessionSheetTitle => 'Added this session';

  @override
  String get shopItemEditorSessionSheetViewAll => 'View all products →';

  @override
  String get shopItemEditorIdentifyHeader => 'Identify';

  @override
  String get shopItemEditorPackagingHeader => 'Packaging';

  @override
  String get shopItemEditorSupplierHeader => 'Supplier';

  @override
  String get shopItemEditorPickSupplierButton => 'Pick supplier';

  @override
  String get shopItemEditorNewSupplierButton => 'NEW';

  @override
  String get shopItemEditorRemoveSupplierTooltip => 'Remove supplier';

  @override
  String get packagingEditorAddTitle => 'Add packaging';

  @override
  String get packagingEditorEditTitle => 'Edit packaging';

  @override
  String get packagingEditorSaveButton => 'SAVE';

  @override
  String get packagingEditorMissingUnitMessage =>
      'Pick a packaging unit (e.g. bag, box).';

  @override
  String get packagingEditorMissingConversionMessage =>
      'How many base units fit in this pack? Enter a number greater than 0.';

  @override
  String packagingEditorCostLabel(String unit) {
    return 'Cost per $unit';
  }

  @override
  String packagingEditorStockLabel(String unit) {
    return 'Stock — how many $unit?';
  }

  @override
  String shopItemEditorBaseStockLabel(String unit) {
    return 'Stock — loose $unit';
  }

  @override
  String shopItemEditorBaseSaleLabel(String unit) {
    return 'Sale price per $unit';
  }

  @override
  String shopItemEditorBaseCostLabel(String unit) {
    return 'Cost per $unit';
  }

  @override
  String shopItemEditorPackagingSummary(
    String sale,
    String cost,
    String stock,
  ) {
    return 'Sell $sale · Cost $cost · $stock in stock';
  }

  @override
  String get shopItemEditorPackagingSummaryEmpty => '—';

  @override
  String get shopItemEditorEditPackagingTooltip => 'Edit packaging';

  @override
  String get shopItemEditorRemovePackagingTooltip => 'Remove packaging';

  @override
  String get shopItemEditorBuyHeader => 'Suppliers';

  @override
  String get shopItemEditorBuySubtitle =>
      'Default supplier + typical cost — pre-fills Receive later.';

  @override
  String get shopItemEditorTypicalCostHeader => 'Typical cost';

  @override
  String shopItemEditorCostPerPackLabel(String pack) {
    return 'Cost per $pack';
  }

  @override
  String get shopItemEditorOpeningHeader => 'Stock';

  @override
  String get shopItemEditorOpeningSubtitle =>
      'Enter current stock per packaging so reports are right from day one.';

  @override
  String get shopItemEditorOpeningPickBaseUnitFirst =>
      'Pick a base unit above to enable this section.';

  @override
  String shopItemEditorOpeningQtyLabel(String unit) {
    return 'Quantity in $unit';
  }

  @override
  String shopItemEditorOpeningAsOf(String date) {
    return 'As of $date';
  }

  @override
  String get shopItemEditorChangeDateButton => 'Change';

  @override
  String get shopItemEditorOpeningStockNote =>
      'Opening stock recorded during onboarding.';

  @override
  String get shopItemEditorOpeningStockFailedMessage =>
      'Item saved but stock did not save — open the product to adjust.';

  @override
  String get shopItemEditorDedupTitle => 'You may already have this';

  @override
  String get shopItemEditorDedupBody =>
      'Your shop has similar items. Open one to edit, or keep going if it\'s something different:';

  @override
  String get shopItemEditorDedupKeepGoing => 'IT\'S DIFFERENT';

  @override
  String get shopItemEditorDedupOpenExisting => 'OPEN EXISTING';

  @override
  String get shopItemEditorPackagingsHeader => 'Packagings';

  @override
  String get shopItemEditorAddPackagingButton => 'Add packaging';

  @override
  String get shopItemEditorBaseBadge => 'BASE';

  @override
  String get shopItemEditorPackagingMissingMessage =>
      'Fill at least one packaging (price, cost, stock, or barcode).';

  @override
  String get shopItemEditorScanBarcodeButton => 'Scan barcode (optional)';

  @override
  String get shopItemEditorRescanBarcodeButton => 'Scan again';

  @override
  String get shopItemEditorRemoveBarcodeTooltip => 'Remove barcode';

  @override
  String shopItemEditorBarcodeBoundLabel(String code) {
    return 'Barcode $code';
  }

  @override
  String shopItemEditorBarcodeCapturedToast(String code) {
    return 'Captured $code';
  }

  @override
  String get shopItemEditorDiscoveryHeader => 'Aliases';

  @override
  String get shopItemEditorDiscoverySubtitle =>
      'Extra names + bono spelling improve search later.';

  @override
  String get shopItemEditorAliasesLabel => 'Other names';

  @override
  String get shopItemEditorAliasHint => 'Add another name';

  @override
  String get shopItemEditorAddAliasButton => 'ADD';

  @override
  String get shopItemEditorAliasHelper =>
      'Names a customer might say. Tap a chip to remove it.';

  @override
  String get shopItemEditorBonoSpellingLabel => 'Bono spelling (optional)';

  @override
  String get shopItemEditorBonoSpellingHelper =>
      'How this item appears on supplier paper invoices (e.g. CCL 330x24).';

  @override
  String get removePackagingTooltip => 'Remove packaging';

  @override
  String get deactivateItemTooltip => 'Hide product';

  @override
  String get deactivateItemConfirmTitle => 'Hide this product?';

  @override
  String get deactivateItemConfirmBody =>
      'It will be removed from Sale, Receive, and Products. Past sales keep it. You can ask support to bring it back.';

  @override
  String get deactivateItemConfirmAction => 'HIDE';

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
  String get shopItemDetailDefaultSaleBadge => 'Sale';

  @override
  String get shopItemDetailDefaultReceiveBadge => 'Receive';

  @override
  String get shopItemDetailDefaultForLabel => 'Default for:';

  @override
  String get shopItemDetailStockLabel => 'Stock';

  @override
  String get shopItemDetailNoPriceLabel => 'no price yet';

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

  @override
  String get relativeTimeJustNow => 'just now';

  @override
  String relativeTimeMinutesAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes min ago',
      one: '1 min ago',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeHoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hr ago',
      one: '1 hr ago',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeOn(String date) {
    return 'on $date';
  }

  @override
  String saleHistoryVoidedSubtitle(String when) {
    return 'voided $when';
  }

  @override
  String partyDetailEditedAt(String when) {
    return 'contact info edited $when';
  }

  @override
  String offlineQueuePillLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Syncing $count',
      one: 'Syncing 1',
    );
    return '$_temp0';
  }

  @override
  String get storageSyncTitle => 'Storage & sync';

  @override
  String get storageSyncStatusConnected => 'Connected';

  @override
  String get storageSyncStatusOffline => 'Offline';

  @override
  String get storageSyncLastSyncedLabel => 'Last synced';

  @override
  String get storageSyncLastSyncedNever => 'Never';

  @override
  String get storageSyncPendingSalesLabel => 'Pending posts';

  @override
  String storageSyncPendingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count waiting',
      one: '1 waiting',
      zero: 'none waiting',
    );
    return '$_temp0';
  }

  @override
  String get storageSyncFailedPermanentlyLabel => 'Failed permanently';

  @override
  String storageSyncFailedPermanentlyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count posts',
      one: '1 post',
    );
    return '$_temp0';
  }

  @override
  String get storageSyncStorageUsedLabel => 'Storage used';

  @override
  String get storageSyncStorageBreakdownPending => 'Pending posts';

  @override
  String get storageSyncStorageBreakdownCached => 'Cached data';

  @override
  String get storageSyncSyncNowButton => 'Sync now';

  @override
  String get storageSyncFreeUpSpaceButton => 'Free up space';

  @override
  String get storageSyncFreeUpSpaceConfirmTitle => 'Clear cached data?';

  @override
  String get storageSyncFreeUpSpaceConfirmBody =>
      'This refreshes prices and lists from the server. Your saved sales aren\'t touched.';

  @override
  String get storageSyncFreeUpSpaceConfirmAction => 'CLEAR';

  @override
  String get storageSyncResyncAllButton => 'Re-download all data';

  @override
  String get storageSyncResyncConfirmTitle => 'Re-download all data?';

  @override
  String get storageSyncResyncConfirmBody =>
      'Fetches a fresh copy of items, customers, and recent transactions from the server. Your saved sales aren\'t touched.';

  @override
  String get storageSyncResyncConfirmAction => 'RE-DOWNLOAD';

  @override
  String get storageSyncResyncDoneToast => 'Re-downloaded all data';

  @override
  String get storageSyncResyncFailedToast => 'Couldn\'t re-download';

  @override
  String get storageSyncCacheClearedToast => 'Cache cleared';

  @override
  String storageSyncSyncedToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Synced $count posts',
      one: 'Synced 1 post',
      zero: 'Already up to date',
    );
    return '$_temp0';
  }

  @override
  String get storageSyncSyncFailedToast =>
      'Could not sync — check your connection.';

  @override
  String get storageSyncAlreadyUpToDateToast => 'Already up to date';

  @override
  String storageSyncPushedToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sent $count pending',
      one: 'Sent 1 pending',
    );
    return '$_temp0';
  }

  @override
  String storageSyncPulledToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Got $count updates',
      one: 'Got 1 update',
    );
    return '$_temp0';
  }

  @override
  String storageSyncPushedAndPulledToast(int pushed, int pulled) {
    return 'Sent $pushed pending, got $pulled updates';
  }

  @override
  String get storageSyncResetButton => 'Reset local data';

  @override
  String get storageSyncResetConfirmTitle => 'Reset local data?';

  @override
  String get storageSyncResetConfirmBody =>
      'This DELETES all data this device has downloaded from the server. Your shop\'s data will be re-downloaded on next sync. Any sales that haven\'t been sent will be lost. Only do this if support tells you to.';

  @override
  String get storageSyncResetTypePrompt => 'Type RESET to confirm';

  @override
  String get storageSyncResetTypeWord => 'RESET';

  @override
  String get storageSyncResetOfflineBlocker =>
      'Connect to internet first — you have pending sales that need to send before reset.';

  @override
  String storageSyncResetPendingFailedBlocker(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count posts couldn\'t send. Review them in Failed posts before reset.',
      one: '1 post couldn\'t send. Review it in Failed posts before reset.',
    );
    return '$_temp0';
  }

  @override
  String get storageSyncResetConfirmAction => 'RESET';

  @override
  String get storageSyncResetDoneToast =>
      'Local data reset. Downloading fresh data...';

  @override
  String get storageSyncResetFailedToast => 'Reset failed';

  @override
  String get storageSyncSettingsHeader => 'Settings';

  @override
  String get storageSyncWifiOnlyLabel => 'Sync only on Wi-Fi';

  @override
  String get storageSyncDrawerEntry => 'Storage & sync';

  @override
  String get drawerManageCategories => 'Categories';

  @override
  String get manageCategoriesTitle => 'Categories';

  @override
  String get manageCategoriesProductsTab => 'Products';

  @override
  String get manageCategoriesExpensesTab => 'Expenses';

  @override
  String get manageCategoriesAdd => 'Add category';

  @override
  String get manageCategoriesEmpty => 'No categories yet. Tap + to add one.';

  @override
  String get manageCategoriesDefaultBadge => 'Built-in';

  @override
  String get manageCategoriesNameLabel => 'Category name';

  @override
  String get manageCategoriesNewTitle => 'New category';

  @override
  String get manageCategoriesRenameTitle => 'Rename category';

  @override
  String get manageCategoriesSave => 'Save';

  @override
  String get manageCategoriesRename => 'Rename';

  @override
  String get manageCategoriesHide => 'Hide';

  @override
  String get manageCategoriesHideConfirmTitle => 'Hide category?';

  @override
  String get manageCategoriesHideConfirmBody =>
      'It will no longer appear when adding or editing items. Items already using it keep it until you change them.';

  @override
  String get failedPostsTitle => 'Failed posts';

  @override
  String get failedPostsRetryButton => 'RETRY';

  @override
  String get failedPostsDiscardButton => 'DISCARD';

  @override
  String get failedPostsDiscardConfirmTitle => 'Discard this post?';

  @override
  String get failedPostsDiscardConfirmBody =>
      'You can\'t recover it. Continue?';

  @override
  String get failedPostsDiscardConfirmAction => 'DISCARD';

  @override
  String get failedPostsEmptyState => 'No failed posts.';

  @override
  String get syncFirstTimeSetupTitle => 'Connect to load your shop\'s data';

  @override
  String get syncFirstTimeSetupBody =>
      'We need to fetch your items, customers, and recent transactions one time before you can work offline. Open Wi-Fi or mobile data, then tap Retry.';

  @override
  String get syncFirstTimeSetupRetryButton => 'RETRY';

  @override
  String get syncFirstTimeLoadingTitle => 'Setting up your shop…';

  @override
  String get syncFirstTimeLoadingBody =>
      'Loading your items, customers, and recent activity. This only happens once.';

  @override
  String syncIssueBannerLabel(String time) {
    return '⚠ Working offline since $time. Tap to retry sync.';
  }

  @override
  String get syncForceSyncingToast => 'Syncing…';

  @override
  String syncForceSyncedToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Synced $count updates',
      one: 'Synced 1 update',
      zero: 'Already up to date',
    );
    return '$_temp0';
  }

  @override
  String get syncForceFailedToast => 'Couldn\'t sync — try again later.';
}

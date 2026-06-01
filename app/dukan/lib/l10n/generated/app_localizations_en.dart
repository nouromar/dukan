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
  String get languageEnglish => 'EN';

  @override
  String get languageSomali => 'SO';

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
  String get repeatLastBono => 'Repeat last bono';

  @override
  String get bonoAttached => 'Bono attached';

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
}

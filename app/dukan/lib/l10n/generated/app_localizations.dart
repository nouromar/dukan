import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_so.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('so'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Dukan'**
  String get appTitle;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'EN'**
  String get languageEnglish;

  /// No description provided for @languageSomali.
  ///
  /// In en, this message translates to:
  /// **'SO'**
  String get languageSomali;

  /// No description provided for @homeHint.
  ///
  /// In en, this message translates to:
  /// **'Choose today\'s job'**
  String get homeHint;

  /// No description provided for @sale.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get sale;

  /// No description provided for @receive.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get receive;

  /// No description provided for @payment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get payment;

  /// No description provided for @expense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get expense;

  /// No description provided for @cash.
  ///
  /// In en, this message translates to:
  /// **'CASH'**
  String get cash;

  /// No description provided for @debt.
  ///
  /// In en, this message translates to:
  /// **'DEBT'**
  String get debt;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM'**
  String get confirm;

  /// No description provided for @searchItems.
  ///
  /// In en, this message translates to:
  /// **'Search items'**
  String get searchItems;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @cart.
  ///
  /// In en, this message translates to:
  /// **'CART'**
  String get cart;

  /// No description provided for @itemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 items} =1{1 item} other{{count} items}}'**
  String itemsCount(num count);

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @savedUndo.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get savedUndo;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get quantity;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @optionalPrice.
  ///
  /// In en, this message translates to:
  /// **'Price override'**
  String get optionalPrice;

  /// No description provided for @addToCart.
  ///
  /// In en, this message translates to:
  /// **'ADD TO CART'**
  String get addToCart;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @customerDebt.
  ///
  /// In en, this message translates to:
  /// **'Customer for debt'**
  String get customerDebt;

  /// No description provided for @searchCustomers.
  ///
  /// In en, this message translates to:
  /// **'Search customers'**
  String get searchCustomers;

  /// No description provided for @emptySaleHint.
  ///
  /// In en, this message translates to:
  /// **'Tap item tiles to add. Long-press for quantity or price.'**
  String get emptySaleHint;

  /// No description provided for @receiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get receiveTitle;

  /// No description provided for @supplierFirst.
  ///
  /// In en, this message translates to:
  /// **'Pick supplier first'**
  String get supplierFirst;

  /// No description provided for @recentSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Recent suppliers'**
  String get recentSuppliers;

  /// No description provided for @searchSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Search suppliers'**
  String get searchSuppliers;

  /// No description provided for @newSupplier.
  ///
  /// In en, this message translates to:
  /// **'+ New supplier'**
  String get newSupplier;

  /// No description provided for @newSupplierStub.
  ///
  /// In en, this message translates to:
  /// **'New supplier stub — name and phone in production.'**
  String get newSupplierStub;

  /// No description provided for @repeatLastBono.
  ///
  /// In en, this message translates to:
  /// **'Repeat last bono'**
  String get repeatLastBono;

  /// No description provided for @bonoAttached.
  ///
  /// In en, this message translates to:
  /// **'Bono attached'**
  String get bonoAttached;

  /// No description provided for @attachBono.
  ///
  /// In en, this message translates to:
  /// **'Attach bono photo'**
  String get attachBono;

  /// No description provided for @receiveFrom.
  ///
  /// In en, this message translates to:
  /// **'Receive from {supplier}'**
  String receiveFrom(Object supplier);

  /// No description provided for @item.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get item;

  /// No description provided for @searchItem.
  ///
  /// In en, this message translates to:
  /// **'Search item'**
  String get searchItem;

  /// No description provided for @unit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get unit;

  /// No description provided for @cost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get cost;

  /// No description provided for @perUnit.
  ///
  /// In en, this message translates to:
  /// **'per unit'**
  String get perUnit;

  /// No description provided for @line.
  ///
  /// In en, this message translates to:
  /// **'line'**
  String get line;

  /// No description provided for @lineTotal.
  ///
  /// In en, this message translates to:
  /// **'Line total'**
  String get lineTotal;

  /// No description provided for @addLine.
  ///
  /// In en, this message translates to:
  /// **'ADD LINE'**
  String get addLine;

  /// No description provided for @linesSoFar.
  ///
  /// In en, this message translates to:
  /// **'Lines so far: {count}'**
  String linesSoFar(Object count);

  /// No description provided for @bonoTotal.
  ///
  /// In en, this message translates to:
  /// **'Bono total'**
  String get bonoTotal;

  /// No description provided for @paidNow.
  ///
  /// In en, this message translates to:
  /// **'Paid now'**
  String get paidNow;

  /// No description provided for @credit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get credit;

  /// No description provided for @paidAll.
  ///
  /// In en, this message translates to:
  /// **'Paid all'**
  String get paidAll;

  /// No description provided for @mismatchWarning.
  ///
  /// In en, this message translates to:
  /// **'Bono total differs from lines — OK to continue.'**
  String get mismatchWarning;

  /// No description provided for @chooseItemWarning.
  ///
  /// In en, this message translates to:
  /// **'Choose item, qty, and cost.'**
  String get chooseItemWarning;

  /// No description provided for @confirmReceive.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM RECEIVE'**
  String get confirmReceive;

  /// No description provided for @numberDone.
  ///
  /// In en, this message translates to:
  /// **'DONE'**
  String get numberDone;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'CLEAR'**
  String get clear;

  /// No description provided for @backspace.
  ///
  /// In en, this message translates to:
  /// **'DEL'**
  String get backspace;

  /// No description provided for @paymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer payment'**
  String get paymentTitle;

  /// No description provided for @pickCustomer.
  ///
  /// In en, this message translates to:
  /// **'Pick customer'**
  String get pickCustomer;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @confirmPayment.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM PAYMENT'**
  String get confirmPayment;

  /// No description provided for @expenseTitle.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get expenseTitle;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @confirmExpense.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM EXPENSE'**
  String get confirmExpense;

  /// No description provided for @rent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get rent;

  /// No description provided for @power.
  ///
  /// In en, this message translates to:
  /// **'Power'**
  String get power;

  /// No description provided for @salary.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get salary;

  /// No description provided for @water.
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get water;

  /// No description provided for @transport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get transport;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Mock screen saved. Undo?'**
  String get comingSoon;

  /// No description provided for @supabaseConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect Dukan to Supabase'**
  String get supabaseConfigTitle;

  /// No description provided for @supabaseConfigMessage.
  ///
  /// In en, this message translates to:
  /// **'Add Supabase URL and anon key to use login. You can still open the prototype screens.'**
  String get supabaseConfigMessage;

  /// No description provided for @supabaseConfigCommand.
  ///
  /// In en, this message translates to:
  /// **'flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...'**
  String get supabaseConfigCommand;

  /// No description provided for @openPrototype.
  ///
  /// In en, this message translates to:
  /// **'Open prototype'**
  String get openPrototype;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get loginTitle;

  /// No description provided for @loginHeadline.
  ///
  /// In en, this message translates to:
  /// **'Use your phone number'**
  String get loginHeadline;

  /// No description provided for @loginBody.
  ///
  /// In en, this message translates to:
  /// **'We will send a one-time code. Dukan can deliver it by WhatsApp from the backend.'**
  String get loginBody;

  /// No description provided for @phoneNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumberLabel;

  /// No description provided for @sendOtpButton.
  ///
  /// In en, this message translates to:
  /// **'SEND CODE'**
  String get sendOtpButton;

  /// No description provided for @verifyOtpTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter code'**
  String get verifyOtpTitle;

  /// No description provided for @verifyOtpHeadline.
  ///
  /// In en, this message translates to:
  /// **'Check your phone'**
  String get verifyOtpHeadline;

  /// No description provided for @verifyOtpBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the code sent to {phone}.'**
  String verifyOtpBody(Object phone);

  /// No description provided for @otpCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get otpCodeLabel;

  /// No description provided for @verifyOtpButton.
  ///
  /// In en, this message translates to:
  /// **'VERIFY'**
  String get verifyOtpButton;

  /// No description provided for @changePhoneButton.
  ///
  /// In en, this message translates to:
  /// **'Change phone number'**
  String get changePhoneButton;

  /// No description provided for @ownerOnboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Create shop'**
  String get ownerOnboardingTitle;

  /// No description provided for @ownerOnboardingHeadline.
  ///
  /// In en, this message translates to:
  /// **'Set up your first shop'**
  String get ownerOnboardingHeadline;

  /// No description provided for @ownerOnboardingBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the business and shop names. You can add workers later.'**
  String get ownerOnboardingBody;

  /// No description provided for @businessNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Business name'**
  String get businessNameLabel;

  /// No description provided for @shopNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Shop name'**
  String get shopNameLabel;

  /// No description provided for @createShopButton.
  ///
  /// In en, this message translates to:
  /// **'CREATE SHOP'**
  String get createShopButton;

  /// No description provided for @chooseShopTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose shop'**
  String get chooseShopTitle;

  /// No description provided for @shopSetupStatus.
  ///
  /// In en, this message translates to:
  /// **'Setup: {status}'**
  String shopSetupStatus(Object status);

  /// No description provided for @activeShopLabel.
  ///
  /// In en, this message translates to:
  /// **'Shop: {shop}'**
  String activeShopLabel(Object shop);

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @invalidPhoneMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number, for example +252612345678.'**
  String get invalidPhoneMessage;

  /// No description provided for @missingPendingPhoneMessage.
  ///
  /// In en, this message translates to:
  /// **'Start with your phone number first.'**
  String get missingPendingPhoneMessage;

  /// No description provided for @missingShopNamesMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter both business name and shop name.'**
  String get missingShopNamesMessage;

  /// No description provided for @sendOtpFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'We could not send the code. Check the phone number or internet and try again.'**
  String get sendOtpFailedMessage;

  /// No description provided for @verifyOtpFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'The code is wrong or expired. Check the code and try again.'**
  String get verifyOtpFailedMessage;

  /// No description provided for @createShopFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'We could not create the shop. Check your internet and try again.'**
  String get createShopFailedMessage;

  /// No description provided for @shopLoadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not open shops'**
  String get shopLoadFailedTitle;

  /// No description provided for @shopLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Check your internet and try again. If this continues, ask the shop owner to check your access.'**
  String get shopLoadFailedMessage;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'TRY AGAIN'**
  String get tryAgain;

  /// No description provided for @setupStepTemplateTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your shop type'**
  String get setupStepTemplateTitle;

  /// No description provided for @setupStepTemplateBody.
  ///
  /// In en, this message translates to:
  /// **'Pick a starter pack so common items and settings are ready for you.'**
  String get setupStepTemplateBody;

  /// No description provided for @setupStepTemplateDone.
  ///
  /// In en, this message translates to:
  /// **'Type chosen: {name}'**
  String setupStepTemplateDone(Object name);

  /// No description provided for @setupStepFinishTitle.
  ///
  /// In en, this message translates to:
  /// **'Finish setup'**
  String get setupStepFinishTitle;

  /// No description provided for @setupStepFinishBody.
  ///
  /// In en, this message translates to:
  /// **'Confirm and start using your shop.'**
  String get setupStepFinishBody;

  /// No description provided for @setupStepFinishButton.
  ///
  /// In en, this message translates to:
  /// **'FINISH SETUP'**
  String get setupStepFinishButton;

  /// No description provided for @templatePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your shop type'**
  String get templatePickerTitle;

  /// No description provided for @applyTemplateButton.
  ///
  /// In en, this message translates to:
  /// **'USE THIS'**
  String get applyTemplateButton;

  /// No description provided for @applyTemplateFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not apply the template. Check your internet and try again.'**
  String get applyTemplateFailedMessage;

  /// No description provided for @templatesEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No shop types are available yet. Contact support if this keeps happening.'**
  String get templatesEmptyMessage;

  /// No description provided for @completeSetupFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not finish setup. Try again.'**
  String get completeSetupFailedMessage;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get openSettings;

  /// No description provided for @settingsShopNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Shop name'**
  String get settingsShopNameLabel;

  /// No description provided for @settingsCurrencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get settingsCurrencyLabel;

  /// No description provided for @settingsLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Default language'**
  String get settingsLanguageLabel;

  /// No description provided for @settingsTimezoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Timezone'**
  String get settingsTimezoneLabel;

  /// No description provided for @settingsSaveButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get settingsSaveButton;

  /// No description provided for @settingsSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settingsSavedToast;

  /// No description provided for @settingsSaveFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not save settings. Try again.'**
  String get settingsSaveFailedMessage;

  /// No description provided for @productsTitle.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get productsTitle;

  /// No description provided for @productsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search Somali or English'**
  String get productsSearchHint;

  /// No description provided for @productsInYourShop.
  ///
  /// In en, this message translates to:
  /// **'In your shop'**
  String get productsInYourShop;

  /// No description provided for @productsFromCatalog.
  ///
  /// In en, this message translates to:
  /// **'From catalog'**
  String get productsFromCatalog;

  /// No description provided for @productsStockLabel.
  ///
  /// In en, this message translates to:
  /// **'{quantity} {unit} in stock'**
  String productsStockLabel(Object quantity, Object unit);

  /// No description provided for @productsNoStock.
  ///
  /// In en, this message translates to:
  /// **'No stock yet'**
  String get productsNoStock;

  /// No description provided for @productsAddToShopButton.
  ///
  /// In en, this message translates to:
  /// **'ADD'**
  String get productsAddToShopButton;

  /// No description provided for @productsAddingToShop.
  ///
  /// In en, this message translates to:
  /// **'Adding…'**
  String get productsAddingToShop;

  /// No description provided for @productsAddedToShopToast.
  ///
  /// In en, this message translates to:
  /// **'{name} added to your shop'**
  String productsAddedToShopToast(Object name);

  /// No description provided for @productsAddToShopFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not add {name}. Try again.'**
  String productsAddToShopFailedMessage(Object name);

  /// No description provided for @productsNewItemButton.
  ///
  /// In en, this message translates to:
  /// **'+ NEW ITEM'**
  String get productsNewItemButton;

  /// No description provided for @productsNewItemUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Adding off-catalog items comes later.'**
  String get productsNewItemUnavailable;

  /// No description provided for @productsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No items yet. Add one from the catalog below.'**
  String get productsEmptyMessage;

  /// No description provided for @productsSearchEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches “{query}”.'**
  String productsSearchEmptyMessage(Object query);

  /// No description provided for @productsLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load products. Check your internet and try again.'**
  String get productsLoadFailedMessage;

  /// No description provided for @saleTitle.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get saleTitle;

  /// No description provided for @saleSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search Somali or English'**
  String get saleSearchHint;

  /// No description provided for @saleCartSummary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No items} =1{1 item} other{{count} items}} · {total}'**
  String saleCartSummary(num count, Object total);

  /// No description provided for @saleEmptyFavoritesMessage.
  ///
  /// In en, this message translates to:
  /// **'Add products from the catalog to see them here.'**
  String get saleEmptyFavoritesMessage;

  /// No description provided for @saleSearchEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches “{query}”.'**
  String saleSearchEmptyMessage(Object query);

  /// No description provided for @saleLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load items. Check your internet and try again.'**
  String get saleLoadFailedMessage;

  /// No description provided for @saleCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get saleCash;

  /// No description provided for @saleDebt.
  ///
  /// In en, this message translates to:
  /// **'Debt'**
  String get saleDebt;

  /// No description provided for @salePickCustomerButton.
  ///
  /// In en, this message translates to:
  /// **'Pick customer'**
  String get salePickCustomerButton;

  /// No description provided for @saleCustomerChip.
  ///
  /// In en, this message translates to:
  /// **'{name} · owes {amount}'**
  String saleCustomerChip(Object amount, Object name);

  /// No description provided for @saleSaveButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get saleSaveButton;

  /// No description provided for @saleSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saleSavedToast;

  /// No description provided for @salePostFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not save the sale. Check your internet and try again.'**
  String get salePostFailedMessage;

  /// No description provided for @saleNeedItemsMessage.
  ///
  /// In en, this message translates to:
  /// **'Add at least one item before saving.'**
  String get saleNeedItemsMessage;

  /// No description provided for @saleNeedCustomerMessage.
  ///
  /// In en, this message translates to:
  /// **'Pick the customer for this debt sale.'**
  String get saleNeedCustomerMessage;

  /// No description provided for @saleAddedItemToast.
  ///
  /// In en, this message translates to:
  /// **'{name} added'**
  String saleAddedItemToast(Object name);

  /// No description provided for @saleAddItemFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not add {name}. Try again.'**
  String saleAddItemFailedMessage(Object name);

  /// No description provided for @customerPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose customer'**
  String get customerPickerTitle;

  /// No description provided for @customerPickerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search name or phone'**
  String get customerPickerSearchHint;

  /// No description provided for @customerPickerOwesLabel.
  ///
  /// In en, this message translates to:
  /// **'owes {amount}'**
  String customerPickerOwesLabel(Object amount);

  /// No description provided for @customerPickerNoDebtLabel.
  ///
  /// In en, this message translates to:
  /// **'no debt'**
  String get customerPickerNoDebtLabel;

  /// No description provided for @customerPickerEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No customers yet. Add one when you record a debt sale.'**
  String get customerPickerEmptyMessage;

  /// No description provided for @customerPickerSearchEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No customers match “{query}”.'**
  String customerPickerSearchEmptyMessage(Object query);

  /// No description provided for @customerPickerLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load customers. Check your internet and try again.'**
  String get customerPickerLoadFailedMessage;

  /// No description provided for @customerNewButton.
  ///
  /// In en, this message translates to:
  /// **'+ NEW CUSTOMER'**
  String get customerNewButton;

  /// No description provided for @customerNewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Adding new customers comes later.'**
  String get customerNewUnavailable;

  /// No description provided for @cartLineSubtotal.
  ///
  /// In en, this message translates to:
  /// **'{quantity} × {unitPrice} = {subtotal}'**
  String cartLineSubtotal(Object quantity, Object subtotal, Object unitPrice);

  /// No description provided for @cartRemoveLineTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String cartRemoveLineTooltip(Object name);

  /// No description provided for @cartExpandHint.
  ///
  /// In en, this message translates to:
  /// **'Show items'**
  String get cartExpandHint;

  /// No description provided for @cartCollapseHint.
  ///
  /// In en, this message translates to:
  /// **'Hide items'**
  String get cartCollapseHint;

  /// No description provided for @cartClearAllButton.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get cartClearAllButton;

  /// No description provided for @cartClearConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear {count, plural, =1{1 item} other{{count} items}} from cart?'**
  String cartClearConfirmTitle(num count);

  /// No description provided for @cartClearConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This won\'t undo any saved sale.'**
  String get cartClearConfirmBody;

  /// No description provided for @cartClearConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'CLEAR'**
  String get cartClearConfirmYes;

  /// No description provided for @cartClearConfirmNo.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get cartClearConfirmNo;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'so'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'so':
      return AppLocalizationsSo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

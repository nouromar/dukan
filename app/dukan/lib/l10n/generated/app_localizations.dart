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

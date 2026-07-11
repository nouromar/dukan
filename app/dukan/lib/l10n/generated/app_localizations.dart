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
  /// **'DukanPro'**
  String get appTitle;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageSomali.
  ///
  /// In en, this message translates to:
  /// **'Somali'**
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

  /// No description provided for @paymentInLabel.
  ///
  /// In en, this message translates to:
  /// **'Money In'**
  String get paymentInLabel;

  /// No description provided for @paymentOutLabel.
  ///
  /// In en, this message translates to:
  /// **'Money Out'**
  String get paymentOutLabel;

  /// No description provided for @paymentDetailSettledHeader.
  ///
  /// In en, this message translates to:
  /// **'Paid for'**
  String get paymentDetailSettledHeader;

  /// No description provided for @paymentFromSaleHeader.
  ///
  /// In en, this message translates to:
  /// **'From a cash sale'**
  String get paymentFromSaleHeader;

  /// No description provided for @paymentFromReceiveHeader.
  ///
  /// In en, this message translates to:
  /// **'From a stock receive'**
  String get paymentFromReceiveHeader;

  /// No description provided for @paymentEffectIn.
  ///
  /// In en, this message translates to:
  /// **'Lowered {name}\'s debt by {amount}.'**
  String paymentEffectIn(String name, String amount);

  /// No description provided for @paymentEffectOut.
  ///
  /// In en, this message translates to:
  /// **'Reduced what you owe {name} by {amount}.'**
  String paymentEffectOut(String name, String amount);

  /// No description provided for @paymentDetailLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this payment.'**
  String get paymentDetailLoadFailedMessage;

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

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

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

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @receiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get receiveTitle;

  /// No description provided for @bonoAttachTooltip.
  ///
  /// In en, this message translates to:
  /// **'Attach bono photo'**
  String get bonoAttachTooltip;

  /// No description provided for @bonoAttachedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Bono attached — tap to replace'**
  String get bonoAttachedTooltip;

  /// No description provided for @bonoAttachCamera.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get bonoAttachCamera;

  /// No description provided for @bonoAttachGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get bonoAttachGallery;

  /// No description provided for @bonoAttachedToast.
  ///
  /// In en, this message translates to:
  /// **'Bono photo attached'**
  String get bonoAttachedToast;

  /// No description provided for @bonoAttachFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not attach the bono. Try again.'**
  String get bonoAttachFailedMessage;

  /// No description provided for @bonoSuggestionsReading.
  ///
  /// In en, this message translates to:
  /// **'Reading the bono…'**
  String get bonoSuggestionsReading;

  /// No description provided for @bonoSuggestionsFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the bono — enter the lines by hand'**
  String get bonoSuggestionsFailed;

  /// No description provided for @bonoSuggestionsFound.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 line read from the bono} other{{count} lines read from the bono}}'**
  String bonoSuggestionsFound(int count);

  /// No description provided for @bonoSuggestionsReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get bonoSuggestionsReview;

  /// No description provided for @bonoSuggestionsTitle.
  ///
  /// In en, this message translates to:
  /// **'From the bono'**
  String get bonoSuggestionsTitle;

  /// No description provided for @bonoSuggestionsMatchedSection.
  ///
  /// In en, this message translates to:
  /// **'Matched'**
  String get bonoSuggestionsMatchedSection;

  /// No description provided for @bonoSuggestionsLikelySection.
  ///
  /// In en, this message translates to:
  /// **'Likely — check these'**
  String get bonoSuggestionsLikelySection;

  /// No description provided for @bonoSuggestionsUnmatchedSection.
  ///
  /// In en, this message translates to:
  /// **'Not found — add these by hand'**
  String get bonoSuggestionsUnmatchedSection;

  /// No description provided for @bonoSuggestionsApply.
  ///
  /// In en, this message translates to:
  /// **'ADD LINES'**
  String get bonoSuggestionsApply;

  /// No description provided for @bonoSuggestionsAppliedToast.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added 1 line} other{Added {count} lines}}'**
  String bonoSuggestionsAppliedToast(int count);

  /// No description provided for @bonoReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review bono'**
  String get bonoReviewTitle;

  /// No description provided for @bonoReviewReady.
  ///
  /// In en, this message translates to:
  /// **'{count} ready'**
  String bonoReviewReady(int count);

  /// No description provided for @bonoReviewNeedsReview.
  ///
  /// In en, this message translates to:
  /// **'{count} need review'**
  String bonoReviewNeedsReview(int count);

  /// No description provided for @bonoReviewStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get bonoReviewStatusReady;

  /// No description provided for @bonoReviewStatusNeedsReview.
  ///
  /// In en, this message translates to:
  /// **'Needs review'**
  String get bonoReviewStatusNeedsReview;

  /// No description provided for @bonoReviewNewItem.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get bonoReviewNewItem;

  /// No description provided for @bonoReviewMarkReady.
  ///
  /// In en, this message translates to:
  /// **'Mark ready'**
  String get bonoReviewMarkReady;

  /// No description provided for @bonoReviewCreateItem.
  ///
  /// In en, this message translates to:
  /// **'Create “{name}”'**
  String bonoReviewCreateItem(String name);

  /// No description provided for @bonoReviewAddPackaging.
  ///
  /// In en, this message translates to:
  /// **'Add packaging — {label}'**
  String bonoReviewAddPackaging(String label);

  /// No description provided for @bonoReviewStatusNewItem.
  ///
  /// In en, this message translates to:
  /// **'New item'**
  String get bonoReviewStatusNewItem;

  /// No description provided for @bonoReviewStatusNewSize.
  ///
  /// In en, this message translates to:
  /// **'New size'**
  String get bonoReviewStatusNewSize;

  /// No description provided for @bonoReviewEditNew.
  ///
  /// In en, this message translates to:
  /// **'Edit before creating'**
  String get bonoReviewEditNew;

  /// No description provided for @bonoReviewKeepPackaging.
  ///
  /// In en, this message translates to:
  /// **'Keep current packaging'**
  String get bonoReviewKeepPackaging;

  /// No description provided for @bonoReviewPickExisting.
  ///
  /// In en, this message translates to:
  /// **'Pick existing product'**
  String get bonoReviewPickExisting;

  /// No description provided for @bonoReviewChangeItem.
  ///
  /// In en, this message translates to:
  /// **'Change item'**
  String get bonoReviewChangeItem;

  /// No description provided for @bonoReviewViewPhoto.
  ///
  /// In en, this message translates to:
  /// **'View bono photo'**
  String get bonoReviewViewPhoto;

  /// No description provided for @bonoReviewFlag.
  ///
  /// In en, this message translates to:
  /// **'Flag for review'**
  String get bonoReviewFlag;

  /// No description provided for @bonoReviewRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove line'**
  String get bonoReviewRemove;

  /// No description provided for @bonoReviewAccept.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Accept 1 line} other{Accept {count} lines}}'**
  String bonoReviewAccept(int count);

  /// No description provided for @bonoReviewAcceptGate.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} need review'**
  String bonoReviewAcceptGate(int count, int total);

  /// No description provided for @bonoReviewEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit line'**
  String get bonoReviewEditTitle;

  /// No description provided for @bonoReviewEditItem.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get bonoReviewEditItem;

  /// No description provided for @bonoReviewEditCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get bonoReviewEditCategory;

  /// No description provided for @bonoReviewEditPackaging.
  ///
  /// In en, this message translates to:
  /// **'Packaging'**
  String get bonoReviewEditPackaging;

  /// No description provided for @bonoReviewEditTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get bonoReviewEditTotal;

  /// No description provided for @bonoReviewEditSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get bonoReviewEditSave;

  /// No description provided for @bonoReviewUncategorized.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get bonoReviewUncategorized;

  /// No description provided for @bonoReviewPriceRequired.
  ///
  /// In en, this message translates to:
  /// **'Add a price first'**
  String get bonoReviewPriceRequired;

  /// No description provided for @bonoReviewPickPackaging.
  ///
  /// In en, this message translates to:
  /// **'Pick packaging'**
  String get bonoReviewPickPackaging;

  /// No description provided for @bonoReviewSavingItems.
  ///
  /// In en, this message translates to:
  /// **'Saving new items…'**
  String get bonoReviewSavingItems;

  /// No description provided for @bonoChipLabel.
  ///
  /// In en, this message translates to:
  /// **'Bono'**
  String get bonoChipLabel;

  /// No description provided for @bonoHintTitle.
  ///
  /// In en, this message translates to:
  /// **'Take a photo of the bono'**
  String get bonoHintTitle;

  /// No description provided for @bonoHintSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll read the items for you'**
  String get bonoHintSubtitle;

  /// No description provided for @receiveDetailViewBonoButton.
  ///
  /// In en, this message translates to:
  /// **'View bono'**
  String get receiveDetailViewBonoButton;

  /// No description provided for @receiveDetailViewBonoTitle.
  ///
  /// In en, this message translates to:
  /// **'Bono'**
  String get receiveDetailViewBonoTitle;

  /// No description provided for @receiveDetailBonoUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Bono photo unavailable'**
  String get receiveDetailBonoUnavailable;

  /// No description provided for @bonoBindChooseItem.
  ///
  /// In en, this message translates to:
  /// **'Choose item'**
  String get bonoBindChooseItem;

  /// No description provided for @bonoBindPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Which item is this?'**
  String get bonoBindPickerTitle;

  /// No description provided for @bonoBindSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search items'**
  String get bonoBindSearchHint;

  /// No description provided for @bonoBindAddNew.
  ///
  /// In en, this message translates to:
  /// **'Add new item'**
  String get bonoBindAddNew;

  /// No description provided for @bonoBindEmpty.
  ///
  /// In en, this message translates to:
  /// **'No match — add it as a new item'**
  String get bonoBindEmpty;

  /// No description provided for @partyDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Party'**
  String get partyDetailTitle;

  /// No description provided for @partyHideTooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get partyHideTooltip;

  /// No description provided for @partyHideConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Hide this contact?'**
  String get partyHideConfirmTitle;

  /// No description provided for @partyHideConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'They\'ll be removed from your lists. Any balance and history stay. You can ask support to bring them back.'**
  String get partyHideConfirmBody;

  /// No description provided for @partyHideConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'HIDE'**
  String get partyHideConfirmYes;

  /// No description provided for @partyHiddenToast.
  ///
  /// In en, this message translates to:
  /// **'Contact hidden'**
  String get partyHiddenToast;

  /// No description provided for @backdateChipToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get backdateChipToday;

  /// No description provided for @backdateChipTooltip.
  ///
  /// In en, this message translates to:
  /// **'Change date'**
  String get backdateChipTooltip;

  /// No description provided for @backdateBannerLabel.
  ///
  /// In en, this message translates to:
  /// **'Recording for {date}'**
  String backdateBannerLabel(String date);

  /// No description provided for @backdateBackToToday.
  ///
  /// In en, this message translates to:
  /// **'TODAY'**
  String get backdateBackToToday;

  /// No description provided for @reportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsTitle;

  /// No description provided for @drawerReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get drawerReports;

  /// No description provided for @reportsSalesTitle.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get reportsSalesTitle;

  /// No description provided for @reportsProfitTitle.
  ///
  /// In en, this message translates to:
  /// **'Profit'**
  String get reportsProfitTitle;

  /// No description provided for @reportsStockTitle.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get reportsStockTitle;

  /// No description provided for @reportsRevenueLabel.
  ///
  /// In en, this message translates to:
  /// **'Sales total'**
  String get reportsRevenueLabel;

  /// No description provided for @reportsSalesCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Number of sales'**
  String get reportsSalesCountLabel;

  /// No description provided for @reportsAvgSaleLabel.
  ///
  /// In en, this message translates to:
  /// **'Average sale'**
  String get reportsAvgSaleLabel;

  /// No description provided for @reportsCostLabel.
  ///
  /// In en, this message translates to:
  /// **'Cost of goods'**
  String get reportsCostLabel;

  /// No description provided for @reportsGrossProfitLabel.
  ///
  /// In en, this message translates to:
  /// **'Gross profit'**
  String get reportsGrossProfitLabel;

  /// No description provided for @reportsExpensesLabel.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get reportsExpensesLabel;

  /// No description provided for @reportsNetProfitLabel.
  ///
  /// In en, this message translates to:
  /// **'Net profit'**
  String get reportsNetProfitLabel;

  /// No description provided for @reportsMarginLabel.
  ///
  /// In en, this message translates to:
  /// **'Margin'**
  String get reportsMarginLabel;

  /// No description provided for @reportsItemsLabel.
  ///
  /// In en, this message translates to:
  /// **'Products in stock'**
  String get reportsItemsLabel;

  /// No description provided for @reportsStockValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Stock value'**
  String get reportsStockValueLabel;

  /// No description provided for @reportsLowStockLabel.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get reportsLowStockLabel;

  /// No description provided for @reportsLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load reports. Check your internet and try again.'**
  String get reportsLoadFailedMessage;

  /// No description provided for @partyDetailLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load this party.'**
  String get partyDetailLoadFailedMessage;

  /// No description provided for @partyDetailReceivableLabel.
  ///
  /// In en, this message translates to:
  /// **'They owe you'**
  String get partyDetailReceivableLabel;

  /// No description provided for @partyDetailPayableLabel.
  ///
  /// In en, this message translates to:
  /// **'You owe them'**
  String get partyDetailPayableLabel;

  /// No description provided for @partyDetailPayButton.
  ///
  /// In en, this message translates to:
  /// **'PAY'**
  String get partyDetailPayButton;

  /// No description provided for @partyDetailSalesHeader.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get partyDetailSalesHeader;

  /// No description provided for @partyDetailReceivesHeader.
  ///
  /// In en, this message translates to:
  /// **'Receives'**
  String get partyDetailReceivesHeader;

  /// No description provided for @partyDetailPaymentsHeader.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get partyDetailPaymentsHeader;

  /// No description provided for @homeTodayHeader.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get homeTodayHeader;

  /// No description provided for @homeSummaryLabel.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get homeSummaryLabel;

  /// No description provided for @homeSalesTodayLabel.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get homeSalesTodayLabel;

  /// No description provided for @homeReceivedLabel.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get homeReceivedLabel;

  /// No description provided for @homeMoneyInLabel.
  ///
  /// In en, this message translates to:
  /// **'Money in'**
  String get homeMoneyInLabel;

  /// No description provided for @homeMoneyOutLabel.
  ///
  /// In en, this message translates to:
  /// **'Money out'**
  String get homeMoneyOutLabel;

  /// No description provided for @homeExpensesLabel.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get homeExpensesLabel;

  /// No description provided for @homeNeedsAttentionLabel.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get homeNeedsAttentionLabel;

  /// No description provided for @homeReceivablesLabel.
  ///
  /// In en, this message translates to:
  /// **'Customers owe you'**
  String get homeReceivablesLabel;

  /// No description provided for @homePayablesLabel.
  ///
  /// In en, this message translates to:
  /// **'You owe suppliers'**
  String get homePayablesLabel;

  /// No description provided for @homeLowStockLabel.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get homeLowStockLabel;

  /// No description provided for @homeLowStockCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{none} =1{1 item} other{{count} items}}'**
  String homeLowStockCount(int count);

  /// No description provided for @lowStockReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get lowStockReportTitle;

  /// No description provided for @lowStockReportEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Nothing is running low.'**
  String get lowStockReportEmptyMessage;

  /// No description provided for @reportLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load. Pull down to try again.'**
  String get reportLoadFailedMessage;

  /// No description provided for @filterTooltip.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filterTooltip;

  /// No description provided for @filterSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filterSheetTitle;

  /// No description provided for @filterApplyButton.
  ///
  /// In en, this message translates to:
  /// **'APPLY'**
  String get filterApplyButton;

  /// No description provided for @filterResetButton.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get filterResetButton;

  /// No description provided for @dateRangeToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dateRangeToday;

  /// No description provided for @dateRangeWeek.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get dateRangeWeek;

  /// No description provided for @dateRangeMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get dateRangeMonth;

  /// No description provided for @dateRangeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get dateRangeAll;

  /// No description provided for @dateRangeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get dateRangeCustom;

  /// No description provided for @filterPartyAny.
  ///
  /// In en, this message translates to:
  /// **'Anyone'**
  String get filterPartyAny;

  /// No description provided for @filterHideVoided.
  ///
  /// In en, this message translates to:
  /// **'Hide voided'**
  String get filterHideVoided;

  /// No description provided for @filterCategoryAny.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get filterCategoryAny;

  /// No description provided for @filterLowStockOnly.
  ///
  /// In en, this message translates to:
  /// **'Low stock only'**
  String get filterLowStockOnly;

  /// No description provided for @filterNoPriceOnly.
  ///
  /// In en, this message translates to:
  /// **'No price yet'**
  String get filterNoPriceOnly;

  /// No description provided for @lowStockSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search product'**
  String get lowStockSearchHint;

  /// No description provided for @filterChipParty.
  ///
  /// In en, this message translates to:
  /// **'Party: {name}'**
  String filterChipParty(String name);

  /// No description provided for @filterChipHideVoided.
  ///
  /// In en, this message translates to:
  /// **'Hiding voided'**
  String get filterChipHideVoided;

  /// No description provided for @filterChipCategory.
  ///
  /// In en, this message translates to:
  /// **'{name}'**
  String filterChipCategory(String name);

  /// No description provided for @filterChipLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get filterChipLowStock;

  /// No description provided for @filterChipNoPrice.
  ///
  /// In en, this message translates to:
  /// **'No price'**
  String get filterChipNoPrice;

  /// No description provided for @drawerHistoryHeader.
  ///
  /// In en, this message translates to:
  /// **'HISTORY'**
  String get drawerHistoryHeader;

  /// No description provided for @drawerSalesHistory.
  ///
  /// In en, this message translates to:
  /// **'Sales history'**
  String get drawerSalesHistory;

  /// No description provided for @drawerReceiveHistory.
  ///
  /// In en, this message translates to:
  /// **'Receive history'**
  String get drawerReceiveHistory;

  /// No description provided for @drawerExpenseHistory.
  ///
  /// In en, this message translates to:
  /// **'Expense history'**
  String get drawerExpenseHistory;

  /// No description provided for @expenseHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenseHistoryTitle;

  /// No description provided for @expenseHistoryLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load expenses. Pull down to try again.'**
  String get expenseHistoryLoadFailedMessage;

  /// No description provided for @expenseHistoryEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No expenses yet.'**
  String get expenseHistoryEmptyMessage;

  /// No description provided for @drawerPaymentHistory.
  ///
  /// In en, this message translates to:
  /// **'Payment history'**
  String get drawerPaymentHistory;

  /// No description provided for @paymentHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get paymentHistoryTitle;

  /// No description provided for @paymentHistoryLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load payments. Pull down to try again.'**
  String get paymentHistoryLoadFailedMessage;

  /// No description provided for @paymentHistoryEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No payments yet.'**
  String get paymentHistoryEmptyMessage;

  /// No description provided for @paymentHistoryNoParty.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get paymentHistoryNoParty;

  /// No description provided for @paymentHistoryRefundBadge.
  ///
  /// In en, this message translates to:
  /// **'refund'**
  String get paymentHistoryRefundBadge;

  /// No description provided for @paymentDirectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get paymentDirectionLabel;

  /// No description provided for @paymentDirectionAny.
  ///
  /// In en, this message translates to:
  /// **'Any direction'**
  String get paymentDirectionAny;

  /// No description provided for @paymentDirectionInbound.
  ///
  /// In en, this message translates to:
  /// **'Customer paid you'**
  String get paymentDirectionInbound;

  /// No description provided for @paymentDirectionOutbound.
  ///
  /// In en, this message translates to:
  /// **'You paid supplier'**
  String get paymentDirectionOutbound;

  /// No description provided for @partiesLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load. Pull down to try again.'**
  String get partiesLoadFailedMessage;

  /// No description provided for @partiesEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No customers or suppliers yet.'**
  String get partiesEmptyMessage;

  /// No description provided for @partiesEmptyForQuery.
  ///
  /// In en, this message translates to:
  /// **'No matches for \"{query}\".'**
  String partiesEmptyForQuery(String query);

  /// No description provided for @partyNewOpeningReceivableLabel.
  ///
  /// In en, this message translates to:
  /// **'Opening balance (they owe you)'**
  String get partyNewOpeningReceivableLabel;

  /// No description provided for @partyNewOpeningPayableLabel.
  ///
  /// In en, this message translates to:
  /// **'Opening balance (you owe them)'**
  String get partyNewOpeningPayableLabel;

  /// No description provided for @partyNewOpeningBalanceHelper.
  ///
  /// In en, this message translates to:
  /// **'Optional — for old debts from before this app.'**
  String get partyNewOpeningBalanceHelper;

  /// No description provided for @partyDetailEditTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit name & phone'**
  String get partyDetailEditTooltip;

  /// No description provided for @drawerPeopleHeader.
  ///
  /// In en, this message translates to:
  /// **'PEOPLE'**
  String get drawerPeopleHeader;

  /// No description provided for @drawerCustomers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get drawerCustomers;

  /// No description provided for @drawerSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get drawerSuppliers;

  /// No description provided for @customersTitle.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get customersTitle;

  /// No description provided for @suppliersTitle.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get suppliersTitle;

  /// No description provided for @customersSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search customer'**
  String get customersSearchHint;

  /// No description provided for @suppliersSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search supplier'**
  String get suppliersSearchHint;

  /// No description provided for @customersAddButton.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get customersAddButton;

  /// No description provided for @suppliersAddButton.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get suppliersAddButton;

  /// No description provided for @customersHasBalanceChip.
  ///
  /// In en, this message translates to:
  /// **'Has receivable only'**
  String get customersHasBalanceChip;

  /// No description provided for @suppliersHasBalanceChip.
  ///
  /// In en, this message translates to:
  /// **'Has payable only'**
  String get suppliersHasBalanceChip;

  /// No description provided for @customersHeadlineLabel.
  ///
  /// In en, this message translates to:
  /// **'Customers owe you'**
  String get customersHeadlineLabel;

  /// No description provided for @suppliersHeadlineLabel.
  ///
  /// In en, this message translates to:
  /// **'You owe suppliers'**
  String get suppliersHeadlineLabel;

  /// No description provided for @customersHeadlineCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No customers with balance} =1{1 customer with balance} other{{count} customers with balance}}'**
  String customersHeadlineCount(int count);

  /// No description provided for @suppliersHeadlineCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No suppliers with balance} =1{1 supplier with balance} other{{count} suppliers with balance}}'**
  String suppliersHeadlineCount(int count);

  /// No description provided for @peopleSortLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get peopleSortLabel;

  /// No description provided for @peopleSortByReceivable.
  ///
  /// In en, this message translates to:
  /// **'By debt (most first)'**
  String get peopleSortByReceivable;

  /// No description provided for @peopleSortByPayable.
  ///
  /// In en, this message translates to:
  /// **'By debt (most first)'**
  String get peopleSortByPayable;

  /// No description provided for @peopleSortByName.
  ///
  /// In en, this message translates to:
  /// **'Alphabetical'**
  String get peopleSortByName;

  /// No description provided for @stockAdjustTitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust {name} stock'**
  String stockAdjustTitle(String name);

  /// No description provided for @stockAdjustCurrentLabel.
  ///
  /// In en, this message translates to:
  /// **'Current: {amount} {unit}'**
  String stockAdjustCurrentLabel(String amount, String unit);

  /// No description provided for @stockAdjustCurrentValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Current: {value}'**
  String stockAdjustCurrentValueLabel(String value);

  /// No description provided for @stockAdjustModeOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening'**
  String get stockAdjustModeOpening;

  /// No description provided for @stockAdjustModeAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get stockAdjustModeAdd;

  /// No description provided for @stockAdjustModeSubtract.
  ///
  /// In en, this message translates to:
  /// **'Subtract'**
  String get stockAdjustModeSubtract;

  /// No description provided for @stockAdjustModeSetExact.
  ///
  /// In en, this message translates to:
  /// **'Set exact'**
  String get stockAdjustModeSetExact;

  /// No description provided for @stockAdjustModeOpeningHelper.
  ///
  /// In en, this message translates to:
  /// **'Stock you had on day one — before this app.'**
  String get stockAdjustModeOpeningHelper;

  /// No description provided for @stockAdjustModeAddHelper.
  ///
  /// In en, this message translates to:
  /// **'Stock received outside a bono (e.g. found behind the shelf).'**
  String get stockAdjustModeAddHelper;

  /// No description provided for @stockAdjustModeSubtractHelper.
  ///
  /// In en, this message translates to:
  /// **'Spoilage, waste, or any loss you can\'t refund.'**
  String get stockAdjustModeSubtractHelper;

  /// No description provided for @stockAdjustModeSetExactHelper.
  ///
  /// In en, this message translates to:
  /// **'Type the new total after a physical count.'**
  String get stockAdjustModeSetExactHelper;

  /// No description provided for @stockAdjustAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount ({unit})'**
  String stockAdjustAmountLabel(String unit);

  /// No description provided for @stockAdjustUnitCostLabel.
  ///
  /// In en, this message translates to:
  /// **'Cost per {unit} ({currency})'**
  String stockAdjustUnitCostLabel(String unit, String currency);

  /// No description provided for @stockAdjustUnitCostRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter the cost per unit so average cost stays correct.'**
  String get stockAdjustUnitCostRequiredMessage;

  /// No description provided for @stockAdjustNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get stockAdjustNotesLabel;

  /// No description provided for @stockAdjustPreview.
  ///
  /// In en, this message translates to:
  /// **'New stock: {amount} {unit}'**
  String stockAdjustPreview(String amount, String unit);

  /// No description provided for @stockAdjustSaveButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get stockAdjustSaveButton;

  /// No description provided for @stockAdjustFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not save the adjustment. Try again.'**
  String get stockAdjustFailedMessage;

  /// No description provided for @stockAdjustInvalidAmountMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount.'**
  String get stockAdjustInvalidAmountMessage;

  /// No description provided for @barcodeAddDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add barcode'**
  String get barcodeAddDialogTitle;

  /// No description provided for @barcodeAddDialogHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 6291100123456'**
  String get barcodeAddDialogHint;

  /// No description provided for @barcodeAddDialogSetPrimary.
  ///
  /// In en, this message translates to:
  /// **'Make primary'**
  String get barcodeAddDialogSetPrimary;

  /// No description provided for @barcodeChipMakePrimary.
  ///
  /// In en, this message translates to:
  /// **'Make primary'**
  String get barcodeChipMakePrimary;

  /// No description provided for @barcodeChipRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get barcodeChipRemove;

  /// No description provided for @barcodeAddTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add barcode'**
  String get barcodeAddTooltip;

  /// No description provided for @aliasAddDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add another name'**
  String get aliasAddDialogTitle;

  /// No description provided for @aliasAddDialogHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Riis (Somali)'**
  String get aliasAddDialogHint;

  /// No description provided for @aliasAddDialogLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get aliasAddDialogLanguage;

  /// No description provided for @aliasAddTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add other name'**
  String get aliasAddTooltip;

  /// No description provided for @languageNone.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get languageNone;

  /// No description provided for @productsHeadline.
  ///
  /// In en, this message translates to:
  /// **'{total, plural, =0{No products yet} =1{1 product} other{{total} products}} · {low} low · {noPrice} without price'**
  String productsHeadline(int total, int low, int noPrice);

  /// No description provided for @productsSortLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get productsSortLabel;

  /// No description provided for @productsSortByName.
  ///
  /// In en, this message translates to:
  /// **'Name (A–Z)'**
  String get productsSortByName;

  /// No description provided for @productsSortByStockLow.
  ///
  /// In en, this message translates to:
  /// **'Stock (low first)'**
  String get productsSortByStockLow;

  /// No description provided for @drawerProductsHeader.
  ///
  /// In en, this message translates to:
  /// **'PRODUCTS'**
  String get drawerProductsHeader;

  /// No description provided for @drawerTopMovers.
  ///
  /// In en, this message translates to:
  /// **'Top movers'**
  String get drawerTopMovers;

  /// No description provided for @topMoversTitle.
  ///
  /// In en, this message translates to:
  /// **'Top movers'**
  String get topMoversTitle;

  /// No description provided for @topMoversPeriodSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Last {days} days'**
  String topMoversPeriodSubtitle(int days);

  /// No description provided for @topMoversPeriodTooltip.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get topMoversPeriodTooltip;

  /// No description provided for @topMoversPeriodOption.
  ///
  /// In en, this message translates to:
  /// **'Last {days} days'**
  String topMoversPeriodOption(int days);

  /// No description provided for @topMoversTopSegment.
  ///
  /// In en, this message translates to:
  /// **'Top sellers'**
  String get topMoversTopSegment;

  /// No description provided for @topMoversDeadSegment.
  ///
  /// In en, this message translates to:
  /// **'Dead stock (no sales)'**
  String get topMoversDeadSegment;

  /// No description provided for @topMoversEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No sales in this period.'**
  String get topMoversEmptyMessage;

  /// No description provided for @drawerLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get drawerLowStock;

  /// No description provided for @drawerSetupHeader.
  ///
  /// In en, this message translates to:
  /// **'SETUP'**
  String get drawerSetupHeader;

  /// No description provided for @drawerProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get drawerProducts;

  /// No description provided for @drawerSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get drawerSettings;

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

  /// No description provided for @bonoTotal.
  ///
  /// In en, this message translates to:
  /// **'Bono total'**
  String get bonoTotal;

  /// No description provided for @credit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get credit;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'CLEAR'**
  String get clear;

  /// No description provided for @paymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get paymentTitle;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

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

  /// No description provided for @rent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get rent;

  /// No description provided for @salary.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get salary;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @supabaseConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect DukanPro to Supabase'**
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

  /// No description provided for @loginTabPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get loginTabPhone;

  /// No description provided for @loginTabEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get loginTabEmail;

  /// No description provided for @loginHeadline.
  ///
  /// In en, this message translates to:
  /// **'Use your phone number'**
  String get loginHeadline;

  /// No description provided for @loginBody.
  ///
  /// In en, this message translates to:
  /// **'We will send a one-time code. DukanPro can deliver it by WhatsApp from the backend.'**
  String get loginBody;

  /// No description provided for @loginEmailHeadline.
  ///
  /// In en, this message translates to:
  /// **'Use your email'**
  String get loginEmailHeadline;

  /// No description provided for @loginEmailBody.
  ///
  /// In en, this message translates to:
  /// **'We will email you a one-time code.'**
  String get loginEmailBody;

  /// No description provided for @phoneNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumberLabel;

  /// No description provided for @emailAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailAddressLabel;

  /// No description provided for @sendOtpButton.
  ///
  /// In en, this message translates to:
  /// **'SEND CODE'**
  String get sendOtpButton;

  /// No description provided for @sendEmailOtpButton.
  ///
  /// In en, this message translates to:
  /// **'SEND CODE'**
  String get sendEmailOtpButton;

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

  /// No description provided for @verifyOtpHeadlineEmail.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get verifyOtpHeadlineEmail;

  /// No description provided for @verifyOtpBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the code sent to {phone}.'**
  String verifyOtpBody(String phone);

  /// No description provided for @verifyOtpBodyEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter the code sent to {email}.'**
  String verifyOtpBodyEmail(String email);

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

  /// No description provided for @changeEmailButton.
  ///
  /// In en, this message translates to:
  /// **'Change email'**
  String get changeEmailButton;

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

  /// No description provided for @queueCapExceededToast.
  ///
  /// In en, this message translates to:
  /// **'Some old unsynced data was dropped — your phone was offline too long.'**
  String get queueCapExceededToast;

  /// No description provided for @signOutPendingDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsynced data'**
  String get signOutPendingDialogTitle;

  /// No description provided for @signOutPendingDialogBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You have 1 post that has not synced yet.} other{You have {count} posts that have not synced yet.}} Sign out anyway? They will sync the next time you sign in.'**
  String signOutPendingDialogBody(int count);

  /// No description provided for @signOutPendingDialogCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get signOutPendingDialogCancel;

  /// No description provided for @signOutPendingDialogConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOutPendingDialogConfirm;

  /// No description provided for @invalidPhoneMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number, for example +252612345678.'**
  String get invalidPhoneMessage;

  /// No description provided for @invalidEmailMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email, for example you@example.com.'**
  String get invalidEmailMessage;

  /// No description provided for @missingPendingPhoneMessage.
  ///
  /// In en, this message translates to:
  /// **'Start with your phone number first.'**
  String get missingPendingPhoneMessage;

  /// No description provided for @missingPendingDestinationMessage.
  ///
  /// In en, this message translates to:
  /// **'Start with your phone or email first.'**
  String get missingPendingDestinationMessage;

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

  /// No description provided for @sendEmailOtpFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'We could not email the code. Check the address or your internet and try again.'**
  String get sendEmailOtpFailedMessage;

  /// No description provided for @emailAccountNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'No account found for that email. Ask your shop owner to add you.'**
  String get emailAccountNotFoundMessage;

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

  /// No description provided for @settingsCurrencyLockedMessage.
  ///
  /// In en, this message translates to:
  /// **'Currency can\'t be changed once the shop has recorded a transaction. Contact support to change it.'**
  String get settingsCurrencyLockedMessage;

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

  /// No description provided for @productsNewItemButton.
  ///
  /// In en, this message translates to:
  /// **'NEW ITEM'**
  String get productsNewItemButton;

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

  /// No description provided for @partyNewCustomerTitle.
  ///
  /// In en, this message translates to:
  /// **'New customer'**
  String get partyNewCustomerTitle;

  /// No description provided for @partyNewSupplierTitle.
  ///
  /// In en, this message translates to:
  /// **'New supplier'**
  String get partyNewSupplierTitle;

  /// No description provided for @partyNewNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get partyNewNameLabel;

  /// No description provided for @partyNewPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get partyNewPhoneLabel;

  /// No description provided for @partyNewSaveButton.
  ///
  /// In en, this message translates to:
  /// **'ADD'**
  String get partyNewSaveButton;

  /// No description provided for @partyNewNameRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get partyNewNameRequiredMessage;

  /// No description provided for @partyNewSaveFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not add. Check your internet and try again.'**
  String get partyNewSaveFailedMessage;

  /// No description provided for @paymentTypeCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get paymentTypeCustomer;

  /// No description provided for @paymentTypeSupplier.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get paymentTypeSupplier;

  /// No description provided for @paymentTypeCustomerHint.
  ///
  /// In en, this message translates to:
  /// **'Customer is paying you back'**
  String get paymentTypeCustomerHint;

  /// No description provided for @paymentTypeSupplierHint.
  ///
  /// In en, this message translates to:
  /// **'You are paying the supplier'**
  String get paymentTypeSupplierHint;

  /// No description provided for @paymentPickCustomerButton.
  ///
  /// In en, this message translates to:
  /// **'Pick customer'**
  String get paymentPickCustomerButton;

  /// No description provided for @paymentPickSupplierButton.
  ///
  /// In en, this message translates to:
  /// **'Pick supplier'**
  String get paymentPickSupplierButton;

  /// No description provided for @paymentCustomerOwesLabel.
  ///
  /// In en, this message translates to:
  /// **'Owes you {amount}'**
  String paymentCustomerOwesLabel(Object amount);

  /// No description provided for @paymentSupplierOwedLabel.
  ///
  /// In en, this message translates to:
  /// **'You owe {amount}'**
  String paymentSupplierOwedLabel(Object amount);

  /// No description provided for @paymentAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount paid'**
  String get paymentAmountLabel;

  /// No description provided for @paymentSaveButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get paymentSaveButton;

  /// No description provided for @paymentNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get paymentNotesLabel;

  /// No description provided for @paymentSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Payment saved'**
  String get paymentSavedToast;

  /// No description provided for @paymentNeedPartyMessage.
  ///
  /// In en, this message translates to:
  /// **'Pick a {type, select, supplier{supplier} other{customer}} first.'**
  String paymentNeedPartyMessage(String type);

  /// No description provided for @paymentNeedAmountMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount greater than zero.'**
  String get paymentNeedAmountMessage;

  /// No description provided for @paymentExceedsBalanceMessage.
  ///
  /// In en, this message translates to:
  /// **'Amount cannot exceed the outstanding balance ({amount}).'**
  String paymentExceedsBalanceMessage(Object amount);

  /// No description provided for @paymentPostFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not save the payment. Check your internet and try again.'**
  String get paymentPostFailedMessage;

  /// No description provided for @paymentChooseInvoicesChip.
  ///
  /// In en, this message translates to:
  /// **'Choose invoices'**
  String get paymentChooseInvoicesChip;

  /// No description provided for @paymentChooseInvoicesChipDone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 invoice chosen} other{{count} invoices chosen}}'**
  String paymentChooseInvoicesChipDone(int count);

  /// No description provided for @allocationHeader.
  ///
  /// In en, this message translates to:
  /// **'{party} · choose invoices'**
  String allocationHeader(String party);

  /// No description provided for @allocationToAllocate.
  ///
  /// In en, this message translates to:
  /// **'{amount} to allocate'**
  String allocationToAllocate(String amount);

  /// No description provided for @allocationRowOpen.
  ///
  /// In en, this message translates to:
  /// **'Open {open} of {original}'**
  String allocationRowOpen(String open, String original);

  /// No description provided for @allocationStillToAllocate.
  ///
  /// In en, this message translates to:
  /// **'Still to allocate: {amount}'**
  String allocationStillToAllocate(String amount);

  /// No description provided for @allocationOverAllocated.
  ///
  /// In en, this message translates to:
  /// **'Over by {amount}'**
  String allocationOverAllocated(String amount);

  /// No description provided for @allocationBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get allocationBalanced;

  /// No description provided for @allocationApplyButton.
  ///
  /// In en, this message translates to:
  /// **'APPLY'**
  String get allocationApplyButton;

  /// No description provided for @allocationNeedAtLeastOne.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one invoice to apply.'**
  String get allocationNeedAtLeastOne;

  /// No description provided for @allocationLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load open invoices.'**
  String get allocationLoadFailed;

  /// No description provided for @allocationNoOpenInvoices.
  ///
  /// In en, this message translates to:
  /// **'No open invoices for this person.'**
  String get allocationNoOpenInvoices;

  /// No description provided for @partyDetailOpenInvoicesHeader.
  ///
  /// In en, this message translates to:
  /// **'Open invoices'**
  String get partyDetailOpenInvoicesHeader;

  /// No description provided for @partyDetailOpenInvoiceRow.
  ///
  /// In en, this message translates to:
  /// **'{open} open of {original}'**
  String partyDetailOpenInvoiceRow(String open, String original);

  /// No description provided for @expenseCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get expenseCategoryLabel;

  /// No description provided for @expenseAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get expenseAmountLabel;

  /// No description provided for @expenseSaveButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get expenseSaveButton;

  /// No description provided for @expenseNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get expenseNotesLabel;

  /// No description provided for @expenseSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Expense saved'**
  String get expenseSavedToast;

  /// No description provided for @expenseNeedCategoryMessage.
  ///
  /// In en, this message translates to:
  /// **'Pick a category first.'**
  String get expenseNeedCategoryMessage;

  /// No description provided for @expenseNeedAmountMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount greater than zero.'**
  String get expenseNeedAmountMessage;

  /// No description provided for @expenseLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load categories. Check your internet and try again.'**
  String get expenseLoadFailedMessage;

  /// No description provided for @expensePostFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not save the expense. Check your internet and try again.'**
  String get expensePostFailedMessage;

  /// No description provided for @expenseEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No expense categories yet. Pick a shop type in Settings.'**
  String get expenseEmptyMessage;

  /// No description provided for @saleHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get saleHistoryTitle;

  /// No description provided for @historyYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get historyYesterday;

  /// No description provided for @historyToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get historyToday;

  /// No description provided for @saleHistoryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sales history'**
  String get saleHistoryTooltip;

  /// No description provided for @saleHistoryEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No sales yet. The first SAVE on the Sale screen will land here.'**
  String get saleHistoryEmptyMessage;

  /// No description provided for @saleHistoryLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load sales. Check your internet and try again.'**
  String get saleHistoryLoadFailedMessage;

  /// No description provided for @saleHistoryCashLabel.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get saleHistoryCashLabel;

  /// No description provided for @saleHistoryDebtLabel.
  ///
  /// In en, this message translates to:
  /// **'Debt · {name}'**
  String saleHistoryDebtLabel(Object name);

  /// No description provided for @saleHistoryVoidedBadge.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get saleHistoryVoidedBadge;

  /// No description provided for @saleDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get saleDetailTitle;

  /// No description provided for @saleDetailVoidedHeader.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get saleDetailVoidedHeader;

  /// No description provided for @saleDetailVoidButton.
  ///
  /// In en, this message translates to:
  /// **'VOID THIS SALE'**
  String get saleDetailVoidButton;

  /// No description provided for @expenseDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get expenseDetailTitle;

  /// No description provided for @expenseDetailVoidButton.
  ///
  /// In en, this message translates to:
  /// **'VOID THIS EXPENSE'**
  String get expenseDetailVoidButton;

  /// No description provided for @expenseDetailLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this expense.'**
  String get expenseDetailLoadFailedMessage;

  /// No description provided for @expenseVoidConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Void this expense?'**
  String get expenseVoidConfirmTitle;

  /// No description provided for @expenseVoidConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This reverses the expense. It can\'t be undone.'**
  String get expenseVoidConfirmBody;

  /// No description provided for @expenseVoidConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'VOID'**
  String get expenseVoidConfirmYes;

  /// No description provided for @expenseVoidedToast.
  ///
  /// In en, this message translates to:
  /// **'Expense voided'**
  String get expenseVoidedToast;

  /// No description provided for @expenseVoidFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t void this expense.'**
  String get expenseVoidFailedMessage;

  /// No description provided for @paymentDetailVoidButton.
  ///
  /// In en, this message translates to:
  /// **'VOID THIS PAYMENT'**
  String get paymentDetailVoidButton;

  /// No description provided for @paymentVoidConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Void this payment?'**
  String get paymentVoidConfirmTitle;

  /// No description provided for @paymentVoidConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This reverses the payment and reopens what it settled. It can\'t be undone.'**
  String get paymentVoidConfirmBody;

  /// No description provided for @paymentVoidConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'VOID'**
  String get paymentVoidConfirmYes;

  /// No description provided for @paymentVoidedToast.
  ///
  /// In en, this message translates to:
  /// **'Payment voided'**
  String get paymentVoidedToast;

  /// No description provided for @paymentVoidedHeader.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get paymentVoidedHeader;

  /// No description provided for @paymentVoidFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t void this payment.'**
  String get paymentVoidFailedMessage;

  /// No description provided for @paymentVoidWindowPassedHint.
  ///
  /// In en, this message translates to:
  /// **'Void window passed'**
  String get paymentVoidWindowPassedHint;

  /// No description provided for @voidNotSyncedHint.
  ///
  /// In en, this message translates to:
  /// **'Not saved online yet — you can undo it once your phone is back online.'**
  String get voidNotSyncedHint;

  /// No description provided for @saleDetailLineSubtotal.
  ///
  /// In en, this message translates to:
  /// **'{quantity} {unit} × {unitPrice} = {subtotal}'**
  String saleDetailLineSubtotal(
    Object quantity,
    Object subtotal,
    Object unit,
    Object unitPrice,
  );

  /// No description provided for @saleDetailTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get saleDetailTotalLabel;

  /// No description provided for @saleDetailCashLabel.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get saleDetailCashLabel;

  /// No description provided for @saleDetailDebtLabel.
  ///
  /// In en, this message translates to:
  /// **'Debt'**
  String get saleDetailDebtLabel;

  /// No description provided for @receiptNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get receiptNumberLabel;

  /// No description provided for @receiptDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get receiptDateLabel;

  /// No description provided for @receiptThankYou.
  ///
  /// In en, this message translates to:
  /// **'Thank you!'**
  String get receiptThankYou;

  /// No description provided for @saleDetailLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load this sale.'**
  String get saleDetailLoadFailedMessage;

  /// No description provided for @saleReceiptShareButton.
  ///
  /// In en, this message translates to:
  /// **'SHARE RECEIPT'**
  String get saleReceiptShareButton;

  /// No description provided for @saleReceiptDoneButton.
  ///
  /// In en, this message translates to:
  /// **'DONE'**
  String get saleReceiptDoneButton;

  /// No description provided for @saleHistoryReceiptTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open receipt'**
  String get saleHistoryReceiptTooltip;

  /// No description provided for @saleVoidConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Void this sale?'**
  String get saleVoidConfirmTitle;

  /// No description provided for @saleVoidConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This will reverse the sale, restore the stock, and clear the customer\'s debt for it.'**
  String get saleVoidConfirmBody;

  /// No description provided for @saleVoidConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'VOID'**
  String get saleVoidConfirmYes;

  /// No description provided for @saleVoidConfirmNo.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get saleVoidConfirmNo;

  /// No description provided for @saleVoidRefundCheckboxLabel.
  ///
  /// In en, this message translates to:
  /// **'Refund cash to the customer'**
  String get saleVoidRefundCheckboxLabel;

  /// No description provided for @saleVoidRefundAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Refund amount'**
  String get saleVoidRefundAmountLabel;

  /// No description provided for @saleVoidRefundPaidHint.
  ///
  /// In en, this message translates to:
  /// **'paid: {amount}'**
  String saleVoidRefundPaidHint(Object amount);

  /// No description provided for @saleVoidRefundExceedsPaidMessage.
  ///
  /// In en, this message translates to:
  /// **'Refund cannot exceed the cash paid ({paid}).'**
  String saleVoidRefundExceedsPaidMessage(Object paid);

  /// No description provided for @saleVoidedToast.
  ///
  /// In en, this message translates to:
  /// **'Sale voided'**
  String get saleVoidedToast;

  /// No description provided for @saleVoidFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not void this sale. Try again.'**
  String get saleVoidFailedMessage;

  /// No description provided for @saleVoidErrorOwnerOnly.
  ///
  /// In en, this message translates to:
  /// **'Only the shop owner can void a sale.'**
  String get saleVoidErrorOwnerOnly;

  /// No description provided for @saleVoidErrorWindowExpired.
  ///
  /// In en, this message translates to:
  /// **'Too late to void — sales can only be voided within 7 days of posting.'**
  String get saleVoidErrorWindowExpired;

  /// No description provided for @saleVoidErrorAlreadyVoided.
  ///
  /// In en, this message translates to:
  /// **'This sale was already voided.'**
  String get saleVoidErrorAlreadyVoided;

  /// No description provided for @saleVoidErrorRefundNeedsCustomer.
  ///
  /// In en, this message translates to:
  /// **'Walk-in sales can\'t be refunded — there\'s no customer to refund to.'**
  String get saleVoidErrorRefundNeedsCustomer;

  /// No description provided for @saleVoidErrorRefundExceedsPaid.
  ///
  /// In en, this message translates to:
  /// **'Refund can\'t be more than the cash paid at the till.'**
  String get saleVoidErrorRefundExceedsPaid;

  /// No description provided for @saleVoidErrorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Sale not found. Pull to refresh and try again.'**
  String get saleVoidErrorNotFound;

  /// No description provided for @saleVoidErrorPartiallyPaid.
  ///
  /// In en, this message translates to:
  /// **'The customer has already paid part of this debt. Undo that payment first (in Money In), then void the sale.'**
  String get saleVoidErrorPartiallyPaid;

  /// No description provided for @receiveHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Receives'**
  String get receiveHistoryTitle;

  /// No description provided for @receiveHistoryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Receive history'**
  String get receiveHistoryTooltip;

  /// No description provided for @receiveHistoryEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No receives yet. The first SAVE on the Receive screen will land here.'**
  String get receiveHistoryEmptyMessage;

  /// No description provided for @receiveHistoryLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load receives. Check your internet and try again.'**
  String get receiveHistoryLoadFailedMessage;

  /// No description provided for @receiveHistorySupplierLabel.
  ///
  /// In en, this message translates to:
  /// **'Supplier · {name}'**
  String receiveHistorySupplierLabel(Object name);

  /// No description provided for @receiveHistoryVoidedBadge.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get receiveHistoryVoidedBadge;

  /// No description provided for @receiveDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get receiveDetailTitle;

  /// No description provided for @receiveDetailVoidedHeader.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get receiveDetailVoidedHeader;

  /// No description provided for @receiveDetailVoidButton.
  ///
  /// In en, this message translates to:
  /// **'VOID THIS RECEIVE'**
  String get receiveDetailVoidButton;

  /// No description provided for @receiveDetailLineSubtotal.
  ///
  /// In en, this message translates to:
  /// **'{quantity} {unit} × {unitCost} = {subtotal}'**
  String receiveDetailLineSubtotal(
    Object quantity,
    Object subtotal,
    Object unit,
    Object unitCost,
  );

  /// No description provided for @receiveDetailTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get receiveDetailTotalLabel;

  /// No description provided for @receiveDetailLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load this receive.'**
  String get receiveDetailLoadFailedMessage;

  /// No description provided for @receiveVoidConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Void this receive?'**
  String get receiveVoidConfirmTitle;

  /// No description provided for @receiveVoidConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Use this only when you typed the receive wrong. It reverses the receive, removes the stock, and clears what you owe the supplier for it.'**
  String get receiveVoidConfirmBody;

  /// No description provided for @receiveVoidMistakesOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Mistakes only. For real returns to the supplier, record a Payment instead.'**
  String get receiveVoidMistakesOnlyHint;

  /// No description provided for @receiveVoidConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'VOID'**
  String get receiveVoidConfirmYes;

  /// No description provided for @receiveVoidConfirmNo.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get receiveVoidConfirmNo;

  /// No description provided for @receiveVoidedToast.
  ///
  /// In en, this message translates to:
  /// **'Receive voided'**
  String get receiveVoidedToast;

  /// No description provided for @receiveVoidFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not void this receive. Check your internet and try again.'**
  String get receiveVoidFailedMessage;

  /// No description provided for @receiveVoidBlockedStockMessage.
  ///
  /// In en, this message translates to:
  /// **'Can\'t void: these items have a newer sale or receive. Undo the newest one first.'**
  String get receiveVoidBlockedStockMessage;

  /// No description provided for @receiveVoidBlockedPaidMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'ve already paid part of this bono. Undo that payment first (in Money Out), then void it.'**
  String get receiveVoidBlockedPaidMessage;

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

  /// No description provided for @cartClearAllButton.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get cartClearAllButton;

  /// No description provided for @drawerExpandTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show all lines'**
  String get drawerExpandTooltip;

  /// No description provided for @drawerShrinkTooltip.
  ///
  /// In en, this message translates to:
  /// **'Shrink'**
  String get drawerShrinkTooltip;

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

  /// No description provided for @lineEditorDoneButton.
  ///
  /// In en, this message translates to:
  /// **'DONE'**
  String get lineEditorDoneButton;

  /// No description provided for @lineEditorPriceRequiredHelper.
  ///
  /// In en, this message translates to:
  /// **'Set a price for this item'**
  String get lineEditorPriceRequiredHelper;

  /// No description provided for @lineEditorInvalidPriceMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter a number 0 or more'**
  String get lineEditorInvalidPriceMessage;

  /// No description provided for @lineEditorTilePriceMissing.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get lineEditorTilePriceMissing;

  /// No description provided for @supplierPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick supplier'**
  String get supplierPickerTitle;

  /// No description provided for @supplierPickerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search name or phone'**
  String get supplierPickerSearchHint;

  /// No description provided for @supplierPickerOwesLabel.
  ///
  /// In en, this message translates to:
  /// **'you owe {amount}'**
  String supplierPickerOwesLabel(Object amount);

  /// No description provided for @supplierPickerNoBonosLabel.
  ///
  /// In en, this message translates to:
  /// **'no receives yet'**
  String get supplierPickerNoBonosLabel;

  /// No description provided for @supplierPickerEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No suppliers yet. Add one when you record a receive.'**
  String get supplierPickerEmptyMessage;

  /// No description provided for @supplierPickerSearchEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No suppliers match “{query}”.'**
  String supplierPickerSearchEmptyMessage(Object query);

  /// No description provided for @supplierPickerLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load suppliers. Check your internet and try again.'**
  String get supplierPickerLoadFailedMessage;

  /// No description provided for @supplierNewButton.
  ///
  /// In en, this message translates to:
  /// **'+ NEW SUPPLIER'**
  String get supplierNewButton;

  /// No description provided for @receiveSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search Somali or English'**
  String get receiveSearchHint;

  /// No description provided for @receiveLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load items. Check your internet and try again.'**
  String get receiveLoadFailedMessage;

  /// No description provided for @receiveEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Tap an item to start the receive. Search if it\'s not in the grid.'**
  String get receiveEmptyMessage;

  /// No description provided for @receiveLineQuantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get receiveLineQuantityLabel;

  /// No description provided for @receiveLineTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'{currency} total'**
  String receiveLineTotalLabel(Object currency);

  /// No description provided for @receiveLineDerivedPerUnit.
  ///
  /// In en, this message translates to:
  /// **'= {money} per {packaging}'**
  String receiveLineDerivedPerUnit(String money, String packaging);

  /// No description provided for @receiveAddLineButton.
  ///
  /// In en, this message translates to:
  /// **'ADD LINE'**
  String get receiveAddLineButton;

  /// No description provided for @receiveLineSubtotal.
  ///
  /// In en, this message translates to:
  /// **'{quantity} {unit} = {total}'**
  String receiveLineSubtotal(Object quantity, Object total, Object unit);

  /// No description provided for @receiveLineRemoveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String receiveLineRemoveTooltip(Object name);

  /// No description provided for @receiveLinesSummary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No lines} =1{1 line} other{{count} lines}} · {total}'**
  String receiveLinesSummary(num count, Object total);

  /// No description provided for @receiveLinesClearAllButton.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get receiveLinesClearAllButton;

  /// No description provided for @receiveLinesClearConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear {count, plural, =1{1 line} other{{count} lines}}?'**
  String receiveLinesClearConfirmTitle(num count);

  /// No description provided for @receiveLinesClearConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This won\'t undo any saved receive.'**
  String get receiveLinesClearConfirmBody;

  /// No description provided for @receiveLinesClearConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'CLEAR'**
  String get receiveLinesClearConfirmYes;

  /// No description provided for @receiveLinesClearConfirmNo.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get receiveLinesClearConfirmNo;

  /// No description provided for @receiveSaveButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get receiveSaveButton;

  /// No description provided for @saleSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Sale saved'**
  String get saleSavedToast;

  /// No description provided for @receiveSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Receive saved (on credit)'**
  String get receiveSavedToast;

  /// No description provided for @receivePostFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not save the receive. Check your internet and try again.'**
  String get receivePostFailedMessage;

  /// No description provided for @receiveNeedSupplierMessage.
  ///
  /// In en, this message translates to:
  /// **'Pick a supplier before saving.'**
  String get receiveNeedSupplierMessage;

  /// No description provided for @receiveNeedLinesMessage.
  ///
  /// In en, this message translates to:
  /// **'Add at least one line before saving.'**
  String get receiveNeedLinesMessage;

  /// No description provided for @unitPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose unit'**
  String get unitPickerTitle;

  /// No description provided for @unitPickerDefaultBadge.
  ///
  /// In en, this message translates to:
  /// **'default'**
  String get unitPickerDefaultBadge;

  /// No description provided for @unitPickerBaseUnit.
  ///
  /// In en, this message translates to:
  /// **'base unit'**
  String get unitPickerBaseUnit;

  /// No description provided for @unitPickerLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load units. Try again.'**
  String get unitPickerLoadFailedMessage;

  /// No description provided for @unitPickerAddPackagingButton.
  ///
  /// In en, this message translates to:
  /// **'+ Add packaging'**
  String get unitPickerAddPackagingButton;

  /// No description provided for @addNewItemSearchResult.
  ///
  /// In en, this message translates to:
  /// **'+ Add new item: “{query}”'**
  String addNewItemSearchResult(Object query);

  /// No description provided for @addNewItemSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Add new item'**
  String get addNewItemSheetTitle;

  /// No description provided for @addProductSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get addProductSheetTitle;

  /// No description provided for @addNewItemNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get addNewItemNameLabel;

  /// No description provided for @addNewItemUnitChooseHint.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get addNewItemUnitChooseHint;

  /// No description provided for @addNewItemCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category (optional)'**
  String get addNewItemCategoryLabel;

  /// No description provided for @addNewItemCancelButton.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get addNewItemCancelButton;

  /// No description provided for @addNewItemSaveButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get addNewItemSaveButton;

  /// No description provided for @addNewItemSaveAndAddAnotherButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE & ADD ANOTHER'**
  String get addNewItemSaveAndAddAnotherButton;

  /// No description provided for @addNewItemSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Saved {name}'**
  String addNewItemSavedToast(String name);

  /// No description provided for @addNewItemAddToSaleButton.
  ///
  /// In en, this message translates to:
  /// **'ADD TO SALE'**
  String get addNewItemAddToSaleButton;

  /// No description provided for @addNewItemAddToReceiveButton.
  ///
  /// In en, this message translates to:
  /// **'ADD TO RECEIVE'**
  String get addNewItemAddToReceiveButton;

  /// No description provided for @addNewItemMissingNameMessage.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get addNewItemMissingNameMessage;

  /// No description provided for @addNewItemMissingUnitMessage.
  ///
  /// In en, this message translates to:
  /// **'Pick a unit'**
  String get addNewItemMissingUnitMessage;

  /// No description provided for @addNewItemInvalidPriceMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter a price (0 or more)'**
  String get addNewItemInvalidPriceMessage;

  /// No description provided for @addNewItemFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not create the item. Try again.'**
  String get addNewItemFailedMessage;

  /// No description provided for @addNewItemHowSoldHeader.
  ///
  /// In en, this message translates to:
  /// **'How is it sold?'**
  String get addNewItemHowSoldHeader;

  /// No description provided for @addNewItemHowDeliveredHeader.
  ///
  /// In en, this message translates to:
  /// **'How did the supplier deliver?'**
  String get addNewItemHowDeliveredHeader;

  /// No description provided for @addNewItemBaseOnlyTile.
  ///
  /// In en, this message translates to:
  /// **'By {base}'**
  String addNewItemBaseOnlyTile(String base);

  /// No description provided for @addNewItemPickedPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Sale price per {packaging}'**
  String addNewItemPickedPriceLabel(String packaging);

  /// No description provided for @addNewItemCustomPackagingEntry.
  ///
  /// In en, this message translates to:
  /// **'+ Custom packaging'**
  String get addNewItemCustomPackagingEntry;

  /// No description provided for @addNewItemCustomBaseUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'Base unit'**
  String get addNewItemCustomBaseUnitLabel;

  /// No description provided for @addNewItemCustomSoldUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'Sold as'**
  String get addNewItemCustomSoldUnitLabel;

  /// No description provided for @addNewItemCustomSoldByLabel.
  ///
  /// In en, this message translates to:
  /// **'Sold by'**
  String get addNewItemCustomSoldByLabel;

  /// No description provided for @addNewItemCustomInnerUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'A pack of smaller units? (optional)'**
  String get addNewItemCustomInnerUnitLabel;

  /// No description provided for @addNewItemCustomInnerNone.
  ///
  /// In en, this message translates to:
  /// **'No — just the {unit}'**
  String addNewItemCustomInnerNone(String unit);

  /// No description provided for @addNewItemCustomConversionLabel.
  ///
  /// In en, this message translates to:
  /// **'How many {base} in 1 {sold}?'**
  String addNewItemCustomConversionLabel(String base, String sold);

  /// No description provided for @addNewItemMissingPackagingMessage.
  ///
  /// In en, this message translates to:
  /// **'Pick how it is sold'**
  String get addNewItemMissingPackagingMessage;

  /// No description provided for @addNewItemLoadOptionsFailedHint.
  ///
  /// In en, this message translates to:
  /// **'Could not load suggestions. Pick custom packaging.'**
  String get addNewItemLoadOptionsFailedHint;

  /// No description provided for @addNewItemUseCustomButton.
  ///
  /// In en, this message translates to:
  /// **'USE THIS PACKAGING'**
  String get addNewItemUseCustomButton;

  /// No description provided for @addNewItemLooseType.
  ///
  /// In en, this message translates to:
  /// **'Loose'**
  String get addNewItemLooseType;

  /// No description provided for @addPackagingSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Add packaging'**
  String get addPackagingSheetTitle;

  /// No description provided for @addPackagingUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get addPackagingUnitLabel;

  /// No description provided for @addPackagingConversionLabel.
  ///
  /// In en, this message translates to:
  /// **'How many {base} in 1 {unit}?'**
  String addPackagingConversionLabel(Object base, Object unit);

  /// No description provided for @addPackagingPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Sale price per {unit} (optional)'**
  String addPackagingPriceLabel(Object unit);

  /// No description provided for @addPackagingSaveButton.
  ///
  /// In en, this message translates to:
  /// **'ADD PACKAGING'**
  String get addPackagingSaveButton;

  /// No description provided for @addPackagingFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not add the packaging. Try again.'**
  String get addPackagingFailedMessage;

  /// No description provided for @addPackagingHeaderBaseUnit.
  ///
  /// In en, this message translates to:
  /// **'Base unit · {unit}'**
  String addPackagingHeaderBaseUnit(Object unit);

  /// No description provided for @addPackagingSuggestionsHeader.
  ///
  /// In en, this message translates to:
  /// **'Common packagings'**
  String get addPackagingSuggestionsHeader;

  /// No description provided for @addPackagingCustomEntry.
  ///
  /// In en, this message translates to:
  /// **'Custom packaging'**
  String get addPackagingCustomEntry;

  /// No description provided for @addPackagingLessCommonHeader.
  ///
  /// In en, this message translates to:
  /// **'Less common'**
  String get addPackagingLessCommonHeader;

  /// No description provided for @packagingConversionPreview.
  ///
  /// In en, this message translates to:
  /// **'1 {unit} holds {qty} {base}'**
  String packagingConversionPreview(String unit, String qty, String base);

  /// No description provided for @addPackagingPickedPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Sale price per {packaging} (optional)'**
  String addPackagingPickedPriceLabel(Object packaging);

  /// No description provided for @addPackagingNoSuggestionsHint.
  ///
  /// In en, this message translates to:
  /// **'No common packagings yet for this base unit — define your own below.'**
  String get addPackagingNoSuggestionsHint;

  /// No description provided for @addPackagingLoadFailedHint.
  ///
  /// In en, this message translates to:
  /// **'Could not load suggestions. Define your own below.'**
  String get addPackagingLoadFailedHint;

  /// No description provided for @lineEditorCostHintLabel.
  ///
  /// In en, this message translates to:
  /// **'Your last cost: {cost}. Add your usual markup.'**
  String lineEditorCostHintLabel(String cost);

  /// No description provided for @shopItemEditorTitleCreate.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get shopItemEditorTitleCreate;

  /// No description provided for @shopItemDetailAliasesHeader.
  ///
  /// In en, this message translates to:
  /// **'Other names'**
  String get shopItemDetailAliasesHeader;

  /// No description provided for @shopItemEditorNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get shopItemEditorNameLabel;

  /// No description provided for @shopItemEditorBaseUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'Base unit'**
  String get shopItemEditorBaseUnitLabel;

  /// No description provided for @shopItemEditorCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get shopItemEditorCategoryLabel;

  /// No description provided for @shopItemEditorReorderThresholdLabel.
  ///
  /// In en, this message translates to:
  /// **'Warn when stock drops below'**
  String get shopItemEditorReorderThresholdLabel;

  /// No description provided for @shopItemEditorReorderThresholdHelper.
  ///
  /// In en, this message translates to:
  /// **'In {unit}. Leave blank for no warning.'**
  String shopItemEditorReorderThresholdHelper(String unit);

  /// No description provided for @shopItemEditorScanIdentifyButton.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get shopItemEditorScanIdentifyButton;

  /// No description provided for @shopItemEditorBarcodeNoMatchToast.
  ///
  /// In en, this message translates to:
  /// **'Code {code} isn\'t in our catalog yet. Fill in the rest and SAVE.'**
  String shopItemEditorBarcodeNoMatchToast(String code);

  /// No description provided for @shopItemEditorPrefillBanner.
  ///
  /// In en, this message translates to:
  /// **'Found \'{name}\' in the catalog — review and tweak anything that\'s different.'**
  String shopItemEditorPrefillBanner(String name);

  /// No description provided for @shopItemEditorSuggestionInShop.
  ///
  /// In en, this message translates to:
  /// **'Already in your shop — tap to open'**
  String get shopItemEditorSuggestionInShop;

  /// No description provided for @shopItemEditorSuggestionInCatalog.
  ///
  /// In en, this message translates to:
  /// **'From global catalog — tap to use'**
  String get shopItemEditorSuggestionInCatalog;

  /// No description provided for @shopItemEditorSessionCounter.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 added} other {# added}}'**
  String shopItemEditorSessionCounter(int count);

  /// No description provided for @shopItemEditorSessionSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Added this session'**
  String get shopItemEditorSessionSheetTitle;

  /// No description provided for @shopItemEditorSessionSheetViewAll.
  ///
  /// In en, this message translates to:
  /// **'View all products →'**
  String get shopItemEditorSessionSheetViewAll;

  /// No description provided for @shopItemEditorIdentifyHeader.
  ///
  /// In en, this message translates to:
  /// **'Identify'**
  String get shopItemEditorIdentifyHeader;

  /// No description provided for @shopItemEditorPackagingHeader.
  ///
  /// In en, this message translates to:
  /// **'Packaging'**
  String get shopItemEditorPackagingHeader;

  /// No description provided for @shopItemEditorSupplierHeader.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get shopItemEditorSupplierHeader;

  /// No description provided for @shopItemEditorPickSupplierButton.
  ///
  /// In en, this message translates to:
  /// **'Pick supplier'**
  String get shopItemEditorPickSupplierButton;

  /// No description provided for @shopItemEditorNewSupplierButton.
  ///
  /// In en, this message translates to:
  /// **'NEW'**
  String get shopItemEditorNewSupplierButton;

  /// No description provided for @shopItemEditorRemoveSupplierTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove supplier'**
  String get shopItemEditorRemoveSupplierTooltip;

  /// No description provided for @packagingEditorAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add packaging'**
  String get packagingEditorAddTitle;

  /// No description provided for @packagingEditorEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit packaging'**
  String get packagingEditorEditTitle;

  /// No description provided for @packagingEditorSaveButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get packagingEditorSaveButton;

  /// No description provided for @packagingEditorMissingUnitMessage.
  ///
  /// In en, this message translates to:
  /// **'Pick a packaging unit (e.g. bag, box).'**
  String get packagingEditorMissingUnitMessage;

  /// No description provided for @packagingEditorMissingConversionMessage.
  ///
  /// In en, this message translates to:
  /// **'How many base units fit in this pack? Enter a number greater than 0.'**
  String get packagingEditorMissingConversionMessage;

  /// No description provided for @packagingEditorCostLabel.
  ///
  /// In en, this message translates to:
  /// **'Cost per {unit}'**
  String packagingEditorCostLabel(String unit);

  /// No description provided for @packagingEditorStockLabel.
  ///
  /// In en, this message translates to:
  /// **'Stock — how many {unit}?'**
  String packagingEditorStockLabel(String unit);

  /// No description provided for @shopItemEditorBaseStockLabel.
  ///
  /// In en, this message translates to:
  /// **'Stock — loose {unit}'**
  String shopItemEditorBaseStockLabel(String unit);

  /// No description provided for @shopItemEditorBaseSaleLabel.
  ///
  /// In en, this message translates to:
  /// **'Sale price per {unit}'**
  String shopItemEditorBaseSaleLabel(String unit);

  /// No description provided for @shopItemEditorBaseCostLabel.
  ///
  /// In en, this message translates to:
  /// **'Cost per {unit}'**
  String shopItemEditorBaseCostLabel(String unit);

  /// No description provided for @shopItemEditorPackagingSummary.
  ///
  /// In en, this message translates to:
  /// **'Sell {sale} · Cost {cost} · {stock} in stock'**
  String shopItemEditorPackagingSummary(String sale, String cost, String stock);

  /// No description provided for @shopItemEditorPackagingSummaryEmpty.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get shopItemEditorPackagingSummaryEmpty;

  /// No description provided for @shopItemEditorEditPackagingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit packaging'**
  String get shopItemEditorEditPackagingTooltip;

  /// No description provided for @shopItemEditorRemovePackagingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove packaging'**
  String get shopItemEditorRemovePackagingTooltip;

  /// No description provided for @shopItemEditorBuyHeader.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get shopItemEditorBuyHeader;

  /// No description provided for @shopItemEditorBuySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Default supplier + typical cost — pre-fills Receive later.'**
  String get shopItemEditorBuySubtitle;

  /// No description provided for @shopItemEditorTypicalCostHeader.
  ///
  /// In en, this message translates to:
  /// **'Typical cost'**
  String get shopItemEditorTypicalCostHeader;

  /// No description provided for @shopItemEditorCostPerPackLabel.
  ///
  /// In en, this message translates to:
  /// **'Cost per {pack}'**
  String shopItemEditorCostPerPackLabel(String pack);

  /// No description provided for @shopItemEditorOpeningHeader.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get shopItemEditorOpeningHeader;

  /// No description provided for @shopItemEditorOpeningSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter current stock per packaging so reports are right from day one.'**
  String get shopItemEditorOpeningSubtitle;

  /// No description provided for @shopItemEditorOpeningPickBaseUnitFirst.
  ///
  /// In en, this message translates to:
  /// **'Pick a base unit above to enable this section.'**
  String get shopItemEditorOpeningPickBaseUnitFirst;

  /// No description provided for @shopItemEditorOpeningQtyLabel.
  ///
  /// In en, this message translates to:
  /// **'Quantity in {unit}'**
  String shopItemEditorOpeningQtyLabel(String unit);

  /// No description provided for @shopItemEditorOpeningAsOf.
  ///
  /// In en, this message translates to:
  /// **'As of {date}'**
  String shopItemEditorOpeningAsOf(String date);

  /// No description provided for @shopItemEditorChangeDateButton.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get shopItemEditorChangeDateButton;

  /// No description provided for @shopItemEditorOpeningStockNote.
  ///
  /// In en, this message translates to:
  /// **'Opening stock recorded during onboarding.'**
  String get shopItemEditorOpeningStockNote;

  /// No description provided for @shopItemEditorOpeningStockFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Item saved but stock did not save — open the product to adjust.'**
  String get shopItemEditorOpeningStockFailedMessage;

  /// No description provided for @shopItemEditorDedupTitle.
  ///
  /// In en, this message translates to:
  /// **'You may already have this'**
  String get shopItemEditorDedupTitle;

  /// No description provided for @shopItemEditorDedupBody.
  ///
  /// In en, this message translates to:
  /// **'Your shop has similar items. Open one to edit, or keep going if it\'s something different:'**
  String get shopItemEditorDedupBody;

  /// No description provided for @shopItemEditorDedupKeepGoing.
  ///
  /// In en, this message translates to:
  /// **'IT\'S DIFFERENT'**
  String get shopItemEditorDedupKeepGoing;

  /// No description provided for @shopItemEditorDedupOpenExisting.
  ///
  /// In en, this message translates to:
  /// **'OPEN EXISTING'**
  String get shopItemEditorDedupOpenExisting;

  /// No description provided for @shopItemEditorPackagingsHeader.
  ///
  /// In en, this message translates to:
  /// **'Packagings'**
  String get shopItemEditorPackagingsHeader;

  /// No description provided for @shopItemEditorAddPackagingButton.
  ///
  /// In en, this message translates to:
  /// **'Add packaging'**
  String get shopItemEditorAddPackagingButton;

  /// No description provided for @shopItemEditorBaseBadge.
  ///
  /// In en, this message translates to:
  /// **'BASE'**
  String get shopItemEditorBaseBadge;

  /// No description provided for @shopItemEditorPackagingMissingMessage.
  ///
  /// In en, this message translates to:
  /// **'Fill at least one packaging (price, cost, stock, or barcode).'**
  String get shopItemEditorPackagingMissingMessage;

  /// No description provided for @shopItemEditorScanBarcodeButton.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode (optional)'**
  String get shopItemEditorScanBarcodeButton;

  /// No description provided for @shopItemEditorRescanBarcodeButton.
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get shopItemEditorRescanBarcodeButton;

  /// No description provided for @shopItemEditorRemoveBarcodeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove barcode'**
  String get shopItemEditorRemoveBarcodeTooltip;

  /// No description provided for @shopItemEditorBarcodeBoundLabel.
  ///
  /// In en, this message translates to:
  /// **'Barcode {code}'**
  String shopItemEditorBarcodeBoundLabel(String code);

  /// No description provided for @shopItemEditorBarcodeCapturedToast.
  ///
  /// In en, this message translates to:
  /// **'Captured {code}'**
  String shopItemEditorBarcodeCapturedToast(String code);

  /// No description provided for @shopItemEditorDiscoveryHeader.
  ///
  /// In en, this message translates to:
  /// **'Aliases'**
  String get shopItemEditorDiscoveryHeader;

  /// No description provided for @shopItemEditorDiscoverySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Extra names + bono spelling improve search later.'**
  String get shopItemEditorDiscoverySubtitle;

  /// No description provided for @shopItemEditorAliasesLabel.
  ///
  /// In en, this message translates to:
  /// **'Other names'**
  String get shopItemEditorAliasesLabel;

  /// No description provided for @shopItemEditorAliasHint.
  ///
  /// In en, this message translates to:
  /// **'Add another name'**
  String get shopItemEditorAliasHint;

  /// No description provided for @shopItemEditorAddAliasButton.
  ///
  /// In en, this message translates to:
  /// **'ADD'**
  String get shopItemEditorAddAliasButton;

  /// No description provided for @shopItemEditorAliasHelper.
  ///
  /// In en, this message translates to:
  /// **'Names a customer might say. Tap a chip to remove it.'**
  String get shopItemEditorAliasHelper;

  /// No description provided for @shopItemEditorBonoSpellingLabel.
  ///
  /// In en, this message translates to:
  /// **'Bono spelling (optional)'**
  String get shopItemEditorBonoSpellingLabel;

  /// No description provided for @shopItemEditorBonoSpellingHelper.
  ///
  /// In en, this message translates to:
  /// **'How this item appears on supplier paper invoices (e.g. CCL 330x24).'**
  String get shopItemEditorBonoSpellingHelper;

  /// No description provided for @removePackagingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove packaging'**
  String get removePackagingTooltip;

  /// No description provided for @deactivateItemTooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide product'**
  String get deactivateItemTooltip;

  /// No description provided for @deactivateItemConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Hide this product?'**
  String get deactivateItemConfirmTitle;

  /// No description provided for @deactivateItemConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'It will be removed from Sale, Receive, and Products. Past sales keep it. You can ask support to bring it back.'**
  String get deactivateItemConfirmBody;

  /// No description provided for @deactivateItemConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'HIDE'**
  String get deactivateItemConfirmAction;

  /// No description provided for @removePackagingConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Remove this packaging? You can add it back later.'**
  String get removePackagingConfirmBody;

  /// No description provided for @removePackagingConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'REMOVE'**
  String get removePackagingConfirmAction;

  /// No description provided for @shopItemEditorSaveButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get shopItemEditorSaveButton;

  /// No description provided for @shopItemEditorSaveAndAddAnotherButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE & ADD ANOTHER'**
  String get shopItemEditorSaveAndAddAnotherButton;

  /// No description provided for @shopItemEditorSavedAndContinueToast.
  ///
  /// In en, this message translates to:
  /// **'{name} saved — add another'**
  String shopItemEditorSavedAndContinueToast(String name);

  /// No description provided for @shopItemDetailEditPrice.
  ///
  /// In en, this message translates to:
  /// **'Edit price'**
  String get shopItemDetailEditPrice;

  /// No description provided for @shopItemDetailDefaultSaleBadge.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get shopItemDetailDefaultSaleBadge;

  /// No description provided for @shopItemDetailDefaultReceiveBadge.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get shopItemDetailDefaultReceiveBadge;

  /// No description provided for @shopItemDetailDefaultForLabel.
  ///
  /// In en, this message translates to:
  /// **'Default for:'**
  String get shopItemDetailDefaultForLabel;

  /// No description provided for @shopItemDetailStockLabel.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get shopItemDetailStockLabel;

  /// No description provided for @shopItemDetailNoPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'no price yet'**
  String get shopItemDetailNoPriceLabel;

  /// No description provided for @shopItemDetailReorderBelowLabel.
  ///
  /// In en, this message translates to:
  /// **'Reorder below {amount} {unit}'**
  String shopItemDetailReorderBelowLabel(Object amount, Object unit);

  /// No description provided for @catalogPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Browse catalog'**
  String get catalogPickerTitle;

  /// No description provided for @catalogPickerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search global catalog'**
  String get catalogPickerSearchHint;

  /// No description provided for @catalogPickerActivatedBadge.
  ///
  /// In en, this message translates to:
  /// **'already added'**
  String get catalogPickerActivatedBadge;

  /// No description provided for @catalogPickerAddButton.
  ///
  /// In en, this message translates to:
  /// **'ADD {count, plural, =1{1 item} other{{count} items}}'**
  String catalogPickerAddButton(num count);

  /// No description provided for @catalogPickerAddedToast.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}} added'**
  String catalogPickerAddedToast(num count);

  /// No description provided for @setupOnboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your products'**
  String get setupOnboardingTitle;

  /// No description provided for @setupOnboardingBody.
  ///
  /// In en, this message translates to:
  /// **'We added {count} items from the {template} template. You can start selling now — prices fill in as you sell.\n\nOr take a minute to:'**
  String setupOnboardingBody(Object count, Object template);

  /// No description provided for @setupOnboardingAddItemsTitle.
  ///
  /// In en, this message translates to:
  /// **'Add my own items'**
  String get setupOnboardingAddItemsTitle;

  /// No description provided for @setupOnboardingAddItemsBody.
  ///
  /// In en, this message translates to:
  /// **'Items the template didn\'t include'**
  String get setupOnboardingAddItemsBody;

  /// No description provided for @setupOnboardingSetPricesTitle.
  ///
  /// In en, this message translates to:
  /// **'Set prices on top items'**
  String get setupOnboardingSetPricesTitle;

  /// No description provided for @setupOnboardingSetPricesBody.
  ///
  /// In en, this message translates to:
  /// **'So sales don\'t pause for a price prompt'**
  String get setupOnboardingSetPricesBody;

  /// No description provided for @setupOnboardingBrowseCatalogTitle.
  ///
  /// In en, this message translates to:
  /// **'Browse the catalog'**
  String get setupOnboardingBrowseCatalogTitle;

  /// No description provided for @setupOnboardingBrowseCatalogBody.
  ///
  /// In en, this message translates to:
  /// **'Activate more items from our list'**
  String get setupOnboardingBrowseCatalogBody;

  /// No description provided for @setupOnboardingSkipButton.
  ///
  /// In en, this message translates to:
  /// **'SKIP — START SELLING'**
  String get setupOnboardingSkipButton;

  /// No description provided for @scanCameraTooltip.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get scanCameraTooltip;

  /// No description provided for @scannerSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan a barcode'**
  String get scannerSheetTitle;

  /// No description provided for @scannerTorchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Torch'**
  String get scannerTorchTooltip;

  /// No description provided for @scannerHoldSteady.
  ///
  /// In en, this message translates to:
  /// **'Hold steady — 15 to 25 cm from the code'**
  String get scannerHoldSteady;

  /// No description provided for @scanUnknownPillLabel.
  ///
  /// In en, this message translates to:
  /// **'Unknown barcode: {code}'**
  String scanUnknownPillLabel(String code);

  /// No description provided for @scanUnknownCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create new'**
  String get scanUnknownCreateAction;

  /// No description provided for @scanUnknownDismissAction.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get scanUnknownDismissAction;

  /// No description provided for @scanLookupFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t look up that barcode'**
  String get scanLookupFailed;

  /// No description provided for @multiScanSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Multi-scan ({count})'**
  String multiScanSheetTitle(int count);

  /// No description provided for @multiScanUnknownCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unknown code — review after} other{{count} unknown codes — review after}}'**
  String multiScanUnknownCount(int count);

  /// No description provided for @multiScanEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Aim at a barcode. Successful scans stage as lines below.'**
  String get multiScanEmptyHint;

  /// No description provided for @multiScanDoneAction.
  ///
  /// In en, this message translates to:
  /// **'DONE'**
  String get multiScanDoneAction;

  /// No description provided for @multiScanLongPressHint.
  ///
  /// In en, this message translates to:
  /// **'Hold to multi-scan'**
  String get multiScanLongPressHint;

  /// No description provided for @multiScanAppliedSummary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 line staged} other{{count} lines staged}}'**
  String multiScanAppliedSummary(int count);

  /// No description provided for @barcodeScanAndBindAction.
  ///
  /// In en, this message translates to:
  /// **'Scan code'**
  String get barcodeScanAndBindAction;

  /// No description provided for @barcodeBoundToPackagingMessage.
  ///
  /// In en, this message translates to:
  /// **'Code linked to this packaging'**
  String get barcodeBoundToPackagingMessage;

  /// No description provided for @relativeTimeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get relativeTimeJustNow;

  /// No description provided for @relativeTimeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{1 min ago} other{{minutes} min ago}}'**
  String relativeTimeMinutesAgo(int minutes);

  /// No description provided for @relativeTimeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{1 hr ago} other{{hours} hr ago}}'**
  String relativeTimeHoursAgo(int hours);

  /// No description provided for @relativeTimeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day ago} other{{days} days ago}}'**
  String relativeTimeDaysAgo(int days);

  /// No description provided for @relativeTimeOn.
  ///
  /// In en, this message translates to:
  /// **'on {date}'**
  String relativeTimeOn(String date);

  /// No description provided for @saleHistoryVoidedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'voided {when}'**
  String saleHistoryVoidedSubtitle(String when);

  /// No description provided for @partyDetailEditedAt.
  ///
  /// In en, this message translates to:
  /// **'contact info edited {when}'**
  String partyDetailEditedAt(String when);

  /// No description provided for @offlineQueuePillLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Syncing 1} other{Syncing {count}}}'**
  String offlineQueuePillLabel(int count);

  /// No description provided for @storageSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Local Storage & Sync'**
  String get storageSyncTitle;

  /// No description provided for @storageSyncStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get storageSyncStatusConnected;

  /// No description provided for @storageSyncStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get storageSyncStatusOffline;

  /// No description provided for @storageSyncLastSyncedLabel.
  ///
  /// In en, this message translates to:
  /// **'Last synced'**
  String get storageSyncLastSyncedLabel;

  /// No description provided for @storageSyncLastSyncedNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get storageSyncLastSyncedNever;

  /// No description provided for @storageSyncPendingSalesLabel.
  ///
  /// In en, this message translates to:
  /// **'Pending posts'**
  String get storageSyncPendingSalesLabel;

  /// No description provided for @storageSyncPendingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{none waiting} =1{1 waiting} other{{count} waiting}}'**
  String storageSyncPendingCount(int count);

  /// No description provided for @storageSyncFailedPermanentlyLabel.
  ///
  /// In en, this message translates to:
  /// **'Failed permanently'**
  String get storageSyncFailedPermanentlyLabel;

  /// No description provided for @storageSyncFailedPermanentlyCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 post} other{{count} posts}}'**
  String storageSyncFailedPermanentlyCount(int count);

  /// No description provided for @storageSyncStorageUsedLabel.
  ///
  /// In en, this message translates to:
  /// **'Storage used'**
  String get storageSyncStorageUsedLabel;

  /// No description provided for @storageSyncStorageBreakdownPending.
  ///
  /// In en, this message translates to:
  /// **'Pending posts'**
  String get storageSyncStorageBreakdownPending;

  /// No description provided for @storageSyncStorageBreakdownCached.
  ///
  /// In en, this message translates to:
  /// **'Cached data'**
  String get storageSyncStorageBreakdownCached;

  /// No description provided for @storageSyncSyncNowButton.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get storageSyncSyncNowButton;

  /// No description provided for @storageSyncFreeUpSpaceButton.
  ///
  /// In en, this message translates to:
  /// **'Free up space'**
  String get storageSyncFreeUpSpaceButton;

  /// No description provided for @storageSyncFreeUpSpaceConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear cached data?'**
  String get storageSyncFreeUpSpaceConfirmTitle;

  /// No description provided for @storageSyncFreeUpSpaceConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This refreshes prices and lists from the server. Your saved sales aren\'t touched.'**
  String get storageSyncFreeUpSpaceConfirmBody;

  /// No description provided for @storageSyncFreeUpSpaceConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'CLEAR'**
  String get storageSyncFreeUpSpaceConfirmAction;

  /// No description provided for @storageSyncResyncAllButton.
  ///
  /// In en, this message translates to:
  /// **'Re-download all data'**
  String get storageSyncResyncAllButton;

  /// No description provided for @storageSyncResyncConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Re-download all data?'**
  String get storageSyncResyncConfirmTitle;

  /// No description provided for @storageSyncResyncConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Fetches a fresh copy of items, customers, and recent transactions from the server. Your saved sales aren\'t touched.'**
  String get storageSyncResyncConfirmBody;

  /// No description provided for @storageSyncResyncConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'RE-DOWNLOAD'**
  String get storageSyncResyncConfirmAction;

  /// No description provided for @storageSyncResyncDoneToast.
  ///
  /// In en, this message translates to:
  /// **'Re-downloaded all data'**
  String get storageSyncResyncDoneToast;

  /// No description provided for @storageSyncResyncFailedToast.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t re-download. Please try again.'**
  String get storageSyncResyncFailedToast;

  /// No description provided for @storageSyncOfflineMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Connect to the internet to sync.'**
  String get storageSyncOfflineMessage;

  /// No description provided for @storageSyncCacheClearedToast.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared'**
  String get storageSyncCacheClearedToast;

  /// No description provided for @storageSyncSyncedToast.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Already up to date} =1{Synced 1 post} other{Synced {count} posts}}'**
  String storageSyncSyncedToast(int count);

  /// No description provided for @storageSyncSyncFailedToast.
  ///
  /// In en, this message translates to:
  /// **'Could not sync — check your connection.'**
  String get storageSyncSyncFailedToast;

  /// No description provided for @storageSyncAlreadyUpToDateToast.
  ///
  /// In en, this message translates to:
  /// **'Already up to date'**
  String get storageSyncAlreadyUpToDateToast;

  /// No description provided for @storageSyncPushedToast.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Sent 1 pending} other{Sent {count} pending}}'**
  String storageSyncPushedToast(int count);

  /// No description provided for @storageSyncPulledToast.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Got 1 update} other{Got {count} updates}}'**
  String storageSyncPulledToast(int count);

  /// No description provided for @storageSyncPushedAndPulledToast.
  ///
  /// In en, this message translates to:
  /// **'Sent {pushed} pending, got {pulled} updates'**
  String storageSyncPushedAndPulledToast(int pushed, int pulled);

  /// No description provided for @storageSyncResetButton.
  ///
  /// In en, this message translates to:
  /// **'Reset local data'**
  String get storageSyncResetButton;

  /// No description provided for @storageSyncResetConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset local data?'**
  String get storageSyncResetConfirmTitle;

  /// No description provided for @storageSyncResetConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This DELETES all data this device has downloaded from the server. Your shop\'s data will be re-downloaded on next sync. Any sales that haven\'t been sent will be lost. Only do this if support tells you to.'**
  String get storageSyncResetConfirmBody;

  /// No description provided for @storageSyncResetTypePrompt.
  ///
  /// In en, this message translates to:
  /// **'Type RESET to confirm'**
  String get storageSyncResetTypePrompt;

  /// No description provided for @storageSyncResetTypeWord.
  ///
  /// In en, this message translates to:
  /// **'RESET'**
  String get storageSyncResetTypeWord;

  /// No description provided for @storageSyncResetOfflineBlocker.
  ///
  /// In en, this message translates to:
  /// **'Connect to internet first — you have pending sales that need to send before reset.'**
  String get storageSyncResetOfflineBlocker;

  /// No description provided for @storageSyncResetPendingFailedBlocker.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 post couldn\'t send. Review it in Failed posts before reset.} other{{count} posts couldn\'t send. Review them in Failed posts before reset.}}'**
  String storageSyncResetPendingFailedBlocker(int count);

  /// No description provided for @storageSyncResetConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'RESET'**
  String get storageSyncResetConfirmAction;

  /// No description provided for @storageSyncResetDoneToast.
  ///
  /// In en, this message translates to:
  /// **'Local data reset. Downloading fresh data...'**
  String get storageSyncResetDoneToast;

  /// No description provided for @storageSyncResetFailedToast.
  ///
  /// In en, this message translates to:
  /// **'Reset failed'**
  String get storageSyncResetFailedToast;

  /// No description provided for @storageSyncSettingsHeader.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get storageSyncSettingsHeader;

  /// No description provided for @storageSyncWifiOnlyLabel.
  ///
  /// In en, this message translates to:
  /// **'Sync only on Wi-Fi'**
  String get storageSyncWifiOnlyLabel;

  /// No description provided for @storageSyncDrawerEntry.
  ///
  /// In en, this message translates to:
  /// **'Local Storage & Sync'**
  String get storageSyncDrawerEntry;

  /// No description provided for @drawerManageCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get drawerManageCategories;

  /// No description provided for @manageCategoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get manageCategoriesTitle;

  /// No description provided for @manageCategoriesProductsTab.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get manageCategoriesProductsTab;

  /// No description provided for @manageCategoriesExpensesTab.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get manageCategoriesExpensesTab;

  /// No description provided for @manageCategoriesAdd.
  ///
  /// In en, this message translates to:
  /// **'Add category'**
  String get manageCategoriesAdd;

  /// No description provided for @manageCategoriesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No categories yet. Tap + to add one.'**
  String get manageCategoriesEmpty;

  /// No description provided for @manageCategoriesDefaultBadge.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get manageCategoriesDefaultBadge;

  /// No description provided for @manageCategoriesNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Category name'**
  String get manageCategoriesNameLabel;

  /// No description provided for @manageCategoriesNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get manageCategoriesNewTitle;

  /// No description provided for @manageCategoriesRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename category'**
  String get manageCategoriesRenameTitle;

  /// No description provided for @manageCategoriesSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get manageCategoriesSave;

  /// No description provided for @manageCategoriesRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get manageCategoriesRename;

  /// No description provided for @manageCategoriesHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get manageCategoriesHide;

  /// No description provided for @manageCategoriesHideConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Hide category?'**
  String get manageCategoriesHideConfirmTitle;

  /// No description provided for @manageCategoriesHideConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'It will no longer appear when adding or editing items. Items already using it keep it until you change them.'**
  String get manageCategoriesHideConfirmBody;

  /// No description provided for @failedPostsTitle.
  ///
  /// In en, this message translates to:
  /// **'Failed posts'**
  String get failedPostsTitle;

  /// No description provided for @failedPostsRetryButton.
  ///
  /// In en, this message translates to:
  /// **'RETRY'**
  String get failedPostsRetryButton;

  /// No description provided for @failedPostsDiscardButton.
  ///
  /// In en, this message translates to:
  /// **'DISCARD'**
  String get failedPostsDiscardButton;

  /// No description provided for @failedPostsDiscardConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard this post?'**
  String get failedPostsDiscardConfirmTitle;

  /// No description provided for @failedPostsDiscardConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You can\'t recover it. Continue?'**
  String get failedPostsDiscardConfirmBody;

  /// No description provided for @failedPostsDiscardConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'DISCARD'**
  String get failedPostsDiscardConfirmAction;

  /// No description provided for @failedPostsEmptyState.
  ///
  /// In en, this message translates to:
  /// **'No failed posts.'**
  String get failedPostsEmptyState;

  /// No description provided for @syncFirstTimeSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to load your shop\'s data'**
  String get syncFirstTimeSetupTitle;

  /// No description provided for @syncFirstTimeSetupBody.
  ///
  /// In en, this message translates to:
  /// **'We need to fetch your items, customers, and recent transactions one time before you can work offline. Open Wi-Fi or mobile data, then tap Retry.'**
  String get syncFirstTimeSetupBody;

  /// No description provided for @syncFirstTimeSetupRetryButton.
  ///
  /// In en, this message translates to:
  /// **'RETRY'**
  String get syncFirstTimeSetupRetryButton;

  /// No description provided for @syncFirstTimeLoadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Setting up your shop…'**
  String get syncFirstTimeLoadingTitle;

  /// No description provided for @syncFirstTimeLoadingBody.
  ///
  /// In en, this message translates to:
  /// **'Loading your items, customers, and recent activity. This only happens once.'**
  String get syncFirstTimeLoadingBody;

  /// No description provided for @syncIssueBannerLabel.
  ///
  /// In en, this message translates to:
  /// **'⚠ Working offline since {time}. Tap to retry sync.'**
  String syncIssueBannerLabel(String time);

  /// No description provided for @syncForceSyncingToast.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncForceSyncingToast;

  /// No description provided for @syncForceSyncedToast.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Already up to date} =1{Synced 1 update} other{Synced {count} updates}}'**
  String syncForceSyncedToast(int count);

  /// No description provided for @syncForceFailedToast.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sync — try again later.'**
  String get syncForceFailedToast;
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

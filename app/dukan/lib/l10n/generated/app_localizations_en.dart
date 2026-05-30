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
}

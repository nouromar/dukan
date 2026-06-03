// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Somali (`so`).
class AppLocalizationsSo extends AppLocalizations {
  AppLocalizationsSo([String locale = 'so']) : super(locale);

  @override
  String get appTitle => 'Dukaan';

  @override
  String get languageEnglish => 'EN';

  @override
  String get languageSomali => 'SO';

  @override
  String get homeHint => 'Dooro shaqada maanta';

  @override
  String get sale => 'Iib';

  @override
  String get receive => 'Qaadasho';

  @override
  String get payment => 'Bixin';

  @override
  String get expense => 'Kharash';

  @override
  String get cash => 'KAASH';

  @override
  String get debt => 'DEYN';

  @override
  String get confirm => 'XAQIIJI';

  @override
  String get searchItems => 'Raadi alaab';

  @override
  String get favorites => 'Kuwa la jecel yahay';

  @override
  String get cart => 'GAARI';

  @override
  String itemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alaab',
      one: '1 alaab',
      zero: '0 alaab',
    );
    return '$_temp0';
  }

  @override
  String get total => 'Wadar';

  @override
  String get savedUndo => 'Waa la keydiyay.';

  @override
  String get undo => 'Ka noqo';

  @override
  String get quantity => 'Tiro';

  @override
  String get price => 'Qiime';

  @override
  String get optionalPrice => 'Qiime beddel';

  @override
  String get addToCart => 'KU DAR';

  @override
  String get cancel => 'Jooji';

  @override
  String get customerDebt => 'Macmiilka deynta';

  @override
  String get searchCustomers => 'Raadi macmiil';

  @override
  String get emptySaleHint => 'Taabo alaabta. Riix dheer tiro ama qiime.';

  @override
  String get receiveTitle => 'Qaadasho';

  @override
  String get supplierFirst => 'Marka hore dooro keenaha';

  @override
  String get recentSuppliers => 'Keenayaal dhawaan';

  @override
  String get searchSuppliers => 'Raadi keenaha';

  @override
  String get newSupplier => '+ Keene cusub';

  @override
  String get newSupplierStub => 'Keene cusub — magac iyo telefoon marka dambe.';

  @override
  String get repeatLastBono => 'Ku celi bonadii hore';

  @override
  String get bonoAttached => 'Bono waa la raaciyay';

  @override
  String get attachBono => 'Ku dar sawir bono';

  @override
  String receiveFrom(Object supplier) {
    return 'Ka qaado $supplier';
  }

  @override
  String get item => 'Alaab';

  @override
  String get searchItem => 'Raadi alaab';

  @override
  String get unit => 'Halbeeg';

  @override
  String get cost => 'Qiime gadasho';

  @override
  String get perUnit => 'midkiiba';

  @override
  String get line => 'xariiq';

  @override
  String get lineTotal => 'Wadarta xariiqda';

  @override
  String get addLine => 'KU DAR XARIIQ';

  @override
  String linesSoFar(Object count) {
    return 'Xariiqyo: $count';
  }

  @override
  String get bonoTotal => 'Wadarta bono';

  @override
  String get paidNow => 'Hadda la bixiyay';

  @override
  String get credit => 'Deyn';

  @override
  String get paidAll => 'Dhammaan bixi';

  @override
  String get mismatchWarning =>
      'Wadarta bono way ka duwan tahay xariiqyada — waa OK.';

  @override
  String get chooseItemWarning => 'Dooro alaab, tiro, iyo qiime.';

  @override
  String get confirmReceive => 'XAQIIJI QAADASHO';

  @override
  String get numberDone => 'DHAMME';

  @override
  String get clear => 'TIRTIR';

  @override
  String get backspace => 'DEL';

  @override
  String get paymentTitle => 'Bixin macmiil';

  @override
  String get pickCustomer => 'Dooro macmiil';

  @override
  String get amount => 'Lacag';

  @override
  String get confirmPayment => 'XAQIIJI BIXIN';

  @override
  String get expenseTitle => 'Kharash';

  @override
  String get category => 'Nooc';

  @override
  String get confirmExpense => 'XAQIIJI KHARASH';

  @override
  String get rent => 'Kiro';

  @override
  String get power => 'Koronto';

  @override
  String get salary => 'Mushahar';

  @override
  String get water => 'Biyo';

  @override
  String get transport => 'Gaadiid';

  @override
  String get other => 'Kale';

  @override
  String get comingSoon => 'Shaashad tijaabo waa la keydiyay. Ka noqo?';

  @override
  String get supabaseConfigTitle => 'Dukaan ku xir Supabase';

  @override
  String get supabaseConfigMessage =>
      'Ku dar Supabase URL iyo anon key si login loo isticmaalo. Weli waad furi kartaa shaashadaha tijaabada.';

  @override
  String get supabaseConfigCommand =>
      'flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...';

  @override
  String get openPrototype => 'Fur tijaabada';

  @override
  String get loginTitle => 'Soo gal';

  @override
  String get loginHeadline => 'Isticmaal telefoonkaaga';

  @override
  String get loginBody =>
      'Waxaan kuu diraynaa kood hal mar la isticmaalo. Dukaan wuxuu backend-ka uga diri karaa WhatsApp.';

  @override
  String get phoneNumberLabel => 'Lambarka telefoonka';

  @override
  String get sendOtpButton => 'DIR KOOD';

  @override
  String get verifyOtpTitle => 'Geli kood';

  @override
  String get verifyOtpHeadline => 'Eeg telefoonkaaga';

  @override
  String verifyOtpBody(Object phone) {
    return 'Geli koodka loo diray $phone.';
  }

  @override
  String get otpCodeLabel => 'Kood';

  @override
  String get verifyOtpButton => 'XAQIIJI';

  @override
  String get changePhoneButton => 'Bedel lambarka telefoonka';

  @override
  String get ownerOnboardingTitle => 'Abuur dukaan';

  @override
  String get ownerOnboardingHeadline => 'Diyaari dukaanka koowaad';

  @override
  String get ownerOnboardingBody =>
      'Geli magaca ganacsiga iyo dukaanka. Shaqaale waad ku dari kartaa marka dambe.';

  @override
  String get businessNameLabel => 'Magaca ganacsiga';

  @override
  String get shopNameLabel => 'Magaca dukaanka';

  @override
  String get createShopButton => 'ABUUR DUKAAN';

  @override
  String get chooseShopTitle => 'Dooro dukaan';

  @override
  String shopSetupStatus(Object status) {
    return 'Diyaarin: $status';
  }

  @override
  String activeShopLabel(Object shop) {
    return 'Dukaan: $shop';
  }

  @override
  String get signOut => 'Ka bax';

  @override
  String get invalidPhoneMessage =>
      'Geli lambar telefoon sax ah, tusaale +252612345678.';

  @override
  String get missingPendingPhoneMessage =>
      'Marka hore ku bilow lambarka telefoonkaaga.';

  @override
  String get missingShopNamesMessage =>
      'Geli magaca ganacsiga iyo magaca dukaanka labadaba.';

  @override
  String get sendOtpFailedMessage =>
      'Koodka lama diri karin. Hubi lambarka ama internetka, ka dib mar kale isku day.';

  @override
  String get verifyOtpFailedMessage =>
      'Koodku waa khalad ama wuu dhacay. Hubi koodka, ka dib mar kale isku day.';

  @override
  String get createShopFailedMessage =>
      'Dukaanka lama abuuri karin. Hubi internetka, ka dib mar kale isku day.';

  @override
  String get shopLoadFailedTitle => 'Dukaamada lama furi karin';

  @override
  String get shopLoadFailedMessage =>
      'Hubi internetka, ka dib mar kale isku day. Haddii ay sii socoto, milkiilaha ha kuu hubiyo gelitaanka.';

  @override
  String get tryAgain => 'MAR KALE ISKU DAY';

  @override
  String get setupStepTemplateTitle => 'Dooro nooca dukaankaaga';

  @override
  String get setupStepTemplateBody =>
      'Dooro xirmo bilow si waxyaalaha caadiga ah iyo goobaha loo diyaariyo.';

  @override
  String setupStepTemplateDone(Object name) {
    return 'Nooca la doortay: $name';
  }

  @override
  String get setupStepFinishTitle => 'Dhamee diyaarinta';

  @override
  String get setupStepFinishBody => 'Xaqiiji oo bilow isticmaalka dukaankaaga.';

  @override
  String get setupStepFinishButton => 'DHAMEE DIYAARINTA';

  @override
  String get templatePickerTitle => 'Dooro nooca dukaankaaga';

  @override
  String get applyTemplateButton => 'ISTICMAAL TAN';

  @override
  String get applyTemplateFailedMessage =>
      'Xirmada lama dabaqi karin. Hubi internetka oo isku day mar kale.';

  @override
  String get templatesEmptyMessage =>
      'Weli ma jiraan noocyo dukaan oo la heli karo. La xiriir taageerada haddii ay sii socoto.';

  @override
  String get completeSetupFailedMessage =>
      'Diyaarinta lama dhamayn karin. Isku day mar kale.';

  @override
  String get settingsTitle => 'Diyaarinta';

  @override
  String get openSettings => 'Diyaarinta';

  @override
  String get settingsShopNameLabel => 'Magaca dukaanka';

  @override
  String get settingsCurrencyLabel => 'Lacagta';

  @override
  String get settingsLanguageLabel => 'Luuqada caadiga ah';

  @override
  String get settingsTimezoneLabel => 'Saacadda goobta';

  @override
  String get settingsSaveButton => 'KEYDI';

  @override
  String get settingsSavedToast => 'Diyaarintu waa la keydiyay';

  @override
  String get settingsSaveFailedMessage =>
      'Diyaarinta lama keydin karin. Isku day mar kale.';

  @override
  String get productsTitle => 'Walxaha';

  @override
  String get productsSearchHint => 'Raadi Soomaali ama Ingiriis';

  @override
  String get productsInYourShop => 'Dukaankaaga ku jira';

  @override
  String get productsFromCatalog => 'Liiska guud';

  @override
  String productsStockLabel(Object quantity, Object unit) {
    return '$quantity $unit oo kaydsan';
  }

  @override
  String get productsNoStock => 'Wax kayd ah ma jiraan';

  @override
  String get productsAddToShopButton => 'KU DAR';

  @override
  String get productsAddingToShop => 'Lagu darayaa…';

  @override
  String productsAddedToShopToast(Object name) {
    return '$name ayaa lagu daray dukaankaaga';
  }

  @override
  String productsAddToShopFailedMessage(Object name) {
    return '$name lama dari karin. Isku day mar kale.';
  }

  @override
  String get productsNewItemButton => '+ WALAX CUSUB';

  @override
  String get productsNewItemUnavailable =>
      'Walxaha aan liiska guud ku jirin waxaa la dari doonaa marka dambe.';

  @override
  String get productsEmptyMessage =>
      'Walxo weli ma jiraan. Ka dar mid liiska guud.';

  @override
  String productsSearchEmptyMessage(Object query) {
    return 'Wax la mid ah “$query” ma jiraan.';
  }

  @override
  String get productsLoadFailedMessage =>
      'Walxaha lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get saleTitle => 'Iibin';

  @override
  String get saleSearchHint => 'Raadi Soomaali ama Ingiriis';

  @override
  String saleCartSummary(num count, Object total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count walxood',
      one: '1 walax',
      zero: 'Wax walax ah ma jiraan',
    );
    return '$_temp0 · $total';
  }

  @override
  String get saleEmptyFavoritesMessage =>
      'Ka dar walxo liiska guud si aad halkan ku aragto.';

  @override
  String saleSearchEmptyMessage(Object query) {
    return 'Wax la mid ah “$query” ma jiraan.';
  }

  @override
  String get saleLoadFailedMessage =>
      'Walxaha lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get saleCash => 'Lacag';

  @override
  String get saleDebt => 'Deyn';

  @override
  String get salePickCustomerButton => 'Dooro macmiil';

  @override
  String saleCustomerChip(Object amount, Object name) {
    return '$name · waxa la leeyahay $amount';
  }

  @override
  String get saleSaveButton => 'KEYDI';

  @override
  String get saleSavedToast => 'Waa la keydiyay';

  @override
  String get salePostFailedMessage =>
      'Iibka lama keydin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get saleNeedItemsMessage => 'Marka hore ku dar ugu yaraan hal walax.';

  @override
  String get saleNeedCustomerMessage => 'Dooro macmiilka iibka deynta ah.';

  @override
  String saleAddedItemToast(Object name) {
    return '$name waa la daray';
  }

  @override
  String saleAddItemFailedMessage(Object name) {
    return '$name lama dari karin. Isku day mar kale.';
  }

  @override
  String get customerPickerTitle => 'Dooro macmiil';

  @override
  String get customerPickerSearchHint => 'Raadi magaca ama telefoonka';

  @override
  String customerPickerOwesLabel(Object amount) {
    return 'waxa la leeyahay $amount';
  }

  @override
  String get customerPickerNoDebtLabel => 'deyn la\'aan';

  @override
  String get customerPickerEmptyMessage =>
      'Wali macmiil ma jiro. Ku dar marka aad qorto iib deyn ah.';

  @override
  String customerPickerSearchEmptyMessage(Object query) {
    return 'Macmiil la mid ah “$query” ma jiro.';
  }

  @override
  String get customerPickerLoadFailedMessage =>
      'Macaamiisha lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get customerNewButton => '+ MACMIIL CUSUB';

  @override
  String get partyNewCustomerTitle => 'Macmiil cusub';

  @override
  String get partyNewSupplierTitle => 'Keene cusub';

  @override
  String get partyNewNameLabel => 'Magaca';

  @override
  String get partyNewPhoneLabel => 'Telefoonka (haddii la rabo)';

  @override
  String get partyNewSaveButton => 'KU DAR';

  @override
  String get partyNewNameRequiredMessage => 'Geli magac';

  @override
  String get partyNewSaveFailedMessage =>
      'Lama dari karin. Hubi internetka oo isku day mar kale.';

  @override
  String get paymentTypeCustomer => 'Macmiil';

  @override
  String get paymentTypeSupplier => 'Keene';

  @override
  String get paymentPickCustomerButton => 'Dooro macmiil';

  @override
  String get paymentPickSupplierButton => 'Dooro keene';

  @override
  String paymentCustomerOwesLabel(Object amount) {
    return 'Wuxuu kuu leeyahay $amount';
  }

  @override
  String paymentSupplierOwedLabel(Object amount) {
    return 'Waxaad ku leedahay $amount';
  }

  @override
  String get paymentAmountLabel => 'Lacagta la bixiyay';

  @override
  String get paymentSaveButton => 'KEYDI';

  @override
  String get paymentSavedToast => 'Bixinta waa la keydiyay';

  @override
  String paymentNeedPartyMessage(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'supplier': 'keenaha',
      'other': 'macmiilka',
    });
    return 'Marka hore dooro $_temp0.';
  }

  @override
  String get paymentNeedAmountMessage => 'Geli lacag ka badan eber.';

  @override
  String paymentExceedsBalanceMessage(Object amount) {
    return 'Lacagtu kama badnaan karto wadarta deynta ($amount).';
  }

  @override
  String get paymentPostFailedMessage =>
      'Bixinta lama keydin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get expenseCategoryLabel => 'Nooca';

  @override
  String get expenseAmountLabel => 'Lacagta';

  @override
  String get expenseSaveButton => 'KEYDI';

  @override
  String get expenseSavedToast => 'Kharashka waa la keydiyay';

  @override
  String get expenseNeedCategoryMessage => 'Marka hore dooro nooc.';

  @override
  String get expenseNeedAmountMessage => 'Geli lacag ka badan eber.';

  @override
  String get expenseLoadFailedMessage =>
      'Noocyada lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get expensePostFailedMessage =>
      'Kharashka lama keydin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get expenseEmptyMessage =>
      'Wali noocyo kharash ma jiraan. Dooro nooca dukaanka Diyaarinta.';

  @override
  String get saleHistoryTitle => 'Iibyada maanta';

  @override
  String get saleHistoryTooltip => 'Taariikhda iibka';

  @override
  String get saleHistoryEmptyMessage =>
      'Wali iib ma jiro. KEYDI hore ee shaashada Iibka ayaa halkan ku soo galaya.';

  @override
  String get saleHistoryLoadFailedMessage =>
      'Iibyada lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get saleHistoryCashLabel => 'Kaash';

  @override
  String saleHistoryDebtLabel(Object name) {
    return 'Deyn · $name';
  }

  @override
  String get saleHistoryVoidedBadge => 'Tirtiran';

  @override
  String get saleDetailTitle => 'Iib';

  @override
  String get saleDetailVoidedHeader => 'Tirtiran';

  @override
  String get saleDetailVoidButton => 'TIRTIR IIBKA';

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
  String get saleDetailTotalLabel => 'Wadar';

  @override
  String get saleDetailPaidLabel => 'La bixiyay';

  @override
  String get saleDetailOwingLabel => 'Weli lagu leeyahay';

  @override
  String get saleDetailLoadFailedMessage => 'Iibkaan lama soo dejin karin.';

  @override
  String get saleVoidConfirmTitle => 'Iibkan ma tirtir?';

  @override
  String get saleVoidConfirmBody =>
      'Iibka waa la rogi doonaa, kayd-ka waa la celin doonaa, oo deynta macmiilka waxa la nadiifin doonaa.';

  @override
  String get saleVoidConfirmYes => 'TIRTIR';

  @override
  String get saleVoidConfirmNo => 'JOOJI';

  @override
  String get saleVoidRefundCheckboxLabel => 'Lacagta ku celi macmiilka';

  @override
  String get saleVoidRefundAmountLabel => 'Lacagta la celiyay';

  @override
  String saleVoidRefundPaidHint(Object amount) {
    return 'la bixiyay: $amount';
  }

  @override
  String saleVoidRefundExceedsPaidMessage(Object paid) {
    return 'Lacagta la celiyay kama badnaan karto lacagta la bixiyay ($paid).';
  }

  @override
  String get saleVoidedToast => 'Iibka waa la tirtiray';

  @override
  String get saleVoidFailedMessage =>
      'Iibka lama tirtiri karin. Hubi internetka oo isku day mar kale.';

  @override
  String get historyMenuSales => 'Taariikhda iibka';

  @override
  String get historyMenuReceives => 'Taariikhda bonada';

  @override
  String get historyMenuTooltip => 'Taariikh';

  @override
  String get receiveHistoryTitle => 'Bonadii maanta';

  @override
  String get receiveHistoryTooltip => 'Taariikhda bonada';

  @override
  String get receiveHistoryEmptyMessage =>
      'Wali bono ma jiro. KEYDI hore ee shaashada Bonada ayaa halkan ku soo galaya.';

  @override
  String get receiveHistoryLoadFailedMessage =>
      'Bonada lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String receiveHistorySupplierLabel(Object name) {
    return 'Keene · $name';
  }

  @override
  String get receiveHistoryVoidedBadge => 'Tirtiran';

  @override
  String get receiveDetailTitle => 'Bono';

  @override
  String get receiveDetailVoidedHeader => 'Tirtiran';

  @override
  String get receiveDetailVoidButton => 'TIRTIR BONADAN';

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
  String get receiveDetailTotalLabel => 'Wadar';

  @override
  String get receiveDetailLoadFailedMessage => 'Bonadan lama soo dejin karin.';

  @override
  String get receiveVoidConfirmTitle => 'Bonadan ma tirtir?';

  @override
  String get receiveVoidConfirmBody =>
      'Tan u isticmaal kaliya marka aad qaladka u dhigtay bonada. Bonada waa la rogi doonaa, kayd-ka waa la dhimi doonaa, oo lacagta aad keenaha ku leedahay ee bonadan waa la tirtir doonaa.';

  @override
  String get receiveVoidMistakesOnlyHint =>
      'Kaliya qaladaad. Haddii aad keenaha wax u celineyso, taas u qor lacag-bixinta.';

  @override
  String get receiveVoidConfirmYes => 'TIRTIR';

  @override
  String get receiveVoidConfirmNo => 'JOOJI';

  @override
  String get receiveVoidedToast => 'Bonadu waa la tirtiray';

  @override
  String get receiveVoidFailedMessage =>
      'Bonada lama tirtiri karin. Hubi internetka oo isku day mar kale.';

  @override
  String get receiveVoidBlockedStockMessage =>
      'Walxaha bonadan qaarkood mar hore wuu dhaqaaqay. Tirtiridda way joojin tahay.';

  @override
  String cartLineSubtotal(Object quantity, Object subtotal, Object unitPrice) {
    return '$quantity × $unitPrice = $subtotal';
  }

  @override
  String cartRemoveLineTooltip(Object name) {
    return 'Ka saar $name';
  }

  @override
  String get cartExpandHint => 'Muuji walxaha';

  @override
  String get cartCollapseHint => 'Qari walxaha';

  @override
  String get cartClearAllButton => 'Tirtir dhammaan';

  @override
  String cartClearConfirmTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count walxood',
      one: '1 walax',
    );
    return 'Ka tirtir $_temp0 gaariga?';
  }

  @override
  String get cartClearConfirmBody => 'Tan ma noqonayso iib hore loo keydiyay.';

  @override
  String get cartClearConfirmYes => 'TIRTIR';

  @override
  String get cartClearConfirmNo => 'JOOJI';

  @override
  String get lineEditorDoneButton => 'DHAMME';

  @override
  String get lineEditorPriceRequiredHelper => 'Geli qiimaha walaxdan';

  @override
  String get lineEditorInvalidPriceMessage => 'Geli lambar 0 ama wax ka badan';

  @override
  String get lineEditorTilePriceMissing => '—';

  @override
  String get supplierPickerTitle => 'Dooro keenaha';

  @override
  String get supplierPickerSearchHint => 'Raadi magaca ama telefoonka';

  @override
  String supplierPickerOwesLabel(Object amount) {
    return 'waxaad ku leedahay $amount';
  }

  @override
  String get supplierPickerNoBonosLabel => 'bono weli ma jirin';

  @override
  String get supplierPickerEmptyMessage =>
      'Wali keene ma jiro. Ku dar marka aad qorto bono.';

  @override
  String supplierPickerSearchEmptyMessage(Object query) {
    return 'Keene la mid ah “$query” ma jiro.';
  }

  @override
  String get supplierPickerLoadFailedMessage =>
      'Keenayaasha lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get supplierNewButton => '+ KEENE CUSUB';

  @override
  String get receiveSearchHint => 'Raadi Soomaali ama Ingiriis';

  @override
  String get receiveLoadFailedMessage =>
      'Walxaha lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get receiveEmptyMessage =>
      'Taabo walax si aad u bilowdo bono. Raadi haddii aysan ku jirin shabakada.';

  @override
  String get receiveLineQuantityLabel => 'Tirada';

  @override
  String receiveLinePerUnitLabel(Object currency, Object unit) {
    return '$currency mid kasta $unit';
  }

  @override
  String receiveLineTotalLabel(Object currency) {
    return '$currency wadarta';
  }

  @override
  String get receiveAddLineButton => 'KU DAR XARIIQ';

  @override
  String receiveLineSubtotal(Object quantity, Object total, Object unit) {
    return '$quantity $unit · $total';
  }

  @override
  String receiveLineRemoveTooltip(Object name) {
    return 'Ka saar $name';
  }

  @override
  String receiveLinesSummary(num count, Object total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count xariiqyo',
      one: '1 xariiq',
      zero: 'Wax xariiq ah ma jiraan',
    );
    return '$_temp0 · $total';
  }

  @override
  String get receiveLinesClearAllButton => 'Tirtir dhammaan';

  @override
  String receiveLinesClearConfirmTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count xariiqyo',
      one: '1 xariiq',
    );
    return 'Tirtir $_temp0?';
  }

  @override
  String get receiveLinesClearConfirmBody =>
      'Tan ma noqonayso bono hore loo keydiyay.';

  @override
  String get receiveLinesClearConfirmYes => 'TIRTIR';

  @override
  String get receiveLinesClearConfirmNo => 'JOOJI';

  @override
  String get receiveSaveButton => 'KEYDI';

  @override
  String get receiveSavedToast => 'Bono waa la keydiyay (deyn)';

  @override
  String get receivePostFailedMessage =>
      'Bonadu lama keydin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get receiveNeedSupplierMessage =>
      'Dooro keene ka hor inta aadan keydin.';

  @override
  String get receiveNeedLinesMessage =>
      'Marka hore ku dar ugu yaraan hal xariiq.';

  @override
  String get receiveInvalidNumberMessage => 'Geli lambar wanaagsan';

  @override
  String get unitPickerTitle => 'Dooro halbeeg';

  @override
  String get unitPickerDefaultBadge => 'caadi';

  @override
  String get unitPickerBaseUnit => 'halbeeg aasaasi';

  @override
  String unitPickerConversion(Object base, Object multiplier, Object unit) {
    return '$multiplier $base $unit walba';
  }

  @override
  String get unitPickerLoadFailedMessage =>
      'Halbeegyada lama soo dejin karin. Isku day mar kale.';
}

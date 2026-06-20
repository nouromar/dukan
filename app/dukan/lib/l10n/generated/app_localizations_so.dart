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
  String get languageEnglish => 'Ingiriis';

  @override
  String get languageSomali => 'Soomaali';

  @override
  String get homeHint => 'Dooro shaqada maanta';

  @override
  String get sale => 'Iibi';

  @override
  String get receive => 'Alaab Dajin';

  @override
  String get payment => 'Lacag bixin';

  @override
  String get expense => 'Qarashaad';

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
  String get cart => 'Danbiil';

  @override
  String get total => 'Wadar';

  @override
  String get undo => 'Ka noqo';

  @override
  String get quantity => 'Tiro';

  @override
  String get price => 'Qiime';

  @override
  String get cancel => 'Jooji';

  @override
  String get receiveTitle => 'Alaab dajin';

  @override
  String get bonoAttachTooltip => 'Sawir bonoga';

  @override
  String get bonoAttachedTooltip =>
      'Bono waa la sawiray — taabo si aad u beddesho';

  @override
  String get bonoAttachCamera => 'Sawir hadda';

  @override
  String get bonoAttachGallery => 'Sawir ka hor leh';

  @override
  String get bonoAttachedToast => 'Sawirka bonoga waa la raaciyay';

  @override
  String get bonoAttachFailedMessage =>
      'Bonoga lama raacin karin. Isku day mar kale.';

  @override
  String get partyDetailTitle => 'Qof';

  @override
  String get partyDetailLoadFailedMessage => 'Qofkan lama soo dejin karin.';

  @override
  String get partyDetailReceivableLabel => 'Adigaa lacag laguu leeyahay';

  @override
  String get partyDetailPayableLabel => 'Iyagaa lacag lagu leeyahay';

  @override
  String get partyDetailPayButton => 'LACAG BIXI';

  @override
  String get partyDetailSalesHeader => 'Iibka';

  @override
  String get partyDetailReceivesHeader => 'Alaab La dajiyey';

  @override
  String get partyDetailPaymentsHeader => 'Lacagaha la bixiyey';

  @override
  String get homeTodayHeader => 'Maanta';

  @override
  String get homeSalesTodayLabel => 'Iibka manta';

  @override
  String get homeReceivablesLabel => 'Deynta kaa maqan';

  @override
  String get homePayablesLabel => 'Deyn aad qabto';

  @override
  String get homeLowStockLabel => 'Alaab Yaraatey';

  @override
  String homeLowStockCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alaab',
      one: '1 alaab',
      zero: 'midna',
    );
    return '$_temp0';
  }

  @override
  String get lowStockReportTitle => 'Alaabta yaraatey';

  @override
  String get lowStockReportEmptyMessage => 'Wax yaraatey ma jiraan.';

  @override
  String get reportLoadFailedMessage =>
      'Ma soo dejin karno. Hoos u jiid si aad mar kale isku daydo.';

  @override
  String get filterTooltip => 'Shaandhee';

  @override
  String get filterSheetTitle => 'Shaandhee';

  @override
  String get filterApplyButton => 'ISTICMAAL';

  @override
  String get filterResetButton => 'Tirtir';

  @override
  String get dateRangeToday => 'Maanta';

  @override
  String get dateRangeWeek => '7-da maalmood ee tegay';

  @override
  String get dateRangeMonth => 'Bishaan';

  @override
  String get dateRangeAll => 'Waqti kasta';

  @override
  String get dateRangeCustom => 'Doorasho…';

  @override
  String get filterPartyAny => 'Qof kasta';

  @override
  String get filterHideVoided => 'Qari kuwa la tirtiray';

  @override
  String get filterCategoryAny => 'Qayb kasta';

  @override
  String get filterLowStockOnly => 'Kaliya kuwa yaraatey';

  @override
  String get filterNoPriceOnly => 'Aan qiimo lahayn';

  @override
  String get lowStockSearchHint => 'Raadi alaab';

  @override
  String filterChipParty(String name) {
    return 'Qof: $name';
  }

  @override
  String get filterChipHideVoided => 'La qariyay kuwa la tirtiray';

  @override
  String filterChipCategory(String name) {
    return '$name';
  }

  @override
  String get filterChipLowStock => 'Yaraatey';

  @override
  String get filterChipNoPrice => 'Aan qiimo lahayn';

  @override
  String get drawerHistoryHeader => 'TAARIIKH';

  @override
  String get drawerSalesHistory => 'Taariikhda iibka';

  @override
  String get drawerReceiveHistory => 'Taariikhda alaabta la qaatay';

  @override
  String get drawerExpenseHistory => 'Taariikhda kharashka';

  @override
  String get expenseHistoryTitle => 'Kharashaadka';

  @override
  String get expenseHistoryLoadFailedMessage =>
      'Kharashka ma soo dejin karno. Hoos u jiid si aad mar kale isku daydo.';

  @override
  String get expenseHistoryEmptyMessage => 'Kharash weli ma jiro.';

  @override
  String get drawerPaymentHistory => 'Taariikhda lacagaha';

  @override
  String get paymentHistoryTitle => 'Lacagaha';

  @override
  String get paymentHistoryLoadFailedMessage =>
      'Lacagaha ma soo dejin karno. Hoos u jiid si aad mar kale isku daydo.';

  @override
  String get paymentHistoryEmptyMessage => 'Lacag weli ma jiro.';

  @override
  String get paymentHistoryNoParty => 'Kaash';

  @override
  String get paymentHistoryRefundBadge => 'celin';

  @override
  String get paymentDirectionLabel => 'Jihada';

  @override
  String get paymentDirectionAny => 'Jiho kasta';

  @override
  String get paymentDirectionInbound => 'Macmiil ku bixiyay';

  @override
  String get paymentDirectionOutbound => 'Bixiye aad bixisay';

  @override
  String get partiesLoadFailedMessage =>
      'Ma soo dejin karno. Hoos u jiid si aad mar kale isku daydo.';

  @override
  String get partiesEmptyMessage => 'Macaamiil ama bixiye weli ma jiro.';

  @override
  String partiesEmptyForQuery(String query) {
    return 'Wax la mid ah \"$query\" lama helin.';
  }

  @override
  String get partyNewOpeningReceivableLabel => 'Deyn furitaan (kuugu leh)';

  @override
  String get partyNewOpeningPayableLabel => 'Deyn furitaan (aad u leh)';

  @override
  String get partyNewOpeningBalanceHelper =>
      'Ikhtiyaari — deynta hore ka horeysay app-kan.';

  @override
  String get partyDetailEditTooltip => 'Bedel magaca & telefoonka';

  @override
  String get drawerPeopleHeader => 'DADKA';

  @override
  String get drawerCustomers => 'Macaamiisha';

  @override
  String get drawerSuppliers => 'Alaab Keenayaasha';

  @override
  String get customersTitle => 'Macaamiisha';

  @override
  String get suppliersTitle => 'Alaab Keenayaasha';

  @override
  String get customersSearchHint => 'Raadi macmiil';

  @override
  String get suppliersSearchHint => 'Raadi bixiye';

  @override
  String get customersAddButton => 'Ku dar';

  @override
  String get suppliersAddButton => 'Ku dar';

  @override
  String get customersHasBalanceChip => 'Oo deyn kuu leh';

  @override
  String get suppliersHasBalanceChip => 'Oo deyn ku leh';

  @override
  String get customersHeadlineLabel => 'Deyn lagaa qabo';

  @override
  String get suppliersHeadlineLabel => 'Deyn aad qabto';

  @override
  String customersHeadlineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count macaamiil oo deyn leh',
      one: '1 macmiil oo deyn leh',
      zero: 'Macmiil deyn leh ma jiro',
    );
    return '$_temp0';
  }

  @override
  String suppliersHeadlineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bixiye oo deyn leh',
      one: '1 bixiye oo deyn leh',
      zero: 'Bixiye deyn leh ma jiro',
    );
    return '$_temp0';
  }

  @override
  String get peopleSortLabel => 'Habayn';

  @override
  String get peopleSortByReceivable => 'Deyn (kii ugu badnaa horta)';

  @override
  String get peopleSortByPayable => 'Deyn (kii ugu badnaa horta)';

  @override
  String get peopleSortByName => 'Magac (alifba)';

  @override
  String stockAdjustTitle(String name) {
    return 'Hagaaji kayd $name';
  }

  @override
  String stockAdjustCurrentLabel(String amount, String unit) {
    return 'Hadda: $amount $unit';
  }

  @override
  String get stockAdjustModeOpening => 'Furitaan';

  @override
  String get stockAdjustModeAdd => 'Ku dar';

  @override
  String get stockAdjustModeSubtract => 'Ka jar';

  @override
  String get stockAdjustModeSetExact => 'Cusub';

  @override
  String get stockAdjustModeOpeningHelper =>
      'Kayddii aad hore u haysatay ka hor app-kan.';

  @override
  String get stockAdjustModeAddHelper => 'Kayd la helay oo aan bono ku jirin.';

  @override
  String get stockAdjustModeSubtractHelper =>
      'Burburin, lumin, ama wax aan dib loo celin karin.';

  @override
  String get stockAdjustModeSetExactHelper =>
      'Geli tirada saxda ah ee aad heshay.';

  @override
  String stockAdjustAmountLabel(String unit) {
    return 'Tirada ($unit)';
  }

  @override
  String stockAdjustUnitCostLabel(String unit, String currency) {
    return 'Qiimaha $unit ($currency)';
  }

  @override
  String get stockAdjustUnitCostRequiredMessage =>
      'Geli qiimaha xidhmadda si qiimaha celceliska u sii saxo.';

  @override
  String get stockAdjustNotesLabel => 'Faallo (ikhtiyaari)';

  @override
  String stockAdjustPreview(String amount, String unit) {
    return 'Kaydka cusub: $amount $unit';
  }

  @override
  String get stockAdjustSaveButton => 'KEYDI';

  @override
  String get stockAdjustFailedMessage =>
      'Ma keydin karno hagaajinta. Isku day mar kale.';

  @override
  String get stockAdjustInvalidAmountMessage => 'Geli tiro sax ah.';

  @override
  String get barcodeAddDialogTitle => 'Ku dar bar code';

  @override
  String get barcodeAddDialogHint => 'tusaale: 6291100123456';

  @override
  String get barcodeAddDialogSetPrimary => 'Ka dhig kan koowaad';

  @override
  String get barcodeChipMakePrimary => 'Ka dhig kan koowaad';

  @override
  String get barcodeChipRemove => 'Tirtir';

  @override
  String get barcodeAddTooltip => 'Ku dar bar code';

  @override
  String get aliasAddDialogTitle => 'Ku dar magac kale';

  @override
  String get aliasAddDialogHint => 'tusaale: Rice (Ingiriis)';

  @override
  String get aliasAddDialogLanguage => 'Luqadda';

  @override
  String get aliasAddTooltip => 'Ku dar magac kale';

  @override
  String get languageNone => 'Mid kasta';

  @override
  String productsHeadline(int total, int low, int noPrice) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total alaab',
      one: '1 alaab',
      zero: 'Alaab weli ma jiro',
    );
    return '$_temp0 · $low yaraatey · $noPrice qiimo la\'aan';
  }

  @override
  String get productsSortLabel => 'Habayn';

  @override
  String get productsSortByName => 'Magaca (A–Z)';

  @override
  String get productsSortByStockLow => 'Kayd (kii ugu yaraa horta)';

  @override
  String get drawerProductsHeader => 'ALAAB';

  @override
  String get drawerTopMovers => 'Kuwa ugu badan iibka';

  @override
  String get topMoversTitle => 'Kuwa ugu badan iibka';

  @override
  String topMoversPeriodSubtitle(int days) {
    return '$days-dii maalmood';
  }

  @override
  String get topMoversPeriodTooltip => 'Muddo';

  @override
  String topMoversPeriodOption(int days) {
    return '$days-dii maalmood';
  }

  @override
  String get topMoversTopSegment => 'Kuwa ugu badan iibka';

  @override
  String get topMoversDeadSegment => 'Kayd aan iib lahayn';

  @override
  String get topMoversEmptyMessage => 'Iib waqtigan ma jiro.';

  @override
  String get drawerLowStock => 'Alaab yaraatey';

  @override
  String get drawerSetupHeader => 'DEJINTA';

  @override
  String get drawerProducts => 'Alaab';

  @override
  String get drawerSettings => 'Qaabayn';

  @override
  String receiveFrom(Object supplier) {
    return 'Ka qaado $supplier';
  }

  @override
  String get item => 'Alaab';

  @override
  String get unit => 'Halbeeg';

  @override
  String get cost => 'Qiimaha uu ku fadhiyo';

  @override
  String get perUnit => 'midkiiba';

  @override
  String get line => 'sadar';

  @override
  String get lineTotal => 'Wadarta sadar';

  @override
  String get bonoTotal => 'Wadarta bono';

  @override
  String get credit => 'Deyn';

  @override
  String get clear => 'TIRTIR';

  @override
  String get paymentTitle => 'Lacag bixin';

  @override
  String get amount => 'qadar Lacag';

  @override
  String get expenseTitle => 'Qarashaad';

  @override
  String get category => 'Nooc';

  @override
  String get rent => 'Kiro';

  @override
  String get salary => 'Mushahar';

  @override
  String get other => 'Kale';

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
  String get loginTabPhone => 'Taleefan';

  @override
  String get loginTabEmail => 'Iimayl';

  @override
  String get loginHeadline => 'Isticmaal telefoonkaaga';

  @override
  String get loginBody =>
      'Waxaan kuu diraynaa kood hal mar la isticmaalo, text ama whatsapp.';

  @override
  String get loginEmailHeadline => 'Isticmaal iimaylkaaga';

  @override
  String get loginEmailBody =>
      'Waxaan iimaylkaaga ku soo diri doonnaa kood hal mar la isticmaalo.';

  @override
  String get phoneNumberLabel => 'Lambarka telefoonka';

  @override
  String get emailAddressLabel => 'Iimayl';

  @override
  String get sendOtpButton => 'DIR KOOD';

  @override
  String get sendEmailOtpButton => 'DIR KOOD';

  @override
  String get verifyOtpTitle => 'Geli kood';

  @override
  String get verifyOtpHeadline => 'Eeg telefoonkaaga';

  @override
  String get verifyOtpHeadlineEmail => 'Eeg iimaylkaaga';

  @override
  String verifyOtpBody(String phone) {
    return 'Geli koodka loo diray $phone.';
  }

  @override
  String verifyOtpBodyEmail(String email) {
    return 'Geli koodka loo diray $email.';
  }

  @override
  String get otpCodeLabel => 'Kood';

  @override
  String get verifyOtpButton => 'XAQIIJI';

  @override
  String get changePhoneButton => 'Bedel lambarka telefoonka';

  @override
  String get changeEmailButton => 'Bedel iimaylka';

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
  String get invalidEmailMessage =>
      'Geli iimayl sax ah, tusaale you@example.com.';

  @override
  String get missingPendingPhoneMessage =>
      'Marka hore ku bilow lambarka telefoonkaaga.';

  @override
  String get missingPendingDestinationMessage =>
      'Marka hore ku bilow taleefan ama iimayl.';

  @override
  String get missingShopNamesMessage =>
      'Geli magaca ganacsiga iyo magaca dukaanka labadaba.';

  @override
  String get sendOtpFailedMessage =>
      'Koodka lama diri karin. Hubi lambarka ama internetka, ka dib mar kale isku day.';

  @override
  String get sendEmailOtpFailedMessage =>
      'Koodka iimaylka lama diri karin. Hubi cinwaanka ama internet-ka, ka dib mar kale isku day.';

  @override
  String get emailAccountNotFoundMessage =>
      'Iimaylkaas account uma jiro. Weydiiso milkiilaha dukaanka inuu ku daro.';

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
  String get setupStepFinishBody => 'Xaqiiji oo bilow isticmaalka dukaankaaga.';

  @override
  String get setupStepFinishButton => 'DHAMEE DIYAARINTA';

  @override
  String get applyTemplateButton => 'ISTICMAAL TAN';

  @override
  String get applyTemplateFailedMessage =>
      'Xirmada lama dabaqi karin. Hubi internetka oo isku day mar kale.';

  @override
  String get templatesEmptyMessage =>
      'Weli ma jiraan noocyo dukaan. La xiriir support haddii ay sii socoto.';

  @override
  String get completeSetupFailedMessage =>
      'Diyaarinta lama dhamayn. Isku day mar kale.';

  @override
  String get settingsTitle => 'Diyaarinta';

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
  String get settingsSavedToast => 'Diyaarinta waa la keydiyay';

  @override
  String get settingsSaveFailedMessage =>
      'Diyaarinta lama keydin karin. Isku day mar kale.';

  @override
  String get productsTitle => 'Alaab';

  @override
  String get productsSearchHint => 'Ku Raadi Soomaali ama Ingiriis';

  @override
  String get productsNewItemButton => 'Alaab CUSUB';

  @override
  String get productsEmptyMessage => 'Alaabo maleh. Kudar hadda liiska guud.';

  @override
  String productsSearchEmptyMessage(Object query) {
    return 'Wax la mid ah “$query” maleh.';
  }

  @override
  String get productsLoadFailedMessage =>
      'Alaabo lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get saleTitle => 'Iibin';

  @override
  String get saleSearchHint => 'Ku Raadi Soomaali ama Ingiriis';

  @override
  String saleCartSummary(num count, Object total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count shay',
      one: '1 shay',
      zero: 'Alaab maleh',
    );
    return '$_temp0 · $total';
  }

  @override
  String get saleEmptyFavoritesMessage =>
      'Ku dar alaabo liiska guud si aad halkan ku aragto.';

  @override
  String saleSearchEmptyMessage(Object query) {
    return 'Wax la mid ah “$query” ma jiraan.';
  }

  @override
  String get saleLoadFailedMessage =>
      'Alaabo lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get saleCash => 'Lacag';

  @override
  String get saleDebt => 'Deyn';

  @override
  String get salePickCustomerButton => 'Dooro macmiil';

  @override
  String saleCustomerChip(Object amount, Object name) {
    return '$name · wuxuu qabaa $amount';
  }

  @override
  String get saleSaveButton => 'KEYDI';

  @override
  String get salePostFailedMessage =>
      'Iibka lama keydin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get saleNeedItemsMessage => 'Marka hore ku dar ugu yaraan hal shay.';

  @override
  String get saleNeedCustomerMessage => 'Dooro macmiilka iibka deynta ah.';

  @override
  String get customerPickerTitle => 'Dooro macmiil';

  @override
  String get customerPickerSearchHint => 'Raadi magaca ama telefoonka';

  @override
  String customerPickerOwesLabel(Object amount) {
    return 'wuxuu qabaa$amount';
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
  String get partyNewSupplierTitle => 'Alaab keene cusub';

  @override
  String get partyNewNameLabel => 'Magaca';

  @override
  String get partyNewPhoneLabel => 'Telefoonka';

  @override
  String get partyNewSaveButton => 'KU DAR';

  @override
  String get partyNewNameRequiredMessage => 'Geli magac';

  @override
  String get partyNewSaveFailedMessage =>
      'Luguma dari karin. Hubi internetka oo isku day mar kale.';

  @override
  String get paymentTypeCustomer => 'Macmiil';

  @override
  String get paymentTypeSupplier => 'Alaab keene';

  @override
  String get paymentTypeCustomerHint => 'Macmiilku wuxuu ku siinayaa lacag';

  @override
  String get paymentTypeSupplierHint => 'Waxaad alaab keenaha siinaysaa lacag';

  @override
  String get paymentPickCustomerButton => 'Dooro macmiil';

  @override
  String get paymentPickSupplierButton => 'Dooro alaab keene';

  @override
  String paymentCustomerOwesLabel(Object amount) {
    return 'Wuxuu kuu leeyahay $amount';
  }

  @override
  String paymentSupplierOwedLabel(Object amount) {
    return 'Waxaad ka qabtaa $amount';
  }

  @override
  String get paymentAmountLabel => 'Lacagta la bixiyay';

  @override
  String get paymentSaveButton => 'KEYDI';

  @override
  String get paymentNotesLabel => 'Qoraal';

  @override
  String get paymentSavedToast => 'Lacag bixinta waa la keydiyay';

  @override
  String paymentNeedPartyMessage(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'supplier': 'alaab keenaha',
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
      'Lacag bixinta lama keydin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get paymentChooseInvoicesChip => 'Dooro biilasha';

  @override
  String paymentChooseInvoicesChipDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count biil ayaa la doortay',
      one: '1 biil ayaa la doortay',
    );
    return '$_temp0';
  }

  @override
  String allocationHeader(String party) {
    return '$party · dooro biilasha';
  }

  @override
  String allocationToAllocate(String amount) {
    return '$amount ayaa la qaybinaayaa';
  }

  @override
  String allocationRowOpen(String open, String original) {
    return 'Furan $open ee $original';
  }

  @override
  String allocationStillToAllocate(String amount) {
    return 'Wali waxaa hadhay: $amount';
  }

  @override
  String allocationOverAllocated(String amount) {
    return 'Waad dheereysay: $amount';
  }

  @override
  String get allocationBalanced => 'Saxan';

  @override
  String get allocationApplyButton => 'ADKEE';

  @override
  String get allocationNeedAtLeastOne =>
      'Doorro biil ugu yaraan mid si aad u adkayso.';

  @override
  String get allocationLoadFailed => 'Biilasha furan lama soo qaadan karin.';

  @override
  String get allocationNoOpenInvoices => 'Biil furan oo qofkan ah ma jiraan.';

  @override
  String get partyDetailOpenInvoicesHeader => 'Biilasha furan';

  @override
  String partyDetailOpenInvoiceRow(String open, String original) {
    return '$open furan oo $original';
  }

  @override
  String get expenseCategoryLabel => 'Nooca';

  @override
  String get expenseAmountLabel => 'Lacagta';

  @override
  String get expenseSaveButton => 'KEYDI';

  @override
  String get expenseNotesLabel => 'Qoraal';

  @override
  String get expenseSavedToast => 'Qarashka waa la keydiyay';

  @override
  String get expenseNeedCategoryMessage => 'Marka hore dooro nooc.';

  @override
  String get expenseNeedAmountMessage => 'Geli lacag ka badan eber.';

  @override
  String get expenseLoadFailedMessage =>
      'Noocyada lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get expensePostFailedMessage =>
      'Qarashka lama keydin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get expenseEmptyMessage =>
      'Wali noocyada qarashaadka lama galin. Ka dooro nooca dukaanka meesha Diyaarinta.';

  @override
  String get saleHistoryTitle => 'Iibin';

  @override
  String get historyYesterday => 'Shalay';

  @override
  String get historyToday => 'Maanta';

  @override
  String get saleHistoryTooltip => 'Sooyaalka iibka';

  @override
  String get saleHistoryEmptyMessage =>
      'Wali waxba lama gadin.  Marka hore wax gad.';

  @override
  String get saleHistoryLoadFailedMessage =>
      'Iibka lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get saleHistoryCashLabel => 'Kaash';

  @override
  String saleHistoryDebtLabel(Object name) {
    return 'Deyn · $name';
  }

  @override
  String get saleHistoryVoidedBadge => 'LagaNoqday';

  @override
  String get saleDetailTitle => 'Iib';

  @override
  String get saleDetailVoidedHeader => 'LagaNoqday';

  @override
  String get saleDetailVoidButton => 'Ka noqo IIBKA';

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
  String get saleDetailCashLabel => 'Kaash';

  @override
  String get saleDetailDebtLabel => 'Deyn';

  @override
  String get saleDetailLoadFailedMessage => 'Iibkaan lama soo dejin karin.';

  @override
  String get saleReceiptShareButton => 'U DIR RASIID';

  @override
  String get saleReceiptDoneButton => 'DHAMMEYSTIR';

  @override
  String get saleHistoryReceiptTooltip => 'Fur rasiidka';

  @override
  String get saleVoidConfirmTitle => 'Ka noqo iibkan?';

  @override
  String get saleVoidConfirmBody =>
      'Iibka waa laga noqo doonaa, alaabta kayd-ka lugu celi doonaa, deynta macmiilka waa laga jari doonaa.';

  @override
  String get saleVoidConfirmYes => 'KaNoqo';

  @override
  String get saleVoidConfirmNo => 'JOOJI';

  @override
  String get saleVoidRefundCheckboxLabel => 'Lacagta u celi macmiilka';

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
  String get saleVoidedToast => 'Iibka waa laga noqday';

  @override
  String get saleVoidFailedMessage =>
      'Iibka lagama noqo karin. Isku day mar kale.';

  @override
  String get saleVoidErrorOwnerOnly =>
      'Kaliya milkiilaha dukaanka ayaa joojin kara iibka.';

  @override
  String get saleVoidErrorWindowExpired =>
      'Goorta way dhammaatay — iibyada waxaa la joojin karaa 7 maalmood gudahood.';

  @override
  String get saleVoidErrorAlreadyVoided => 'Iibkan hore ayaa loo joojiyay.';

  @override
  String get saleVoidErrorRefundNeedsCustomer =>
      'Iibyada xayeysiis (walk-in) lama soo celin karo — macmiil aan loogu celiyo ma jiro.';

  @override
  String get saleVoidErrorRefundExceedsPaid =>
      'Soo-celinta lagama wada-weynaan karo lacagta kaashka.';

  @override
  String get saleVoidErrorNotFound =>
      'Iibka lama helin. Cusboonaysii oo isku day mar kale.';

  @override
  String get receiveHistoryTitle => 'Alaabtii La dajiyey';

  @override
  String get receiveHistoryTooltip => 'Sooyaalka Alaab keenida';

  @override
  String get receiveHistoryEmptyMessage =>
      'Wali Alaab Lama dejin. Marka hore alaab daji.';

  @override
  String get receiveHistoryLoadFailedMessage =>
      'Sooyaalka Alaab Keenida lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String receiveHistorySupplierLabel(Object name) {
    return 'Alaab keene · $name';
  }

  @override
  String get receiveHistoryVoidedBadge => 'Laga Noqday';

  @override
  String get receiveDetailTitle => 'Alaab La Dajiyey';

  @override
  String get receiveDetailVoidedHeader => 'Laga Noqday';

  @override
  String get receiveDetailVoidButton => 'Ka Noqo BONADAN';

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
  String get receiveDetailLoadFailedMessage =>
      'Alaab dajintan lama soo dejin karin.';

  @override
  String get receiveVoidConfirmTitle => 'Ka noqo alaab dajintan?';

  @override
  String get receiveVoidConfirmBody =>
      'Tan u isticmaal kaliya marka aad qaladka u dhigtay alaab dajinta. Alaab dajinta waa laga noqo doonaa, alaabta kayd-ka waa laga dhimi doonaa, oo lacagta aad alaab keenaha ka qabto ee alaab dajintan waa la nadiifin doonaa.';

  @override
  String get receiveVoidMistakesOnlyHint =>
      'Kaliya qaladaad. Haddii aad alaab keenaha wax u celineyso, taas u qor lacag-bixinta.';

  @override
  String get receiveVoidConfirmYes => 'KaNoqo';

  @override
  String get receiveVoidConfirmNo => 'JOOJI';

  @override
  String get receiveVoidedToast => 'Alaab dajinta waa laga noqday';

  @override
  String get receiveVoidFailedMessage =>
      'Alaab dajinta lagama noqo karin. Hubi internetka oo isku day mar kale.';

  @override
  String get receiveVoidBlockedStockMessage =>
      'Alaabaha alaab dajintan qaarkood mar hore wuu dhaqaaqay. Ka noqoshada waa la joojiyay.';

  @override
  String cartLineSubtotal(Object quantity, Object subtotal, Object unitPrice) {
    return '$quantity × $unitPrice = $subtotal';
  }

  @override
  String cartRemoveLineTooltip(Object name) {
    return 'Ka saar $name';
  }

  @override
  String get cartClearAllButton => 'Tirtir dhammaan';

  @override
  String cartClearConfirmTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count shay',
      one: '1 shay',
    );
    return 'Ka tirtir $_temp0 danbiisha?';
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
  String get lineEditorPriceRequiredHelper => 'Geli qiimaha shaygan';

  @override
  String get lineEditorInvalidPriceMessage => 'Geli lambar 0 ama wax ka badan';

  @override
  String get lineEditorTilePriceMissing => '—';

  @override
  String get supplierPickerTitle => 'Dooro alaab keenaha';

  @override
  String get supplierPickerSearchHint => 'Ku Raadi magaca ama telefoonka';

  @override
  String supplierPickerOwesLabel(Object amount) {
    return 'waxaad ka qabtaa $amount';
  }

  @override
  String get supplierPickerNoBonosLabel => 'alaab dajin maleh';

  @override
  String get supplierPickerEmptyMessage =>
      'Alaab keene maleh. Ku dar marka aad qorto alaab dajin.';

  @override
  String supplierPickerSearchEmptyMessage(Object query) {
    return 'Alaab keene la mid ah “$query” maleh.';
  }

  @override
  String get supplierPickerLoadFailedMessage =>
      'Alaab keenayaasha lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get supplierNewButton => '+ ALAAB KEENE CUSUB';

  @override
  String get receiveSearchHint => 'Ku Raadi Soomaali ama Ingiriis';

  @override
  String get receiveLoadFailedMessage =>
      'Alaabo lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get receiveEmptyMessage =>
      'Taabo alaab si aad u bilowdo alaab dajin. Ku raadi haddii aysan ku jirin shabakada.';

  @override
  String get receiveLineQuantityLabel => 'Tirada';

  @override
  String receiveLineTotalLabel(Object currency) {
    return '$currency wadarta';
  }

  @override
  String receiveLineDerivedPerUnit(String money, String packaging) {
    return '= $money mid kasta $packaging';
  }

  @override
  String get receiveAddLineButton => 'KU DAR SADAR';

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
      other: '$count sadar',
      one: '1 sadar',
      zero: 'Wax sadar ah maleh',
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
      other: '$count sadar',
      one: '1 sadar',
    );
    return 'Tirtir $_temp0?';
  }

  @override
  String get receiveLinesClearConfirmBody =>
      'Tan ma noqonayso alaab dajin hore loo keydiyay.';

  @override
  String get receiveLinesClearConfirmYes => 'TIRTIR';

  @override
  String get receiveLinesClearConfirmNo => 'JOOJI';

  @override
  String get receiveSaveButton => 'KEYDI';

  @override
  String get receiveSavedToast => 'Alaab dajin waa la keydiyay (deyn)';

  @override
  String get receivePostFailedMessage =>
      'Alaab dajinta lama keydin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get receiveNeedSupplierMessage =>
      'Dooro alaab keene ka hor inta aadan keydin.';

  @override
  String get receiveNeedLinesMessage =>
      'Marka hore ku dar ugu yaraan hal sadar.';

  @override
  String get unitPickerTitle => 'Dooro halbeeg';

  @override
  String get unitPickerDefaultBadge => 'caadi';

  @override
  String get unitPickerBaseUnit => 'halbeeg aasaasi';

  @override
  String get unitPickerLoadFailedMessage =>
      'Halbeegyada lama soo dejin karin. Isku day mar kale.';

  @override
  String get unitPickerAddPackagingButton => '+ Ku dar baakad';

  @override
  String addNewItemSearchResult(Object query) {
    return '+ Ku dar alaab cusub: “$query”';
  }

  @override
  String get addNewItemSheetTitle => 'Ku dar alaab cusub';

  @override
  String get addNewItemNameLabel => 'Magaca';

  @override
  String get addNewItemUnitChooseHint => 'Dooro';

  @override
  String get addNewItemCategoryLabel => 'Nooca (ikhtiyaari)';

  @override
  String get addNewItemCancelButton => 'JOOJI';

  @override
  String get addNewItemAddToSaleButton => 'KU DAR IIBKA';

  @override
  String get addNewItemAddToReceiveButton => 'KU DAR ALAAB DAJINTA';

  @override
  String get addNewItemMissingNameMessage => 'Magaca waa loo baahan yahay';

  @override
  String get addNewItemMissingUnitMessage => 'Dooro halbeeg';

  @override
  String get addNewItemInvalidPriceMessage =>
      'Geli qiimaha (0 ama wax ka badan)';

  @override
  String get addNewItemFailedMessage =>
      'Alaabta lama abuuri karin. Isku day mar kale.';

  @override
  String get addNewItemHowSoldHeader => 'Sidee loo iibiyaa?';

  @override
  String get addNewItemHowDeliveredHeader =>
      'Sidee bay alaabkeeneha u keenaan?';

  @override
  String addNewItemBaseOnlyTile(String base) {
    return '$base ku iibiya';
  }

  @override
  String addNewItemPickedPriceLabel(String packaging) {
    return 'Qiimaha iibka mid kasta $packaging';
  }

  @override
  String get addNewItemCustomPackagingEntry => '+ Baakad gaar ah';

  @override
  String get addNewItemCustomBaseUnitLabel => 'Halbeegga aasaasi';

  @override
  String get addNewItemCustomSoldUnitLabel => 'Loo iibiyo';

  @override
  String addNewItemCustomConversionLabel(String base, String sold) {
    return 'Imisa $base ayaa ku jira 1 $sold?';
  }

  @override
  String get addNewItemMissingPackagingMessage => 'Dooro sida loo iibiyo';

  @override
  String get addNewItemLoadOptionsFailedHint =>
      'Soo jeedimaha lama soo dejin karin. Dooro baakad gaar ah.';

  @override
  String get addNewItemUseCustomButton => 'ISTICMAAL BAAKADAN';

  @override
  String get addNewItemLooseType => 'Furan';

  @override
  String get addPackagingSheetTitle => 'Ku dar baakad';

  @override
  String get addPackagingUnitLabel => 'Halbeeg';

  @override
  String addPackagingConversionLabel(Object base, Object unit) {
    return 'Imisa $base ayaa ku jira 1 $unit?';
  }

  @override
  String addPackagingPriceLabel(Object unit) {
    return 'Qiimaha iibka mid kasta $unit (ikhtiyaari)';
  }

  @override
  String get addPackagingSaveButton => 'KU DAR BAAKAD';

  @override
  String get addPackagingFailedMessage =>
      'Baakadda luguma dari karin. Isku day mar kale.';

  @override
  String addPackagingHeaderBaseUnit(Object unit) {
    return 'Halbeeg aasaasi · $unit';
  }

  @override
  String get addPackagingSuggestionsHeader => 'Baakado caadi ah';

  @override
  String get addPackagingCustomEntry => '+ Baakad gaar ah';

  @override
  String get addPackagingLessCommonHeader => 'Kuwo aan caadi ahayn';

  @override
  String packagingConversionPreview(String unit, String qty, String base) {
    return '1 $unit waxay qaaddaa $qty $base';
  }

  @override
  String addPackagingPickedPriceLabel(Object packaging) {
    return 'Qiimaha iibka mid kasta $packaging (ikhtiyaari)';
  }

  @override
  String get addPackagingNoSuggestionsHint =>
      'Halbeegan wali baakado caadi ah uma jiraan — hoosta ka qor mid gaar ah.';

  @override
  String get addPackagingLoadFailedHint =>
      'Soo jeedimaha lama soo dejin karin. Hoosta ka qor mid gaar ah.';

  @override
  String lineEditorCostHintLabel(String cost) {
    return 'Qiimaha aad ku iibsatay ugu dambeysay: $cost. Ku dar dheeraadkaaga caadi ah.';
  }

  @override
  String get shopItemEditorTitleCreate => 'Ku dar alaab cusub';

  @override
  String get shopItemDetailAliasesHeader => 'Magacyo kale';

  @override
  String get shopItemEditorNameLabel => 'Magaca';

  @override
  String get shopItemEditorBaseUnitLabel => 'Halbeeg aasaasi';

  @override
  String get shopItemEditorCategoryLabel => 'Nooca';

  @override
  String get shopItemEditorReorderThresholdLabel =>
      'Soo digi marka kayd-ku ka hooseeyo';

  @override
  String shopItemEditorReorderThresholdHelper(String unit) {
    return '$unit ku qor. Ka tag bannaan haddii aadan rabin digniin.';
  }

  @override
  String get shopItemEditorScanIdentifyButton => 'Sken';

  @override
  String shopItemEditorBarcodeNoMatchToast(String code) {
    return 'Koodhka $code weli kuma jiro cataloga. Buuxi qaybaha kale, ka dibna KAYDI.';
  }

  @override
  String shopItemEditorPrefillBanner(String name) {
    return 'Waxaan ka helay \'$name\' cataloga — fiiri oo wax ka beddel haddii uu jiro waxa kala duwan.';
  }

  @override
  String get shopItemEditorSuggestionInShop =>
      'Horey ayuu dukaankaaga ugu jiray — taabo si aad u furto';

  @override
  String get shopItemEditorSuggestionInCatalog =>
      'Catalog guud — taabo si aad u isticmaasho';

  @override
  String shopItemEditorSessionCounter(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# la daray',
      one: '1 la daray',
    );
    return '$_temp0';
  }

  @override
  String get shopItemEditorSessionSheetTitle => 'Lagu daray fadhigan';

  @override
  String get shopItemEditorSessionSheetViewAll => 'Eeg dhammaan alaabta →';

  @override
  String get shopItemEditorIdentifyHeader => 'Aqoonsasho';

  @override
  String get shopItemEditorPackagingHeader => 'Xidhmada';

  @override
  String get shopItemEditorSupplierHeader => 'Alaab Keene';

  @override
  String get shopItemEditorPickSupplierButton => 'Dooro alaab keene';

  @override
  String get shopItemEditorNewSupplierButton => 'CUSUB';

  @override
  String get shopItemEditorRemoveSupplierTooltip => 'Saar alaab keenaha';

  @override
  String get packagingEditorAddTitle => 'Ku dar xidhmad';

  @override
  String get packagingEditorEditTitle => 'Bedel xidhmadda';

  @override
  String get packagingEditorSaveButton => 'KEYDI';

  @override
  String get packagingEditorMissingUnitMessage =>
      'Dooro nooca xidhmadda (tusaale: bac, sanduuq).';

  @override
  String get packagingEditorMissingConversionMessage =>
      'Imisa unug aasaasi ah ayaa ku jira xidhmaddan? Geli tiro ka weyn 0.';

  @override
  String packagingEditorCostLabel(String unit) {
    return 'Qiimaha $unit';
  }

  @override
  String packagingEditorStockLabel(String unit) {
    return 'Kayd — imisa $unit?';
  }

  @override
  String shopItemEditorBaseStockLabel(String unit) {
    return 'Kayd — furan $unit';
  }

  @override
  String shopItemEditorBaseSaleLabel(String unit) {
    return 'Qiimaha iibka — $unit';
  }

  @override
  String shopItemEditorBaseCostLabel(String unit) {
    return 'Qiimaha keenta — $unit';
  }

  @override
  String shopItemEditorPackagingSummary(
    String sale,
    String cost,
    String stock,
  ) {
    return 'Iib $sale · Qiimaha $cost · $stock kayd';
  }

  @override
  String get shopItemEditorPackagingSummaryEmpty => '—';

  @override
  String get shopItemEditorEditPackagingTooltip => 'Bedel xidhmadda';

  @override
  String get shopItemEditorRemovePackagingTooltip => 'Saar xidhmadda';

  @override
  String get shopItemEditorBuyHeader => 'Alaab Keenayaasha';

  @override
  String get shopItemEditorBuySubtitle =>
      'Alaab keene asaasi + qiimaha caadiga — wuxuu hore u buuxinayaa Qaadasho.';

  @override
  String get shopItemEditorTypicalCostHeader => 'Qiimaha caadiga';

  @override
  String shopItemEditorCostPerPackLabel(String pack) {
    return 'Qiimaha $pack';
  }

  @override
  String get shopItemEditorOpeningHeader => 'Inta Taal';

  @override
  String get shopItemEditorOpeningSubtitle =>
      'Geli kayd hadda baakad walba si warbixinada saxda u shaqeeyaan maalintaa.';

  @override
  String get shopItemEditorOpeningPickBaseUnitFirst =>
      'Marka hore dooro cabbir asaasi ah si aad u isticmaasho qaybtan.';

  @override
  String shopItemEditorOpeningQtyLabel(String unit) {
    return 'Tirada $unit';
  }

  @override
  String shopItemEditorOpeningAsOf(String date) {
    return 'Laga bilaabo $date';
  }

  @override
  String get shopItemEditorChangeDateButton => 'Bedel';

  @override
  String get shopItemEditorOpeningStockNote =>
      'Kayd furitaan oo la diiwaan geliyay xilliga hagaajinta.';

  @override
  String get shopItemEditorDedupTitle =>
      'Waxaa laga yaabaa inaad horey u haysatay';

  @override
  String get shopItemEditorDedupBody =>
      'Dukaankaaga wuxuu leeyahay alaab la mid ah. Mid ka fur si aad u tafatirto, ama sii wad haddii uu kala duwan yahay:';

  @override
  String get shopItemEditorDedupKeepGoing => 'WAA KALA DUWAN';

  @override
  String get shopItemEditorDedupOpenExisting => 'FUR KII HORE';

  @override
  String get shopItemEditorAddPhotoButton => 'Ku dar sawir (ikhtiyaari)';

  @override
  String get shopItemEditorPhotoCapturedLabel => 'Sawir diyaar';

  @override
  String get shopItemEditorRetakePhotoButton => 'Mar kale qaad';

  @override
  String get shopItemEditorRemovePhotoTooltip => 'Saar sawirka';

  @override
  String get shopItemEditorPhotoCapturedToast =>
      'Sawir la qaaday — la soo dejin doonaa marka aad kaydiso.';

  @override
  String get shopItemEditorPhotoUploadFailedToast =>
      'Alaabta waa la kaydiyay, laakiin sawir soo-dejin ma guulaysan. Waad ka qaadi kartaa bogga alaabta.';

  @override
  String get shopItemEditorPackagingsHeader => 'Baakado';

  @override
  String get shopItemEditorAddPackagingButton => 'Ku dar baakad';

  @override
  String get shopItemEditorBaseBadge => 'ASAAS';

  @override
  String get shopItemEditorBasePackagingEmptyHint =>
      'Taabo si aad u gelisid qiime, qarash, kayd';

  @override
  String get shopItemEditorPackagingMissingMessage =>
      'Buuxi ugu yaraan hal qaybsasho (qiime, qarash, kayd, ama barcode).';

  @override
  String get shopItemEditorScanBarcodeButton =>
      'Sken garee barcode (ikhtiyaari)';

  @override
  String get shopItemEditorRescanBarcodeButton => 'Mar kale sken';

  @override
  String get shopItemEditorRemoveBarcodeTooltip => 'Saar barcode-ka';

  @override
  String shopItemEditorBarcodeBoundLabel(String code) {
    return 'Barcode $code';
  }

  @override
  String shopItemEditorBarcodeCapturedToast(String code) {
    return 'Waa la qaaday $code';
  }

  @override
  String get shopItemEditorDiscoveryHeader => 'Magacyo kale';

  @override
  String get shopItemEditorDiscoverySubtitle =>
      'Magacyo kale + qoraalka qoraalka ayaa raadinta ka horumarinaya.';

  @override
  String get shopItemEditorAliasesLabel => 'Magacyo kale';

  @override
  String get shopItemEditorAliasHint => 'Ku dar magac kale';

  @override
  String get shopItemEditorAddAliasButton => 'KU DAR';

  @override
  String get shopItemEditorAliasHelper =>
      'Magacyada macmiilku oran karo. Riix shukaansiga si aad u saarto.';

  @override
  String get shopItemEditorBonoSpellingLabel =>
      'Qoraalka qoraalka (ikhtiyaari)';

  @override
  String get shopItemEditorBonoSpellingHelper =>
      'Sida alaabtan u soo muuqato qoraalka warqada keenaha (tusaale CCL 330x24).';

  @override
  String get removePackagingTooltip => 'Tirtir baakadda';

  @override
  String get shopItemEditorItemSectionHeader => 'Alaab';

  @override
  String get removePackagingConfirmBody =>
      'Ma tirtirayaa baakaddan? Mar dambe wad ku celin kartaa.';

  @override
  String get removePackagingConfirmAction => 'TIRTIR';

  @override
  String get shopItemEditorSaveButton => 'KEYDI';

  @override
  String get shopItemEditorSaveAndAddAnotherButton =>
      'KEYDI OO KU DAR MID KALE';

  @override
  String shopItemEditorSavedAndContinueToast(String name) {
    return '$name waa la keydiyay — ku dar mid kale';
  }

  @override
  String get shopItemDetailEditPrice => 'Bedel qiimaha';

  @override
  String get shopItemDetailDefaultSaleBadge => 'iib caadi';

  @override
  String get shopItemDetailDefaultReceiveBadge => 'alaab caadi';

  @override
  String get shopItemDetailNoPriceLabel => 'qiimo maleh';

  @override
  String shopItemDetailReorderBelowLabel(Object amount, Object unit) {
    return 'Soo qaado marka uu yaraado $amount $unit';
  }

  @override
  String get catalogPickerTitle => 'Eeg liiska guud';

  @override
  String get catalogPickerSearchHint => 'Ku Raadi liiska guud';

  @override
  String get catalogPickerActivatedBadge => 'horeyba';

  @override
  String catalogPickerAddButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count shay',
      one: '1 shay',
    );
    return 'KU DAR $_temp0';
  }

  @override
  String catalogPickerAddedToast(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count shay',
      one: '1 shay',
    );
    return '$_temp0 ayaa la daray';
  }

  @override
  String get setupOnboardingTitle => 'U habee alaabadaada';

  @override
  String setupOnboardingBody(Object count, Object template) {
    return 'Waxaan kuugu darnay $count alaab oo ka mid ah qaabka $template. Hadda iibi waad bilaaban kartaa — qiimayaashu way buuxin doonaan markaad iibinayso.\n\nAma daqiiqad ku qaad:';
  }

  @override
  String get setupOnboardingAddItemsTitle => 'Ku dar alaabadayda';

  @override
  String get setupOnboardingAddItemsBody => 'Alaabaha qaabku aanu lahayn';

  @override
  String get setupOnboardingSetPricesTitle =>
      'U dhig qiimayaal alaabta caanka ah';

  @override
  String get setupOnboardingSetPricesBody =>
      'Si aanu iibku u dhabaalayn qiimo weydiin';

  @override
  String get setupOnboardingBrowseCatalogTitle => 'Eeg liiska guud';

  @override
  String get setupOnboardingBrowseCatalogBody =>
      'Ka dhaqaaji alaabo dheeraad ah liiskayaga';

  @override
  String get setupOnboardingSkipButton => 'BOOD — BILOW IIBKA';

  @override
  String get scanCameraTooltip => 'Akhri jeegga';

  @override
  String get scannerSheetTitle => 'Akhri jeegga';

  @override
  String get scannerTorchTooltip => 'Iftiin';

  @override
  String get scannerHoldSteady =>
      'Si toosan u qabo — 15 ilaa 25 cm meel jeegga';

  @override
  String scanUnknownPillLabel(String code) {
    return 'Jeeg lama yaqaano: $code';
  }

  @override
  String get scanUnknownCreateAction => 'Cusub abuur';

  @override
  String get scanUnknownDismissAction => 'Iska saar';

  @override
  String get scanLookupFailed => 'Jeegga lama heli karo';

  @override
  String multiScanSheetTitle(int count) {
    return 'Multi-akhri ($count)';
  }

  @override
  String multiScanUnknownCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jeeg lama yaqaano — eeg ka dib',
      one: '1 jeeg lama yaqaano — eeg ka dib',
    );
    return '$_temp0';
  }

  @override
  String get multiScanEmptyHint =>
      'Jeegga camera-da hor dhig. Akhrida guul leh waxay galayaan liiska hoose.';

  @override
  String get multiScanDoneAction => 'DHAMAYE';

  @override
  String get multiScanLongPressHint =>
      'Si dheer u taabo si aad u multi-akhrido';

  @override
  String multiScanAppliedSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saf la galiyay',
      one: '1 saf la gallinay',
    );
    return '$_temp0';
  }

  @override
  String get barcodeScanAndBindAction => 'Akhri jeegga';

  @override
  String get barcodeBoundToPackagingMessage =>
      'Jeegga waxa lagu xidhay shaandhada';

  @override
  String get relativeTimeJustNow => 'hadda';

  @override
  String relativeTimeMinutesAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes daqiiqo ka hor',
      one: '1 daqiiqo ka hor',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeHoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours saac ka hor',
      one: '1 saac ka hor',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days maalmood ka hor',
      one: '1 maalin ka hor',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeOn(String date) {
    return '$date-tii';
  }

  @override
  String saleHistoryVoidedSubtitle(String when) {
    return 'la baabi\'iyay $when';
  }

  @override
  String partyDetailEditedAt(String when) {
    return 'xog xidhiidh la beddelay $when';
  }

  @override
  String offlineQueuePillLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hubinta $count',
      one: 'Hubinta 1',
    );
    return '$_temp0';
  }
}

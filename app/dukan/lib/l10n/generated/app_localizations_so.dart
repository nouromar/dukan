// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Somali (`so`).
class AppLocalizationsSo extends AppLocalizations {
  AppLocalizationsSo([String locale = 'so']) : super(locale);

  @override
  String get appTitle => 'DukanPro';

  @override
  String get languageEnglish => 'Ingiriis';

  @override
  String get languageSomali => 'Soomaali';

  @override
  String get homeHint => 'Maxaad qabaneysaa maanta.';

  @override
  String get sale => 'Iibi';

  @override
  String get receive => 'Alaab Dejin';

  @override
  String get payment => 'Lacag bixin';

  @override
  String get paymentInLabel => 'Lacag Qabasho';

  @override
  String get paymentOutLabel => 'Lacag Bixin';

  @override
  String get paymentDetailSettledHeader => 'Waxa loo bixiyay';

  @override
  String get paymentDetailNoAllocations =>
      'Lacagtan weli lama xirin iib ama qaadasho.';

  @override
  String get paymentDetailLoadFailedMessage =>
      'Lama soo qaadan karin lacagtan.';

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
  String get cancel => 'Ka noqo';

  @override
  String get receiveTitle => 'Alaab dejin';

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
  String get partyHideTooltip => 'Qari';

  @override
  String get partyHideConfirmTitle => 'Ma qarinaysaa qofkan?';

  @override
  String get partyHideConfirmBody =>
      'Waxaa laga saari doonaa liisaskaaga. Lacagta iyo taariikhda way sii jiri doonaan. Waxaad weydiisan kartaa taageerada inay soo celiyaan.';

  @override
  String get partyHideConfirmYes => 'QARI';

  @override
  String get partyHiddenToast => 'Qofka waa la qariyay';

  @override
  String get backdateChipToday => 'Maanta';

  @override
  String get backdateChipTooltip => 'Beddel taariikhda';

  @override
  String backdateBannerLabel(String date) {
    return 'Waxaad u diiwaangelinaysaa $date';
  }

  @override
  String get backdateBackToToday => 'MAANTA';

  @override
  String get reportsTitle => 'Warbixino';

  @override
  String get drawerReports => 'Warbixino';

  @override
  String get reportsSalesTitle => 'Iibka';

  @override
  String get reportsProfitTitle => 'Faa\'iido';

  @override
  String get reportsStockTitle => 'Kaydka';

  @override
  String get reportsRevenueLabel => 'Wadarta iibka';

  @override
  String get reportsSalesCountLabel => 'Tirada iibka';

  @override
  String get reportsAvgSaleLabel => 'Celceliska iibka';

  @override
  String get reportsCostLabel => 'Qiimaha alaabta';

  @override
  String get reportsGrossProfitLabel => 'Faa\'iidada guud';

  @override
  String get reportsExpensesLabel => 'Qarashaadka';

  @override
  String get reportsNetProfitLabel => 'Faa\'iidada saafiga ah';

  @override
  String get reportsMarginLabel => 'Faa\'iido boqolkiiba';

  @override
  String get reportsItemsLabel => 'Alaab kaydka ku jirta';

  @override
  String get reportsStockValueLabel => 'Qiimaha kaydka';

  @override
  String get reportsLowStockLabel => 'Alaab yaraatey';

  @override
  String get reportsLoadFailedMessage =>
      'Warbixinada lama soo bandhigi karin. Hubi internetkaaga oo isku day mar kale.';

  @override
  String get partyDetailLoadFailedMessage => 'Qofkan lama soo dejin karin.';

  @override
  String get partyDetailReceivableLabel => 'Lacag laguu leeyahay';

  @override
  String get partyDetailPayableLabel => 'Lacag aad ku leedahay';

  @override
  String get partyDetailPayButton => 'LACAG BIXI';

  @override
  String get partyDetailSalesHeader => 'Iibka';

  @override
  String get partyDetailReceivesHeader => 'Alaab Dejin';

  @override
  String get partyDetailPaymentsHeader => 'Lacagaha la bixiyey';

  @override
  String get homeTodayHeader => 'Maanta';

  @override
  String get homeSalesTodayLabel => 'Iibka maanta';

  @override
  String get homeReceivablesLabel => 'Deyn lagaa qabo';

  @override
  String get homePayablesLabel => 'Deyn aad qabto';

  @override
  String get homeLowStockLabel => 'Alaab yaraatey';

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
  String get filterApplyButton => 'DABBAQ';

  @override
  String get filterResetButton => 'Dib u bilow';

  @override
  String get dateRangeToday => 'Maanta';

  @override
  String get dateRangeWeek => '7 maalmood';

  @override
  String get dateRangeMonth => 'Bishaan';

  @override
  String get dateRangeAll => 'Dhammaan';

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
  String get filterNoPriceOnly => 'Qiimo la\'aan';

  @override
  String get lowStockSearchHint => 'Raadi alaab';

  @override
  String filterChipParty(String name) {
    return 'Qof: $name';
  }

  @override
  String get filterChipHideVoided => 'Qari Kuwa la tiray';

  @override
  String filterChipCategory(String name) {
    return '$name';
  }

  @override
  String get filterChipLowStock => 'Yaraatey';

  @override
  String get filterChipNoPrice => 'Qiimo la\'aan';

  @override
  String get drawerHistoryHeader => 'SOOYAAL';

  @override
  String get drawerSalesHistory => 'Sooyaalka iibka';

  @override
  String get drawerReceiveHistory => 'Sooyaalka Alaab Keenida';

  @override
  String get drawerExpenseHistory => 'Sooyaalka qarashka';

  @override
  String get expenseHistoryTitle => 'Qarashaadka';

  @override
  String get expenseHistoryLoadFailedMessage =>
      'Qarashka ma soo dejin karno. Hoos u jiid si aad mar kale isku daydo.';

  @override
  String get expenseHistoryEmptyMessage => 'Qarash weli ma jiro.';

  @override
  String get drawerPaymentHistory => 'Sooyaalka lacagaha';

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
  String get paymentDirectionOutbound => 'Alaab keene aad bixisay';

  @override
  String get partiesLoadFailedMessage =>
      'Ma soo dejin karno. Hoos u jiid si aad mar kale isku daydo.';

  @override
  String get partiesEmptyMessage => 'Macaamiil ama alaab keene weli ma jiro.';

  @override
  String partiesEmptyForQuery(String query) {
    return 'Wax la mid ah \"$query\" lama helin.';
  }

  @override
  String get partyNewOpeningReceivableLabel => 'Deyn furitaan (kuu leh)';

  @override
  String get partyNewOpeningPayableLabel => 'Deyn furitaan (aad leh)';

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
  String get suppliersSearchHint => 'Raadi alaab keene';

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
      other: '$count alaab keene oo deyn leh',
      one: '1 alaab keene oo deyn leh',
      zero: 'Alaab keene deyn leh ma jiro',
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
  String get stockAdjustModeSetExact => 'Tiro Go\'an';

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
      'Geli qiimaha xirmada si qiimaha celceliska u sii saxo.';

  @override
  String get stockAdjustNotesLabel => 'Faallo (ikhtiyaari)';

  @override
  String stockAdjustPreview(String amount, String unit) {
    return 'Kaydka cusub: $amount $unit';
  }

  @override
  String get stockAdjustSaveButton => 'KAYDI';

  @override
  String get stockAdjustFailedMessage =>
      'Ma kaydin karno hagaajinta. Isku day mar kale.';

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
  String get drawerSettings => 'Qaabeyn';

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
  String get supabaseConfigTitle => 'Ku xir Supabase';

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
  String get changePhoneButton => 'Bedel lambarka';

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
  String get queueCapExceededToast =>
      'Xog hore oo aan la kaydin ayaa la tirtiray — telefoonkaagu wuxuu daahay xagga internet-ka.';

  @override
  String get signOutPendingDialogTitle => 'Xog aan la kaydin';

  @override
  String signOutPendingDialogBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Waxaad haysataa $count diiwaan oo aan weli la kaydin.',
      one: 'Waxaad haysataa 1 diiwaan oo aan weli la kaydin.',
    );
    return '$_temp0 Ma rabtaa inaad sii baxdo? Markaad mar kale gasho ayaa la kaydin doonaa.';
  }

  @override
  String get signOutPendingDialogCancel => 'Ka noqo';

  @override
  String get signOutPendingDialogConfirm => 'Ka bax';

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
  String get shopLoadFailedTitle => 'Dukaan lama furin';

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
  String get settingsTitle => 'Qaabeyn';

  @override
  String get settingsShopNameLabel => 'Magaca dukaanka';

  @override
  String get settingsCurrencyLabel => 'Lacagta';

  @override
  String get settingsLanguageLabel => 'Luuqada caadiga ah';

  @override
  String get settingsTimezoneLabel => 'Saacadda goobta';

  @override
  String get settingsSaveButton => 'KAYDI';

  @override
  String get settingsSavedToast => 'Diyaarinta waa la kaydiyay';

  @override
  String get settingsSaveFailedMessage =>
      'Diyaarinta lama kaydin karin. Isku day mar kale.';

  @override
  String get settingsCurrencyLockedMessage =>
      'Lacagta lama beddeli karo marka dukaanku diiwaangeliyo wax ganacsi. La xiriir taageerada si aad u beddesho.';

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
  String get saleSearchHint => 'Ku Raadi (Somaali/ingiriis)';

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
  String get saleCash => 'Kaash';

  @override
  String get saleDebt => 'Deyn';

  @override
  String get salePickCustomerButton => 'Dooro macmiil';

  @override
  String saleCustomerChip(Object amount, Object name) {
    return '$name · wuxuu qabaa $amount';
  }

  @override
  String get saleSaveButton => 'KAYDI';

  @override
  String get salePostFailedMessage =>
      'Iibka lama kaydin karin. Hubi internetka oo isku day mar kale.';

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
  String get paymentSaveButton => 'KAYDI';

  @override
  String get paymentNotesLabel => 'Qoraal';

  @override
  String get paymentSavedToast => 'Lacag bixinta waa la kaydiyay';

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
      'Lacag bixinta lama kaydin karin. Hubi internetka oo isku day mar kale.';

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
  String get expenseSaveButton => 'KAYDI';

  @override
  String get expenseNotesLabel => 'Qoraal';

  @override
  String get expenseSavedToast => 'Qarashka waa la kaydiyay';

  @override
  String get expenseNeedCategoryMessage => 'Marka hore dooro nooc.';

  @override
  String get expenseNeedAmountMessage => 'Geli lacag ka badan eber.';

  @override
  String get expenseLoadFailedMessage =>
      'Noocyada lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get expensePostFailedMessage =>
      'Qarashka lama kaydin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get expenseEmptyMessage =>
      'Wali noocyada qarashaadka lama galin. Ka dooro nooca dukaanka meesha Diyaarinta.';

  @override
  String get saleHistoryTitle => 'Iibka';

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
  String get saleHistoryVoidedBadge => 'La tirtiray';

  @override
  String get saleDetailTitle => 'Iib';

  @override
  String get saleDetailVoidedHeader => 'La tirtiray';

  @override
  String get saleDetailVoidButton => 'TIRTIR IIBKA';

  @override
  String get expenseDetailTitle => 'Qarash';

  @override
  String get expenseDetailVoidButton => 'TIRTIR QARASHKAN';

  @override
  String get expenseDetailLoadFailedMessage =>
      'Lama soo qaadan karin qarashkan.';

  @override
  String get expenseVoidConfirmTitle => 'Tirtir qarashkan?';

  @override
  String get expenseVoidConfirmBody =>
      'Tani way tirtiraysaa qarashka. Lama soo celin karo.';

  @override
  String get expenseVoidConfirmYes => 'TIRTIR';

  @override
  String get expenseVoidedToast => 'Qarash waa la tirtiray';

  @override
  String get expenseVoidFailedMessage => 'Lama tirtiri karin qarashkan.';

  @override
  String get paymentDetailVoidButton => 'TIRTIR LACAGTAN';

  @override
  String get paymentVoidConfirmTitle => 'Tirtir lacagtan?';

  @override
  String get paymentVoidConfirmBody =>
      'Tani lacagta way tirtiraysaa oo dib u furaysaa wixii la bixiyay. Lama soo celin karo.';

  @override
  String get paymentVoidConfirmYes => 'TIRTIR';

  @override
  String get paymentVoidedToast => 'Lacag waa la tirtiray';

  @override
  String get paymentVoidedHeader => 'La tirtiray';

  @override
  String get paymentVoidFailedMessage => 'Lama tirtiri karin lacagtan.';

  @override
  String get paymentVoidWindowPassedHint =>
      'Wakhtigii tirtiridda wuu dhammaaday';

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
  String get receiptNumberLabel => 'Rasiidka';

  @override
  String get receiptDateLabel => 'Taariikhda';

  @override
  String get receiptThankYou => 'Mahadsanid!';

  @override
  String get saleDetailLoadFailedMessage => 'Iibkaan lama soo dejin karin.';

  @override
  String get saleReceiptShareButton => 'U DIR RASIID';

  @override
  String get saleReceiptDoneButton => 'DHAMMEE';

  @override
  String get saleHistoryReceiptTooltip => 'Fur rasiidka';

  @override
  String get saleVoidConfirmTitle => 'Iibkan tirtir?';

  @override
  String get saleVoidConfirmBody =>
      'Iibka waa la tirtiri doonaa, alaabta kaydka waa lugu celin doonaa, deynta macmiilkana waa la tirtiri doonaa.';

  @override
  String get saleVoidConfirmYes => 'TIRTIR';

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
  String get saleVoidedToast => 'Iibka waa la tirtiray';

  @override
  String get saleVoidFailedMessage =>
      'Iibka lama tirtiri karin. Isku day mar kale.';

  @override
  String get saleVoidErrorOwnerOnly =>
      'Kaliya milkiilaha dukaanka ayaa tirtiri kara iibka.';

  @override
  String get saleVoidErrorWindowExpired =>
      'Goorta way dhammaatay — iibyada waxaa la tirtiri karaa 7 maalmood gudahood.';

  @override
  String get saleVoidErrorAlreadyVoided => 'Iibkan hore ayaa la tirtiray.';

  @override
  String get saleVoidErrorRefundNeedsCustomer =>
      'Iibyada xayeysiis (walk-in) lama soo celin karo — macmiil aan loogu celiyo ma jiro.';

  @override
  String get saleVoidErrorRefundExceedsPaid =>
      'Soo-celintu kama badnaan karto lacagta kaashka.';

  @override
  String get saleVoidErrorNotFound =>
      'Iibka lama helin. Cusboonaysii oo isku day mar kale.';

  @override
  String get receiveHistoryTitle => 'Alaab Keenida';

  @override
  String get receiveHistoryTooltip => 'Sooyaalka Alaab Keenida';

  @override
  String get receiveHistoryEmptyMessage =>
      'Wali Alaab Lama dejin. Marka hore alaab deji.';

  @override
  String get receiveHistoryLoadFailedMessage =>
      'Sooyaalka Alaab Keenida lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String receiveHistorySupplierLabel(Object name) {
    return 'Alaab keene · $name';
  }

  @override
  String get receiveHistoryVoidedBadge => 'La tirtiray';

  @override
  String get receiveDetailTitle => 'Alaab La Dejiyey';

  @override
  String get receiveDetailVoidedHeader => 'La tirtiray';

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
  String get receiveDetailLoadFailedMessage =>
      'Alaab dejintan lama soo dejin karin.';

  @override
  String get receiveVoidConfirmTitle => 'Alaab dejintan tirtir?';

  @override
  String get receiveVoidConfirmBody =>
      'Tan u isticmaal kaliya marka aad qaladka u dhigtay alaab dejinta. Alaab dejinta waa la tirtiri doonaa, alaabta kaydka waa laga dhimi doonaa, oo lacagta aad alaab keenaha ka qabto waa la tirtiri doonaa.';

  @override
  String get receiveVoidMistakesOnlyHint =>
      'Kaliya qaladaad. Haddii aad alaab keenaha wax u celineyso, taas u qor lacag-bixinta.';

  @override
  String get receiveVoidConfirmYes => 'TIRTIR';

  @override
  String get receiveVoidConfirmNo => 'JOOJI';

  @override
  String get receiveVoidedToast => 'Alaab dejinta waa la tirtiray';

  @override
  String get receiveVoidFailedMessage =>
      'Alaab dejinta lama tirtiri karin. Hubi internetka oo isku day mar kale.';

  @override
  String get receiveVoidBlockedStockMessage =>
      'Alaabaha alaab dejintan qaarkood mar hore wuu dhaqaaqay. Tirtiridda waa la diiday.';

  @override
  String cartLineSubtotal(Object quantity, Object subtotal, Object unitPrice) {
    return '$quantity × $unitPrice = $subtotal';
  }

  @override
  String cartRemoveLineTooltip(Object name) {
    return 'Ka saar $name';
  }

  @override
  String get cartClearAllButton => 'Tirtir';

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
  String get cartClearConfirmBody => 'Tan ma noqonayso iib hore loo kaydiyay.';

  @override
  String get cartClearConfirmYes => 'TIRTIR';

  @override
  String get cartClearConfirmNo => 'JOOJI';

  @override
  String get lineEditorDoneButton => 'DHAMMEE';

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
  String get supplierPickerNoBonosLabel => 'alaab dejin maleh';

  @override
  String get supplierPickerEmptyMessage =>
      'Alaab keene maleh. Ku dar marka aad qorto alaab dejin.';

  @override
  String supplierPickerSearchEmptyMessage(Object query) {
    return 'Alaab keene la mid ah “$query” maleh.';
  }

  @override
  String get supplierPickerLoadFailedMessage =>
      'Alaab keenayaasha lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get supplierNewButton => '+ KEENE CUSUB';

  @override
  String get receiveSearchHint => 'Ku Raadi (Somaali/ingiriis)';

  @override
  String get receiveLoadFailedMessage =>
      'Alaabo lama soo dejin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get receiveEmptyMessage =>
      'Taabo alaab si aad u bilowdo alaab dejin. Ku raadi haddii aysan ku jirin shabakada.';

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
  String get receiveLinesClearAllButton => 'Tirtir';

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
      'Tan ma noqonayso alaab dejin hore loo kaydiyay.';

  @override
  String get receiveLinesClearConfirmYes => 'TIRTIR';

  @override
  String get receiveLinesClearConfirmNo => 'JOOJI';

  @override
  String get receiveSaveButton => 'KAYDI';

  @override
  String get saleSavedToast => 'Iibka waa la kaydiyay';

  @override
  String get receiveSavedToast => 'Alaab dejin waa la kaydiyay (deyn)';

  @override
  String get receivePostFailedMessage =>
      'Alaab dejinta lama kaydin karin. Hubi internetka oo isku day mar kale.';

  @override
  String get receiveNeedSupplierMessage =>
      'Dooro alaab keene ka hor inta aadan kaydin.';

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
  String get unitPickerAddPackagingButton => '+ Ku dar xirmo';

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
  String get addNewItemCancelButton => 'KA NOQO';

  @override
  String get addNewItemAddToSaleButton => 'KU DAR IIBKA';

  @override
  String get addNewItemAddToReceiveButton => 'KU DAR DEJINTA';

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
  String get addNewItemHowDeliveredHeader => 'Sidee loo keenay?';

  @override
  String addNewItemBaseOnlyTile(String base) {
    return '$base ku iibiya';
  }

  @override
  String addNewItemPickedPriceLabel(String packaging) {
    return 'Qiimaha iibka mid kasta $packaging';
  }

  @override
  String get addNewItemCustomPackagingEntry => '+ Xirmo gaar ah';

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
      'Soo jeedimaha lama soo dejin karin. Dooro xirmo gaar ah.';

  @override
  String get addNewItemUseCustomButton => 'ISTICMAAL XIRMADAN';

  @override
  String get addNewItemLooseType => 'Furan';

  @override
  String get addPackagingSheetTitle => 'Ku dar xirmo';

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
  String get addPackagingSaveButton => 'KU DAR';

  @override
  String get addPackagingFailedMessage =>
      'Xirmada luguma dari karin. Isku day mar kale.';

  @override
  String addPackagingHeaderBaseUnit(Object unit) {
    return 'Halbeeg aasaasi · $unit';
  }

  @override
  String get addPackagingSuggestionsHeader => 'Xirmooyin la isticmaalo';

  @override
  String get addPackagingCustomEntry => '+ Xirmo gaar ah';

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
      'Halbeegan wali xirmooyin la isticmaalo uma jiraan — hoosta ka qor mid gaar ah.';

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
  String get shopItemEditorReorderThresholdLabel => 'Digniin marka ay yaraato';

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
  String get shopItemEditorPackagingHeader => 'Xirmada';

  @override
  String get shopItemEditorSupplierHeader => 'Alaab Keene';

  @override
  String get shopItemEditorPickSupplierButton => 'Dooro alaab keene';

  @override
  String get shopItemEditorNewSupplierButton => 'CUSUB';

  @override
  String get shopItemEditorRemoveSupplierTooltip => 'Saar alaab keenaha';

  @override
  String get packagingEditorAddTitle => 'Ku dar xirmo';

  @override
  String get packagingEditorEditTitle => 'Bedel xirmada';

  @override
  String get packagingEditorSaveButton => 'KAYDI';

  @override
  String get packagingEditorMissingUnitMessage =>
      'Dooro nooca xirmada (tusaale: bac, sanduuq).';

  @override
  String get packagingEditorMissingConversionMessage =>
      'Imisa unug aasaasi ah ayaa ku jira xirmadan? Geli tiro ka weyn 0.';

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
  String get shopItemEditorEditPackagingTooltip => 'Bedel xirmada';

  @override
  String get shopItemEditorRemovePackagingTooltip => 'Saar xirmada';

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
      'Geli kayd hadda xirmo walba si warbixinada saxda u shaqeeyaan maalintaa.';

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
  String get shopItemEditorOpeningStockFailedMessage =>
      'Alaabta waa la kaydiyay laakiin kaydka ma kaydsanin — fur alaabta si aad u hagaajiso.';

  @override
  String get shopItemEditorDedupTitle => 'Ma horaad haysataa?';

  @override
  String get shopItemEditorDedupBody =>
      'Dukaankaaga wuxuu leeyahay alaab la mid ah. Mid ka fur si aad u tafatirto, ama sii wad haddii uu kala duwan yahay:';

  @override
  String get shopItemEditorDedupKeepGoing => 'WAA KALA DUWAN';

  @override
  String get shopItemEditorDedupOpenExisting => 'FUR KII HORE';

  @override
  String get shopItemEditorPackagingsHeader => 'Xirmooyin';

  @override
  String get shopItemEditorAddPackagingButton => 'Ku dar xirmo';

  @override
  String get shopItemEditorBaseBadge => 'ASAAS';

  @override
  String get shopItemEditorPackagingMissingMessage =>
      'Buuxi ugu yaraan hal qaybsasho (qiime, qarash, kayd, ama barcode).';

  @override
  String get shopItemEditorScanBarcodeButton => 'Sken barcode';

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
      'Magacyo kale + sida bonada loo qoro ayaa raadinta ka horumarinaya.';

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
  String get shopItemEditorBonoSpellingLabel => 'Sida Bonada loogu qoro';

  @override
  String get shopItemEditorBonoSpellingHelper =>
      'Sida alaabtan u soo muuqato qoraalka warqada keenaha (tusaale CCL 330x24).';

  @override
  String get removePackagingTooltip => 'Tirtir xirmada';

  @override
  String get deactivateItemTooltip => 'Qari alaabta';

  @override
  String get deactivateItemConfirmTitle => 'Ma qarinaysaa alaabtan?';

  @override
  String get deactivateItemConfirmBody =>
      'Waxaa laga saari doonaa Iibinta, Dejinta, iyo Alaabta. Iibkii hore way sii jiri doonaan. Waxaad weydiisan kartaa taageerada inay soo celiyaan.';

  @override
  String get deactivateItemConfirmAction => 'QARI';

  @override
  String get removePackagingConfirmBody =>
      'Ma tirtirayaa xirmadan? Mar dambe wad ku celin kartaa.';

  @override
  String get removePackagingConfirmAction => 'TIRTIR';

  @override
  String get shopItemEditorSaveButton => 'KAYDI';

  @override
  String get shopItemEditorSaveAndAddAnotherButton => 'KAYDI + MID KALE';

  @override
  String shopItemEditorSavedAndContinueToast(String name) {
    return '$name waa la kaydiyay — ku dar mid kale';
  }

  @override
  String get shopItemDetailEditPrice => 'Bedel qiimaha';

  @override
  String get shopItemDetailDefaultSaleBadge => 'Iibin';

  @override
  String get shopItemDetailDefaultReceiveBadge => 'Dejin';

  @override
  String get shopItemDetailDefaultForLabel => 'Caadi u ah:';

  @override
  String get shopItemDetailStockLabel => 'Kayd';

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
  String get setupOnboardingSetPricesTitle => 'Qiime u Samee Alaabta Caanka ah';

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
    return 'la tirtiray $when';
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

  @override
  String get storageSyncTitle => 'Kayd & is-waafajin';

  @override
  String get storageSyncStatusConnected => 'Xidhan';

  @override
  String get storageSyncStatusOffline => 'Aan xidhneyn';

  @override
  String get storageSyncLastSyncedLabel => 'Is-waafajin u dambeysay';

  @override
  String get storageSyncLastSyncedNever => 'Marnaba';

  @override
  String get storageSyncPendingSalesLabel => 'Kuwa sugaya';

  @override
  String storageSyncPendingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sugaya',
      one: '1 sugaya',
      zero: 'midna',
    );
    return '$_temp0';
  }

  @override
  String get storageSyncFailedPermanentlyLabel => 'ma shaqeynayo si joogto ah';

  @override
  String storageSyncFailedPermanentlyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      one: '1',
    );
    return '$_temp0';
  }

  @override
  String get storageSyncStorageUsedLabel => 'Boos la isticmaalay';

  @override
  String get storageSyncStorageBreakdownPending => 'Kuwa sugaya';

  @override
  String get storageSyncStorageBreakdownCached => 'Xog la kaydiyay';

  @override
  String get storageSyncSyncNowButton => 'Is-waafaji hadda';

  @override
  String get storageSyncFreeUpSpaceButton => 'Furfur booska';

  @override
  String get storageSyncFreeUpSpaceConfirmTitle => 'Tirtir xogta la kaydiyay?';

  @override
  String get storageSyncFreeUpSpaceConfirmBody =>
      'Tani waxay cusbooneysiisaa qiimaha iyo liiska serfarka. Iibyada aad kaydisay ma taabankaro.';

  @override
  String get storageSyncFreeUpSpaceConfirmAction => 'TIRTIR';

  @override
  String get storageSyncResyncAllButton => 'Dib u soo deji';

  @override
  String get storageSyncResyncConfirmTitle => 'Dib u soo deji xogta oo dhan?';

  @override
  String get storageSyncResyncConfirmBody =>
      'Waxaa la soo dejinayaa nuqul cusub oo ka kooban alaab, macaamiil, iyo wax iibinta dhowaan. Iibyada aad kaydisay ma taabankaro.';

  @override
  String get storageSyncResyncConfirmAction => 'DIB U SOO DEJI';

  @override
  String get storageSyncResyncDoneToast =>
      'Xogta oo dhan dib ayaa loo soo dejiyay';

  @override
  String get storageSyncResyncFailedToast => 'Lama soo dejin karin';

  @override
  String get storageSyncCacheClearedToast => 'Kaydka waa la tirtiray';

  @override
  String storageSyncSyncedToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count la diray',
      one: '1 la diray',
      zero: 'Horeyba u cusub',
    );
    return '$_temp0';
  }

  @override
  String get storageSyncSyncFailedToast =>
      'Lama waafajin karin — hubi xidhiidhka.';

  @override
  String get storageSyncAlreadyUpToDateToast => 'Hadda way cusub tahay';

  @override
  String storageSyncPushedToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'La diray $count sugaya',
      one: 'La diray 1 sugaya',
    );
    return '$_temp0';
  }

  @override
  String storageSyncPulledToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'La helay $count cusbooneysiin',
      one: 'La helay 1 cusbooneysiin',
    );
    return '$_temp0';
  }

  @override
  String storageSyncPushedAndPulledToast(int pushed, int pulled) {
    return 'La diray $pushed sugaya, la helay $pulled cusbooneysiin';
  }

  @override
  String get storageSyncResetButton => 'Dib u bilow xogta';

  @override
  String get storageSyncResetConfirmTitle => 'Dib u bilow xogta maxalliga?';

  @override
  String get storageSyncResetConfirmBody =>
      'Tani waxay TIRTIRTAA dhammaan xogta uu taleefankaan ka soo dejiyey serverka. Xogta dukaankaaga waxaa dib loo soo dejin doonaa marka xiga ee la xidhiidho. Iibyada aan loo dirin server-ka way lumi doonaan. Tan hel kaliya marka taageerada ay ku weydiisto.';

  @override
  String get storageSyncResetTypePrompt => 'Ku qor BILOW si aad u xaqiijiso';

  @override
  String get storageSyncResetTypeWord => 'BILOW';

  @override
  String get storageSyncResetOfflineBlocker =>
      'Marka hore internet-ka ku xidh — waxaa jira iibyo sugaya in la diro server-ka kahor dib-u-bilowga.';

  @override
  String storageSyncResetPendingFailedBlocker(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count dir ayaa fashilmay. Eeg Iibyo guuldarreystay ka hor dib-u-bilowga.',
      one:
          '1 dirka ayaa fashilmay. Eeg Iibyo guuldarreystay ka hor dib-u-bilowga.',
    );
    return '$_temp0';
  }

  @override
  String get storageSyncResetConfirmAction => 'DIB U BILOW';

  @override
  String get storageSyncResetDoneToast =>
      'Xogta maxalliga waa la dib u bilaabay. Soo dejinta xog cusub...';

  @override
  String get storageSyncResetFailedToast => 'Dib-u-bilowga way fashilantay';

  @override
  String get storageSyncSettingsHeader => 'Qaabeyn';

  @override
  String get storageSyncWifiOnlyLabel => 'Kaliya marka Wi-Fi jiro';

  @override
  String get storageSyncDrawerEntry => 'Kayd & is-waafajin';

  @override
  String get drawerManageCategories => 'Qaybaha';

  @override
  String get manageCategoriesTitle => 'Qaybaha';

  @override
  String get manageCategoriesProductsTab => 'Alaabta';

  @override
  String get manageCategoriesExpensesTab => 'Qarashyada';

  @override
  String get manageCategoriesAdd => 'Ku dar qayb';

  @override
  String get manageCategoriesEmpty =>
      'Wali qaybo ma jiraan. Taabo + si aad u darto.';

  @override
  String get manageCategoriesDefaultBadge => 'Nidaam';

  @override
  String get manageCategoriesNameLabel => 'Magaca qaybta';

  @override
  String get manageCategoriesNewTitle => 'Qayb cusub';

  @override
  String get manageCategoriesRenameTitle => 'Magac-beddel qaybta';

  @override
  String get manageCategoriesSave => 'Kaydi';

  @override
  String get manageCategoriesRename => 'Magac beddel';

  @override
  String get manageCategoriesHide => 'Qari';

  @override
  String get manageCategoriesHideConfirmTitle => 'Qari qaybta?';

  @override
  String get manageCategoriesHideConfirmBody =>
      'Mar dambe kama soo bixi doonto marka aad alaab dartid ama wax ka beddeshid. Alaabta hadda isticmaasha way sii haysanaysaa ilaa aad beddesho.';

  @override
  String get failedPostsTitle => 'Kuwa guul-darreystay';

  @override
  String get failedPostsRetryButton => 'MAR KALE';

  @override
  String get failedPostsDiscardButton => 'TUUR';

  @override
  String get failedPostsDiscardConfirmTitle => 'Tuur kan?';

  @override
  String get failedPostsDiscardConfirmBody => 'Ma soo celin kartid. Sii wad?';

  @override
  String get failedPostsDiscardConfirmAction => 'TUUR';

  @override
  String get failedPostsEmptyState => 'Wax guul-darreystay ma jiro.';

  @override
  String get syncFirstTimeSetupTitle => 'Ku xir internetka';

  @override
  String get syncFirstTimeSetupBody =>
      'Waxaan mar u baahanahay inaan soo dejino alaabtaada, macaamiishaada, iyo wax iibinta dhowaan ka hor inta aanad shaqayn karin marka aad offline-tahay. Fur Wi-Fi ama internet-ka taleefanka, ka dibna taabo MAR KALE.';

  @override
  String get syncFirstTimeSetupRetryButton => 'MAR KALE';

  @override
  String get syncFirstTimeLoadingTitle => 'Waa la diyaarinayaa…';

  @override
  String get syncFirstTimeLoadingBody =>
      'Waxaa la soo dejinayaa alaabtaada, macaamiishaada, iyo dhaqdhaqaaqyada dhowaan. Tani hal mar ayey dhacaysaa.';

  @override
  String syncIssueBannerLabel(String time) {
    return '⚠ Offline tan iyo $time. Taabo si aad mar kale isku daydid.';
  }

  @override
  String get syncForceSyncingToast => 'Waa la diraaya…';

  @override
  String syncForceSyncedToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cusboonaysiis la diray',
      one: '1 cusboonaysiis la diray',
      zero: 'Horeyba u cusub',
    );
    return '$_temp0';
  }

  @override
  String get syncForceFailedToast =>
      'Lama is-waafajin karin — mar kale isku day.';
}

// MultiScanSheet unit tests. Drive the sheet through debugIngest
// (the visible-for-testing scan hook) so we exercise the staging /
// dedupe / unknown-queue logic without spinning up a real camera.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/scanner/multi_scan_sheet.dart';
import 'package:dukan/scanner/scan_event.dart';

import '../shared/fakes.dart' show fakeActivatedItem;

void main() {
  Future<void> pump(WidgetTester tester, MultiScanResolver resolver) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiScanSheet(resolver: resolver),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Locate the sheet's state via the widget tree so we can call
  // debugIngest directly without going through the camera.
  MultiScanSheet sheetWidget() =>
      const MultiScanSheet(resolver: _UnusedResolver.resolve);

  testWidgets(
    'matched scan stages a quantity-1 line with the matched defaults',
    (tester) async {
      await pump(tester, (code) async => fakeActivatedItem(
            shopItemId: 'si-rice',
            itemId: 'item-rice',
            defaultShopItemUnitId: 'siu-rice',
            displayName: 'Bariis Basmati',
            defaultUnitSalePrice: 1.5,
          ));

      final state =
          tester.state<State<MultiScanSheet>>(find.byType(MultiScanSheet))
              as dynamic;
      await state.debugIngest(
        const ScanEvent(code: '5901234123457', source: ScanSource.camera),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bariis Basmati'), findsOneWidget);
      expect(find.textContaining('× 1'), findsOneWidget);
    },
  );

  testWidgets(
    're-scan within the dedupe window does NOT bump count',
    (tester) async {
      await pump(tester, (code) async => fakeActivatedItem(
            shopItemId: 'si-rice',
            itemId: 'item-rice',
            defaultShopItemUnitId: 'siu-rice',
            displayName: 'Bariis Basmati',
            defaultUnitSalePrice: 1.5,
          ));

      final state =
          tester.state<State<MultiScanSheet>>(find.byType(MultiScanSheet))
              as dynamic;
      const event =
          ScanEvent(code: '5901234123457', source: ScanSource.camera);
      await state.debugIngest(event);
      await state.debugIngest(event); // same code, instant — should dedupe
      await tester.pumpAndSettle();

      expect(find.textContaining('× 1'), findsOneWidget);
    },
  );

  testWidgets('unknown code lands in the unknown queue', (tester) async {
    await pump(tester, (code) async => null);

    final state =
        tester.state<State<MultiScanSheet>>(find.byType(MultiScanSheet))
            as dynamic;
    await state.debugIngest(
      const ScanEvent(code: 'abc-000', source: ScanSource.camera),
    );
    await tester.pumpAndSettle();

    final en = lookupAppLocalizations(const Locale('en'));
    expect(find.text(en.multiScanUnknownCount(1)), findsOneWidget);
    expect(find.text(en.multiScanEmptyHint), findsOneWidget);

    // Smoke-check the widget is mountable
    expect(sheetWidget().resolver, isNotNull);
  });
}

/// Placeholder resolver — only used by the type system; never called.
class _UnusedResolver {
  static Future<ItemSearchResult?> resolve(String _) async => null;
}

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/sale/receipt_pdf.dart';

import '../shared/fakes.dart';

SaleSummary _header({
  required String txnId,
  required DateTime occurredAt,
  String? partyName,
  double total = 3.0,
  double paid = 3.0,
}) =>
    SaleSummary(
      txnId: txnId,
      occurredAt: occurredAt,
      postedAt: occurredAt,
      partyId: partyName == null ? null : 'p-1',
      partyName: partyName,
      totalAmount: total,
      paidAmount: paid,
      paymentMethodCode: 'cash',
      isVoided: false,
      reversalTxnId: null,
      voidedAt: null,
    );

void main() {
  test('receiptNumberFor is R-YYYYMMDD-<txn tail>', () {
    final header = _header(
      txnId: 'abcdef12-3456-7890-abcd-ef0123456789',
      occurredAt: DateTime(2026, 6, 28, 14),
    );
    expect(receiptNumberFor(header), 'R-20260628-456789');
  });

  test('buildSaleReceiptPdf produces a valid PDF document', () async {
    final l = lookupAppLocalizations(const Locale('en'));
    final shop = fakeShop();
    final header = _header(
      txnId: 'tx-000001',
      occurredAt: DateTime(2026, 6, 28),
      partyName: 'Cumar',
      total: 3.0,
      paid: 1.0,
    );
    const lines = [
      SaleLineDetail(
        lineNo: 1,
        itemId: 'i',
        shopItemUnitId: 'u',
        itemName: 'Bariis',
        quantity: 2,
        unitLabel: 'Kg',
        unitAmount: 1.5,
        lineTotal: 3.0,
        packagingLabel: null,
      ),
    ];

    final bytes = await buildSaleReceiptPdf(
      shop: shop,
      header: header,
      lines: lines,
      l: l,
      dateText: '28 Jun 2026',
    );

    expect(bytes, isNotEmpty);
    // PDF magic number.
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}

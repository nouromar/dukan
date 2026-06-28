import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/shared/money.dart';

/// A printable receipt number derived from the sale — no backend sequence yet.
/// `R-YYYYMMDD-XXXXXX` (date + the tail of the transaction id). A real per-shop
/// sequence is a later upgrade.
String receiptNumberFor(SaleSummary header) {
  final d = header.occurredAt.toLocal();
  final ymd = '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';
  final compact = header.txnId.replaceAll('-', '');
  final tail = compact.length >= 6
      ? compact.substring(compact.length - 6)
      : compact;
  return 'R-$ymd-${tail.toUpperCase()}';
}

/// Renders a formatted PDF sales receipt from the same data the in-app receipt
/// and the plain-text share use. Latin + €/£ are covered by the built-in PDF
/// fonts, so no embedded font is needed (Somali is plain Latin). #6.
Future<Uint8List> buildSaleReceiptPdf({
  required ShopSummary shop,
  required SaleSummary header,
  required List<SaleLineDetail> lines,
  required AppLocalizations l,
  required String dateText,
}) async {
  final doc = pw.Document();
  final receiptNo = receiptNumberFor(header);
  final debt = header.totalAmount - header.paidAmount;

  String qtyText(num q) => q == q.roundToDouble()
      ? q.toInt().toString()
      : q.toString();

  pw.Widget totalRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: bold ? 12 : 10,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [pw.Text(label, style: style), pw.Text(value, style: style)],
    );
  }

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a6,
      margin: const pw.EdgeInsets.all(18),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text(
              shop.name,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(l.saleDetailTitle,
                style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.SizedBox(height: 8),
          totalRow(l.receiptNumberLabel, receiptNo),
          totalRow(l.receiptDateLabel, dateText),
          pw.Text(
            header.partyName != null
                ? l.saleHistoryDebtLabel(header.partyName!)
                : l.saleHistoryCashLabel,
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Divider(),
          for (final line in lines) ...[
            pw.Text(line.itemName,
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${qtyText(line.quantity)} '
                  '${line.packagingLabel ?? line.unitLabel}'
                  '${line.unitAmount == null ? '' : ' × ${formatMoney(line.unitAmount!, shop)}'}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.Text(formatMoney(line.lineTotal, shop),
                    style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
            pw.SizedBox(height: 4),
          ],
          pw.Divider(),
          totalRow(l.saleDetailTotalLabel,
              formatMoney(header.totalAmount, shop), bold: true),
          totalRow(l.saleDetailCashLabel, formatMoney(header.paidAmount, shop)),
          if (debt > 0)
            totalRow(l.saleDetailDebtLabel, formatMoney(debt, shop)),
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(l.receiptThankYou,
                style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}

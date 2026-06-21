// Dispatches a PendingPost to the corresponding ShopApi method.
// Decoupled from OfflineQueueController so the controller can be
// unit-tested with a stub executor and the executor can be unit-
// tested with a real ShopApi + fake Supabase client.
//
// Phase 1 wired post_sale. Phase 5B (#367) adds post_receive,
// post_payment, and post_expense so all four daily-flow posting
// RPCs queue on transient failure.

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/queue/pending_post.dart';

class PostExecutor {
  PostExecutor(this._api);

  final ShopApi _api;

  Future<void> execute(PendingPost post) async {
    switch (post.rpc) {
      case 'post_sale':
        await _executeSale(post);
      case 'post_receive':
        await _executeReceive(post);
      case 'post_payment':
        await _executePayment(post);
      case 'post_expense':
        await _executeExpense(post);
      default:
        throw UnsupportedError(
          'OfflineQueue does not yet know how to retry ${post.rpc}',
        );
    }
  }

  Future<void> _executeSale(PendingPost post) async {
    final p = post.params;
    final lines = (p['lines'] as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .map((m) => SaleLine(
              shopItemUnitId: m['shop_item_unit_id'] as String,
              quantity: (m['quantity'] as num),
              unitPrice: (m['unit_price'] as num),
            ))
        .toList(growable: false);
    await _api.postSale(
      shopId: post.shopId,
      lines: lines,
      paidAmount: (p['paid_amount'] as num),
      partyId: p['party_id'] as String?,
      paymentMethodCode: p['payment_method_code'] as String?,
      clientOpId: post.clientOpId,
    );
  }

  Future<void> _executeReceive(PendingPost post) async {
    final p = post.params;
    final lines = (p['lines'] as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .map((m) => ReceiveLinePayload(
              shopItemUnitId: m['shop_item_unit_id'] as String,
              quantity: (m['quantity'] as num),
              lineTotal: (m['line_total'] as num),
            ))
        .toList(growable: false);
    await _api.postReceive(
      shopId: post.shopId,
      partyId: p['party_id'] as String,
      lines: lines,
      paidAmount: (p['paid_amount'] as num),
      paymentMethodCode: p['payment_method_code'] as String?,
      documentId: p['document_id'] as String?,
      clientOpId: post.clientOpId,
      notes: p['notes'] as String?,
    );
  }

  Future<void> _executePayment(PendingPost post) async {
    final p = post.params;
    final rawAllocs = p['allocations'];
    final allocations = rawAllocs is List
        ? rawAllocs
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .map((m) => PaymentAllocationInput(
                  transactionId: m['transaction_id'] as String,
                  amount: (m['amount'] as num),
                ))
            .toList(growable: false)
        : null;
    await _api.postPayment(
      shopId: post.shopId,
      partyId: p['party_id'] as String,
      direction: p['direction'] as String,
      amount: (p['amount'] as num),
      paymentMethodCode: p['payment_method_code'] as String,
      clientOpId: post.clientOpId,
      notes: p['notes'] as String?,
      allocations: allocations,
    );
  }

  Future<void> _executeExpense(PendingPost post) async {
    final p = post.params;
    await _api.postExpense(
      shopId: post.shopId,
      expenseCategoryId: p['expense_category_id'] as String,
      amount: (p['amount'] as num),
      paymentMethodCode: p['payment_method_code'] as String,
      clientOpId: post.clientOpId,
      notes: p['notes'] as String?,
    );
  }
}

/// Helper that builds the params map for a post_sale enqueue. Lives
/// here so the screen call sites stay simple and the schema is
/// shared with the executor that reads it.
Map<String, dynamic> buildPostSaleParams({
  required List<SaleLine> lines,
  required num paidAmount,
  String? partyId,
  String? paymentMethodCode,
}) =>
    <String, dynamic>{
      'lines': lines
          .map((l) => {
                'shop_item_unit_id': l.shopItemUnitId,
                'quantity': l.quantity,
                'unit_price': l.unitPrice,
              })
          .toList(growable: false),
      'paid_amount': paidAmount,
      if (partyId != null) 'party_id': partyId,
      if (paymentMethodCode != null) 'payment_method_code': paymentMethodCode,
    };

Map<String, dynamic> buildPostReceiveParams({
  required String partyId,
  required List<ReceiveLinePayload> lines,
  required num paidAmount,
  String? paymentMethodCode,
  String? documentId,
  String? notes,
}) =>
    <String, dynamic>{
      'party_id': partyId,
      'lines': lines
          .map((l) => {
                'shop_item_unit_id': l.shopItemUnitId,
                'quantity': l.quantity,
                'line_total': l.lineTotal,
              })
          .toList(growable: false),
      'paid_amount': paidAmount,
      if (paymentMethodCode != null) 'payment_method_code': paymentMethodCode,
      if (documentId != null) 'document_id': documentId,
      if (notes != null) 'notes': notes,
    };

Map<String, dynamic> buildPostPaymentParams({
  required String partyId,
  required String direction,
  required num amount,
  required String paymentMethodCode,
  String? notes,
  List<PaymentAllocationInput>? allocations,
}) =>
    <String, dynamic>{
      'party_id': partyId,
      'direction': direction,
      'amount': amount,
      'payment_method_code': paymentMethodCode,
      if (notes != null) 'notes': notes,
      if (allocations != null && allocations.isNotEmpty)
        'allocations': allocations
            .map((a) => {
                  'transaction_id': a.transactionId,
                  'amount': a.amount,
                })
            .toList(growable: false),
    };

Map<String, dynamic> buildPostExpenseParams({
  required String expenseCategoryId,
  required num amount,
  required String paymentMethodCode,
  String? notes,
}) =>
    <String, dynamic>{
      'expense_category_id': expenseCategoryId,
      'amount': amount,
      'payment_method_code': paymentMethodCode,
      if (notes != null) 'notes': notes,
    };
// ignore_for_file: use_null_aware_elements

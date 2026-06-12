// Dispatches a PendingPost to the corresponding ShopApi method.
// Decoupled from OfflineQueueController so the controller can be
// unit-tested with a stub executor and the executor can be unit-
// tested with a real ShopApi + fake Supabase client.
//
// Phase 1 covers post_sale only. Receive / Payment / Expense ship
// as one-liner additions to the switch when the screens are wired.

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
// ignore_for_file: use_null_aware_elements

// PostExecutor dispatch — confirms each rpc string routes to the
// matching ShopApi wrapper with the params reconstructed from the
// serialized payload. Phase 1 covered post_sale; Phase 5B (#367)
// added post_receive / post_payment / post_expense.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/receive/bono_image_cache.dart';

import '../shared/fakes.dart';
import '../shared/test_database.dart';

PendingPost _post(String rpc, Map<String, dynamic> params) => PendingPost(
      id: 'id-1',
      clientOpId: 'op-1',
      shopId: 'shop-1',
      originalActorUserId: 'user-A',
      rpc: rpc,
      params: params,
      queuedAt: DateTime.utc(2026, 6, 21, 12, 0, 0),
    );

void main() {
  late FakeShopApi api;
  late PostExecutor executor;

  setUp(() {
    api = FakeShopApi();
    executor = PostExecutor(api);
  });

  test('post_sale dispatches with reconstructed lines + clientOpId',
      () async {
    String? capturedClientOp;
    List<SaleLine>? capturedLines;
    api.onPostSale = (shop, lines, paid, party, method, clientOp, notes) async {
      capturedClientOp = clientOp;
      capturedLines = lines;
      return 'sale-txn-1';
    };
    await executor.execute(_post(
      'post_sale',
      buildPostSaleParams(
        lines: const [
          SaleLine(shopItemUnitId: 'unit-a', quantity: 2, unitPrice: 5),
        ],
        paidAmount: 10,
        partyId: null,
        paymentMethodCode: 'cash',
        txnId: 'sale-uuid-1',
      ),
    ));
    expect(capturedClientOp, 'op-1');
    expect(capturedLines, isNotNull);
    expect(capturedLines!.single.shopItemUnitId, 'unit-a');
    expect(capturedLines!.single.quantity, 2);
    expect(capturedLines!.single.unitPrice, 5);
    // The client-minted txn id round-trips through builder + dispatch.
    expect(api.postSaleTxnIds.last, 'sale-uuid-1');
  });

  test('post_receive dispatches with reconstructed lines + bono docId',
      () async {
    String? capturedClientOp;
    String? capturedDocId;
    List<ReceiveLinePayload>? capturedLines;
    api.onPostReceive =
        (shop, party, lines, paid, method, docId, clientOp, notes) async {
      capturedClientOp = clientOp;
      capturedDocId = docId;
      capturedLines = lines;
      return 'recv-txn-1';
    };
    await executor.execute(_post(
      'post_receive',
      buildPostReceiveParams(
        partyId: 'supplier-1',
        lines: const [
          ReceiveLinePayload(
            shopItemUnitId: 'unit-bag',
            quantity: 3,
            lineTotal: 150,
          ),
        ],
        paidAmount: 0,
        documentId: 'doc-bono-1',
        txnId: 'recv-uuid-1',
      ),
    ));
    expect(capturedClientOp, 'op-1');
    expect(capturedDocId, 'doc-bono-1');
    expect(capturedLines, isNotNull);
    expect(capturedLines!.single.shopItemUnitId, 'unit-bag');
    expect(capturedLines!.single.quantity, 3);
    expect(capturedLines!.single.lineTotal, 150);
    // The client-minted txn id round-trips through builder + dispatch.
    expect(api.postReceiveTxnIds.last, 'recv-uuid-1');
  });

  test('post_payment dispatches with reconstructed allocations',
      () async {
    String? capturedClientOp;
    List<PaymentAllocationInput>? capturedAllocs;
    api.onPostPayment = (shop, party, dir, amount, method, clientOp, notes, allocs) async {
      capturedClientOp = clientOp;
      capturedAllocs = allocs;
      return 'pay-txn-1';
    };
    await executor.execute(_post(
      'post_payment',
      buildPostPaymentParams(
        partyId: 'party-1',
        direction: 'I',
        amount: 50,
        paymentMethodCode: 'cash',
        paymentId: 'pay-uuid-1',
        allocations: const [
          PaymentAllocationInput(transactionId: 'txn-1', amount: 30),
          PaymentAllocationInput(transactionId: 'txn-2', amount: 20),
        ],
      ),
    ));
    expect(capturedClientOp, 'op-1');
    expect(capturedAllocs, isNotNull);
    expect(capturedAllocs!.length, 2);
    expect(capturedAllocs![0].transactionId, 'txn-1');
    expect(capturedAllocs![0].amount, 30);
    // The client-minted payment id round-trips through builder + dispatch.
    expect(api.postPaymentTxnIds.last, 'pay-uuid-1');
  });

  test('post_payment without allocations passes null', () async {
    List<PaymentAllocationInput>? capturedAllocs;
    api.onPostPayment = (shop, party, dir, amount, method, clientOp, notes, allocs) async {
      capturedAllocs = allocs;
      return 'pay-txn-1';
    };
    await executor.execute(_post(
      'post_payment',
      buildPostPaymentParams(
        partyId: 'party-1',
        direction: 'O',
        amount: 100,
        paymentMethodCode: 'cash',
      ),
    ));
    expect(capturedAllocs, isNull);
  });

  test('post_expense dispatches with category + amount', () async {
    String? capturedClientOp;
    String? capturedCategory;
    num? capturedAmount;
    api.onPostExpense = (shop, category, amount, method, clientOp, notes) async {
      capturedClientOp = clientOp;
      capturedCategory = category;
      capturedAmount = amount;
      return 'exp-txn-1';
    };
    await executor.execute(_post(
      'post_expense',
      buildPostExpenseParams(
        expenseCategoryId: 'cat-rent',
        amount: 200,
        paymentMethodCode: 'cash',
        notes: 'July rent',
        txnId: 'exp-uuid-1',
      ),
    ));
    expect(capturedClientOp, 'op-1');
    expect(capturedCategory, 'cat-rent');
    expect(capturedAmount, 200);
    // The client-minted txn id round-trips through the builder + dispatch so
    // the queued post reuses the optimistic mirror's id (offline-void support).
    expect(api.postExpenseTxnIds.last, 'exp-uuid-1');
  });

  test('void_sale dispatches txn + refund + clientOpId', () async {
    await executor.execute(_post(
      'void_sale',
      buildVoidSaleParams(txnId: 'txn-99', refundAmount: 3.5),
    ));
    expect(api.voidSaleCalls, hasLength(1));
    expect(api.voidSaleCalls.first.txnId, 'txn-99');
    expect(api.voidSaleCalls.first.refundAmount, 3.5);
  });

  test('void_sale without a refund passes null', () async {
    await executor.execute(_post(
      'void_sale',
      buildVoidSaleParams(txnId: 'txn-100'),
    ));
    expect(api.voidSaleCalls.single.refundAmount, isNull);
  });

  test('void_receive / void_payment / void_expense dispatch by id', () async {
    await executor.execute(
        _post('void_receive', buildVoidReceiveParams(txnId: 'rcv-1')));
    await executor.execute(
        _post('void_payment', buildVoidPaymentParams(paymentId: 'pay-1')));
    await executor.execute(
        _post('void_expense', buildVoidExpenseParams(txnId: 'exp-1')));
    expect(api.voidReceiveCalls, ['rcv-1']);
    expect(api.voidPaymentCalls, ['pay-1']);
    expect(api.voidExpenseCalls, ['exp-1']);
  });

  test('unknown rpc throws UnsupportedError', () async {
    await expectLater(
      executor.execute(_post('post_unknown', const {})),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test(
      '#368 after successful drain, setAuditOriginalActor is called '
      'with the post.originalActorUserId + the returned transaction id',
      () async {
    api.onPostSale = (shop, lines, paid, party, method, clientOp, notes) async {
      return 'sale-txn-stamped';
    };
    await executor.execute(_post(
      'post_sale',
      buildPostSaleParams(
        lines: const [
          SaleLine(shopItemUnitId: 'unit-a', quantity: 1, unitPrice: 5),
        ],
        paidAmount: 5,
        paymentMethodCode: 'cash',
      ),
    ));
    expect(api.setAuditOriginalActorCalls, hasLength(1));
    final call = api.setAuditOriginalActorCalls.single;
    expect(call.shopId, 'shop-1');
    expect(call.entityId, 'sale-txn-stamped');
    expect(call.originalActorUserId, 'user-A');
  });

  test(
      '#368 audit-stamp skipped when post has no originator stamp',
      () async {
    api.onPostSale = (shop, lines, paid, party, method, clientOp, notes) async {
      return 'sale-txn-bare';
    };
    final bare = PendingPost(
      id: 'id-bare',
      clientOpId: 'op-bare',
      shopId: 'shop-1',
      originalActorUserId: '', // empty = no originator captured
      rpc: 'post_sale',
      params: buildPostSaleParams(
        lines: const [
          SaleLine(shopItemUnitId: 'unit-a', quantity: 1, unitPrice: 5),
        ],
        paidAmount: 5,
        paymentMethodCode: 'cash',
      ),
      queuedAt: DateTime.utc(2026, 6, 21, 12, 0, 0),
    );
    await executor.execute(bare);
    expect(api.setAuditOriginalActorCalls, isEmpty);
  });

  test('upload_bono_image uploads the cached bytes then marks uploaded', () async {
    final db = await openTestDatabase();
    final cache = BonoImageCache(database: Future.value(db));
    await cache.put(
      documentId: 'doc-9',
      shopId: 'shop-1',
      ext: 'jpg',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
    );
    final exec = PostExecutor(api, bonoCache: cache);

    await exec.execute(_post('upload_bono_image', {
      'document_id': 'doc-9',
      'storage_path': 'shop-1/documents/doc-9/image.jpg',
      'mime_type': 'image/jpeg',
      'size_bytes': 4,
    }));

    expect(api.uploadBonoImageAtCalls, hasLength(1));
    final call = api.uploadBonoImageAtCalls.single;
    expect(call.documentId, 'doc-9');
    expect(call.storagePath, 'shop-1/documents/doc-9/image.jpg');
    expect(call.sizeBytes, 4);
    // Cached entry is now marked uploaded (kept, not deleted).
    final row = (await db.db.query('local_bono',
            where: 'document_id = ?', whereArgs: ['doc-9']))
        .single;
    expect(row['uploaded'], 1);
  });

  test('upload_bono_image with the cached bytes gone is a no-op', () async {
    final db = await openTestDatabase();
    final cache = BonoImageCache(database: Future.value(db));
    final exec = PostExecutor(api, bonoCache: cache);
    await exec.execute(_post('upload_bono_image', {
      'document_id': 'gone',
      'storage_path': 'p',
      'mime_type': 'image/jpeg',
      'size_bytes': 0,
    }));
    expect(api.uploadBonoImageAtCalls, isEmpty);
  });
}

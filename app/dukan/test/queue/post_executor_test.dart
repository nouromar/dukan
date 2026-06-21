// PostExecutor dispatch — confirms each rpc string routes to the
// matching ShopApi wrapper with the params reconstructed from the
// serialized payload. Phase 1 covered post_sale; Phase 5B (#367)
// added post_receive / post_payment / post_expense.

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/queue/post_executor.dart';

import '../shared/fakes.dart';

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
      ),
    ));
    expect(capturedClientOp, 'op-1');
    expect(capturedLines, isNotNull);
    expect(capturedLines!.single.shopItemUnitId, 'unit-a');
    expect(capturedLines!.single.quantity, 2);
    expect(capturedLines!.single.unitPrice, 5);
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
      ),
    ));
    expect(capturedClientOp, 'op-1');
    expect(capturedDocId, 'doc-bono-1');
    expect(capturedLines, isNotNull);
    expect(capturedLines!.single.shopItemUnitId, 'unit-bag');
    expect(capturedLines!.single.quantity, 3);
    expect(capturedLines!.single.lineTotal, 150);
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
      ),
    ));
    expect(capturedClientOp, 'op-1');
    expect(capturedCategory, 'cat-rent');
    expect(capturedAmount, 200);
  });

  test('unknown rpc throws UnsupportedError', () async {
    await expectLater(
      executor.execute(_post('post_unknown', const {})),
      throwsA(isA<UnsupportedError>()),
    );
  });
}

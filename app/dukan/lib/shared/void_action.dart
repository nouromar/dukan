// Shared dual-mode void: reverse a posted transaction directly while
// online, and fall back to the offline write queue on a transient
// failure. Used by the Sale / Receive / Payment / Expense detail screens.
//
// Every void RPC (void_sale / void_receive / void_payment / void_expense)
// is owner-gated and dedups its reversal on client_op_id server-side, so a
// re-drained void is a safe no-op — the queue can retry freely. The local
// `is_voided` flag is flipped optimistically so the receipt + history show
// the void before the drain syncs the authoritative payload back.
//
// - success  → optimistic void + onDone (toast / pop)
// - Postgrest (structured reject: outside window, not owner, later stock
//   activity…) → onFailure (surface it); nothing was voided
// - transient + useLocalDb → optimistic void + enqueue + onDone
// - transient + thin-client → onFailure (no queue to fall back on)

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/shared/client_op_id.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

Future<void> voidWithQueueFallback({
  required BuildContext context,
  required String shopId,
  // The local_transaction id to flip is_voided on (the txn id, or the
  // payment id — payments are mirrored with txn_id == payment id).
  required String optimisticTxnId,
  required String rpc,
  required Map<String, dynamic> params,
  required String clientOpId,
  required Future<void> Function() direct,
  required VoidCallback onDone,
  required void Function(Object error, StackTrace stackTrace) onFailure,
}) async {
  // Read before the awaits so an unmounted context can't break the mirror
  // write / enqueue.
  final queue = context.read<OfflineQueueController>();
  final repo = useLocalDb(context) ? context.read<LocalRepository>() : null;
  String actorId = '';
  try {
    actorId = Supabase.instance.client.auth.currentUser?.id ?? '';
  } catch (_) {}

  try {
    await direct();
    await repo?.applyOptimisticVoid(optimisticTxnId);
    onDone();
  } on PostgrestException catch (error, stackTrace) {
    onFailure(error, stackTrace);
  } catch (error, stackTrace) {
    if (repo == null) {
      onFailure(error, stackTrace);
      return;
    }
    await repo.applyOptimisticVoid(optimisticTxnId);
    await queue.enqueue(PendingPost(
      id: generateClientOpId('post'),
      clientOpId: clientOpId,
      shopId: shopId,
      originalActorUserId: actorId,
      rpc: rpc,
      params: params,
      queuedAt: DateTime.now(),
    ));
    onDone();
  }
}

// Headless, offline-robust item + packaging creation.
//
// Extracted from AddNewItemSheet._onSave so the "Add product" sheet AND the
// bono review's one-tap Create / Add-packaging share ONE create path:
//   * mint client-side ids (0094/0095) so the optimistic mirror row and the
//     server row share one id,
//   * optimistically mirror the row(s) + display alias so it's searchable +
//     selectable immediately,
//   * POST with an 8s timeout — after an idle app the radio can be asleep and
//     the call hangs; the timeout converts that into the transient path,
//   * on a transient failure (offline / network / timeout) enqueue with the
//     same client_op_id (server-side idempotency → no duplicate on drain),
//   * on a HARD reject (PostgrestException) surface an error and return null.
//
// Thin-client (no local mirror): a transient failure surfaces an error, since
// there's no queue to fall back on.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/sale/add_new_item_sheet.dart' show AddNewItemResult;
import 'package:dukan/shared/client_op_id.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/packaging_label.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

String _actorId() {
  try {
    return Supabase.instance.client.auth.currentUser?.id ?? '';
  } catch (_) {
    return '';
  }
}

/// Create a whole shop item (optionally with a distinct selling/receiving
/// packaging) from a draft. When [soldUnitCode] is set, `create_shop_item`'s
/// [defaultSide] split applies: the sold (pack) unit owns that side, the base
/// owns the other (0095) — e.g. `defaultSide: 'receive'` → pack default-receive,
/// base default-sale. Returns the result (real or optimistic/queued), or null
/// on a hard reject / thin-client transient failure (error already surfaced).
Future<AddNewItemResult?> createShopItemDraft(
  BuildContext context, {
  required ShopSummary shop,
  required String name,
  String? categoryId,
  required String baseUnitCode,
  required String baseUnitLabel,
  String? soldUnitCode,
  String? soldUnitLabel,
  num? soldConversion,
  num? salePrice,
  required String languageCode,
  required String defaultSide, // 'sale' | 'receive'
  required String errorMessage,
}) async {
  final api = context.read<ShopApi>();
  final queue = context.read<OfflineQueueController>();
  final repo = useLocalDb(context) ? context.read<LocalRepository>() : null;

  final baseOnly = soldUnitCode == null;
  final label = baseOnly
      ? baseUnitLabel
      : packagingLabel(soldConversion!, baseUnitLabel, soldUnitLabel!);

  final shopItemId = generateUuidV4();
  final baseUnitId = generateUuidV4();
  final soldUnitId = baseOnly ? null : generateUuidV4();
  final defaultUnitId = soldUnitId ?? baseUnitId;
  final itemOpId = generateClientOpId('item');
  final actorId = _actorId();

  // Mirror default flags mirror create_shop_item (0095): base-only → base is
  // default for both; packaged → the pack owns `defaultSide`, base owns the
  // other side.
  final baseDefaultSale = baseOnly || defaultSide == 'receive';
  final baseDefaultReceive = baseOnly || defaultSide == 'sale';
  final soldDefaultSale = !baseOnly && defaultSide == 'sale';
  final soldDefaultReceive = !baseOnly && defaultSide == 'receive';

  Future<void> writeMirror() async {
    if (repo == null) return;
    try {
      await repo.insertLocalShopItem(
        shopItemId: shopItemId,
        shopId: shop.id,
        displayName: name,
        baseUnitCode: baseUnitCode,
        categoryId: categoryId,
      );
      await repo.insertLocalShopItemUnit(
        shopItemUnitId: baseUnitId,
        shopItemId: shopItemId,
        unitCode: baseUnitCode,
        packagingLabel: baseUnitLabel,
        conversionToBase: 1,
        salePrice: baseOnly ? salePrice : null,
        isDefaultSale: baseDefaultSale,
        isDefaultReceive: baseDefaultReceive,
      );
      if (!baseOnly) {
        await repo.insertLocalShopItemUnit(
          shopItemUnitId: soldUnitId!,
          shopItemId: shopItemId,
          unitCode: soldUnitCode,
          packagingLabel: label,
          conversionToBase: soldConversion!,
          salePrice: salePrice,
          isDefaultSale: soldDefaultSale,
          isDefaultReceive: soldDefaultReceive,
        );
      }
      await repo.insertLocalShopItemAlias(
        shopItemId: shopItemId,
        aliasText: name,
        isDisplay: true,
      );
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'dukan item-creator',
        context: ErrorDescription('optimistic shop_item create mirror'),
      ));
    }
  }

  AddNewItemResult result() => AddNewItemResult(
        shopItemId: shopItemId,
        shopItemUnitId: defaultUnitId,
        displayName: name,
        packagingLabel: label,
        baseUnitCode: baseUnitCode,
        baseUnitLabel: baseUnitLabel,
        salePrice: salePrice,
      );

  try {
    await api
        .createShopItem(
          shopId: shop.id,
          name: name,
          languageCode: languageCode,
          baseUnitCode: baseUnitCode,
          salePrice: salePrice,
          categoryId: categoryId,
          soldUnitCode: soldUnitCode,
          soldConversion: soldConversion,
          defaultSide: defaultSide,
          shopItemId: shopItemId,
          baseUnitId: baseUnitId,
          soldUnitId: soldUnitId,
          clientOpId: itemOpId,
        )
        .timeout(const Duration(seconds: 8));
    await writeMirror();
    return result();
  } on PostgrestException catch (error, st) {
    _report(error, st, 'create_shop_item');
    if (context.mounted) showError(context, errorMessage);
    return null;
  } catch (error, st) {
    // Transient (offline / network / timeout). Thin-client → surface; with a
    // mirror → queue silently (expected offline, not Sentry-worthy).
    if (repo == null) {
      _report(error, st, 'create_shop_item');
      if (context.mounted) showError(context, errorMessage);
      return null;
    }
    await writeMirror();
    await queue.enqueue(PendingPost(
      id: generateClientOpId('post'),
      clientOpId: itemOpId,
      shopId: shop.id,
      originalActorUserId: actorId,
      rpc: 'create_shop_item',
      params: buildCreateShopItemParams(
        shopItemId: shopItemId,
        baseUnitId: baseUnitId,
        name: name,
        languageCode: languageCode,
        baseUnitCode: baseUnitCode,
        salePrice: salePrice,
        categoryId: categoryId,
        soldUnitCode: soldUnitCode,
        soldConversion: soldConversion,
        soldUnitId: soldUnitId,
        defaultSide: defaultSide,
      ),
      queuedAt: DateTime.now(),
    ));
    return result();
  }
}

/// Add a packaging to an EXISTING item from a draft. Non-default (server RPC
/// adds it non-default; the caller binds the line to it and the learned alias
/// makes future bonos resolve it). Returns the new unit id + synthesized label,
/// or null on a hard reject / thin-client transient failure.
Future<AddedUnit?> addShopItemUnitDraft(
  BuildContext context, {
  required ShopSummary shop,
  required String shopItemId,
  required String unitCode,
  required String unitLabel,
  required String baseUnitLabel,
  required num conversionToBase,
  num? salePrice,
  required String errorMessage,
}) async {
  final api = context.read<ShopApi>();
  final queue = context.read<OfflineQueueController>();
  final repo = useLocalDb(context) ? context.read<LocalRepository>() : null;

  final label = packagingLabel(conversionToBase, baseUnitLabel, unitLabel);
  final unitId = generateUuidV4();
  final opId = generateClientOpId('unit');
  final actorId = _actorId();

  Future<void> writeMirror() async {
    try {
      await repo?.insertLocalShopItemUnit(
        shopItemUnitId: unitId,
        shopItemId: shopItemId,
        unitCode: unitCode,
        packagingLabel: label,
        conversionToBase: conversionToBase,
        salePrice: salePrice,
      );
    } catch (_) {
      // Non-fatal — the next delta sync brings the row in.
    }
  }

  try {
    await api
        .createShopItemUnit(
          shopId: shop.id,
          shopItemId: shopItemId,
          unitCode: unitCode,
          conversionToBase: conversionToBase,
          salePrice: salePrice,
          shopItemUnitId: unitId,
          clientOpId: opId,
        )
        .timeout(const Duration(seconds: 8));
    await writeMirror();
    return AddedUnit(shopItemUnitId: unitId, packagingLabel: label);
  } on PostgrestException catch (error, st) {
    _report(error, st, 'create_shop_item_unit');
    if (context.mounted) showError(context, errorMessage);
    return null;
  } catch (error, st) {
    if (repo == null) {
      _report(error, st, 'create_shop_item_unit');
      if (context.mounted) showError(context, errorMessage);
      return null;
    }
    await writeMirror();
    await queue.enqueue(PendingPost(
      id: generateClientOpId('post'),
      clientOpId: opId,
      shopId: shop.id,
      originalActorUserId: actorId,
      rpc: 'create_shop_item_unit',
      params: buildCreateShopItemUnitParams(
        shopItemUnitId: unitId,
        shopItemId: shopItemId,
        unitCode: unitCode,
        conversionToBase: conversionToBase,
        salePrice: salePrice,
      ),
      queuedAt: DateTime.now(),
    ));
    return AddedUnit(shopItemUnitId: unitId, packagingLabel: label);
  }
}

/// Result of [addShopItemUnitDraft] — the new packaging's id + display label.
class AddedUnit {
  const AddedUnit({required this.shopItemUnitId, required this.packagingLabel});
  final String shopItemUnitId;
  final String packagingLabel;
}

void _report(Object error, StackTrace st, String ctx) {
  FlutterError.reportError(FlutterErrorDetails(
    exception: error,
    stack: st,
    library: 'dukan item-creator',
    context: ErrorDescription(ctx),
  ));
}

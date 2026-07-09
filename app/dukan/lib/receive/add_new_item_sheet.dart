// Receive-side "+ Add new item" entry point. Shares 100% of the body
// with the sale sheet — only the button label + price-required flag
// differ, both flipped via the `AddNewItemVariant` enum. Keeping a
// separate file under `lib/receive/` so the receive screen imports from
// the path that matches its flow (and so a future receive-only tweak
// can land here without touching sale).

import 'package:flutter/material.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/sale/add_new_item_sheet.dart' as shared;

// Re-export the result + variant types so callers under `lib/receive/`
// don't have to reach into `lib/sale/`.
typedef AddNewItemResult = shared.AddNewItemResult;

class AddNewItemSheet {
  /// Receive-side entry point. Always opens the sheet with the receive
  /// variant (optional price, "ADD TO BONO" button).
  static Future<AddNewItemResult?> show(
    BuildContext context,
    ShopSummary shop, {
    required String initialName,
    String? initialCategoryId,
    String? initialBaseUnitCode,
    String? initialPackUnitCode,
    num? initialPackSize,
  }) {
    return shared.AddNewItemSheet.show(
      context,
      shop,
      initialName: initialName,
      variant: shared.AddNewItemVariant.receive,
      initialCategoryId: initialCategoryId,
      initialBaseUnitCode: initialBaseUnitCode,
      initialPackUnitCode: initialPackUnitCode,
      initialPackSize: initialPackSize,
    );
  }
}

// Shared barcode-lookup for every scan entry point (Sale, Receive single,
// Receive multi-scan). Mirrors the typed-search `_fetch` hard-branch: when the
// shop runs the local mirror (`use_local_db`), resolve the code offline-first
// from the mirror; otherwise (thin client) hit the network `search_items` RPC.
//
// Keeping it in one place means camera + HID + multi-scan all resolve the same
// way, online or offline, and there's a single seam to test.

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/sync/local_repository.dart';

/// Resolve a scanned [code] to a single [ItemSearchResult], or null if nothing
/// matches (→ the caller shows its unknown-scan pill).
///
/// Pass [repo] non-null exactly when `useLocalDb` is true for this screen —
/// then the lookup is a local O(1) barcode hit (instant, works offline). When
/// [repo] is null the network `search_items` barcode probe is used.
Future<ItemSearchResult?> resolveScannedCode({
  required LocalRepository? repo,
  required ShopApi api,
  required String shopId,
  required String code,
  required String screen, // 'sale' | 'receive'
  required String locale,
  String? partyId,
}) async {
  if (repo != null) {
    return repo.resolveBarcode(code, screen: screen);
  }
  final rows = await api.searchItems(
    shopId: shopId,
    query: code,
    screen: screen,
    locale: locale,
    partyId: partyId,
  );
  return rows.isEmpty ? null : rows.first;
}

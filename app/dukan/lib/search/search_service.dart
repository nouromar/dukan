// One search path for the whole app, so offline/online policy lives in ONE
// place instead of being copy-pasted at every callsite.
//
// Policy — local-first, network fallback ONLY on an empty local result when
// online:
//   * use_local_db (default) → read the mirror (instant, offline). If it has
//     hits, or we're offline, return it. If it's EMPTY and we're online, fall
//     back to the network — which additionally surfaces GLOBAL-CATALOG rows
//     (isActivated:false, tap to activate) so a shop can reach the catalog the
//     moment a local search misses.
//   * thin client (no mirror) → network, bounded by a short timeout.
//   * discover:true (catalog picker, whose job IS browsing the catalog) →
//     network-first when online, local fallback offline.
//
// Core functions take explicit deps (unit-testable, no BuildContext); the
// context wrappers resolve providers — the resolveScannedCode pattern.

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/search/connectivity_status.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

/// Bounds a network search so an unreachable server (or captive portal that the
/// interface-level connectivity check can't see) can't hang the results.
const Duration kSearchTimeout = Duration(seconds: 5);

// --------------------------------------------------------------------------
// Items
// --------------------------------------------------------------------------

Future<List<ItemSearchResult>> runItemSearch({
  required LocalRepository? repo,
  required ShopApi api,
  required bool online,
  required String shopId,
  required String query,
  required String screen, // 'sale' | 'receive'
  String? partyId,
  String rankBy = 'name',
  String? locale,
  bool discover = false,
}) async {
  Future<List<ItemSearchResult>> local() async {
    if (repo == null) return const [];
    final items = await repo.searchItems(query, shopId: shopId, rankBy: rankBy);
    return [
      for (final i in items) await repo.toItemSearchResult(i, screen: screen),
    ];
  }

  Future<List<ItemSearchResult>> network() async {
    try {
      return await api
          .searchItems(
            shopId: shopId,
            query: query,
            screen: screen,
            partyId: partyId,
            locale: locale,
          )
          .timeout(kSearchTimeout);
    } catch (_) {
      return const []; // offline / timeout → treat as no match
    }
  }

  if (repo == null) {
    // Thin client: no mirror to fall back on. Offline → instant empty rather
    // than a doomed request that hangs to the timeout.
    if (!online) return const [];
    return network();
  }
  if (discover) {
    if (online) {
      final n = await network();
      if (n.isNotEmpty) return n;
    }
    return local();
  }
  final l = await local();
  if (l.isNotEmpty || !online) return l;
  return network();
}

/// Context wrapper — daily-flow item search. Set [discover] for the catalog picker.
Future<List<ItemSearchResult>> searchItems(
  BuildContext context, {
  required String shopId,
  String query = '',
  required String screen,
  String? partyId,
  String rankBy = 'name',
  bool discover = false,
}) {
  return runItemSearch(
    repo: useLocalDb(context) ? context.read<LocalRepository>() : null,
    api: context.read<ShopApi>(),
    online: context.read<ConnectivityStatus>().online,
    shopId: shopId,
    query: query,
    screen: screen,
    partyId: partyId,
    rankBy: rankBy,
    locale: Localizations.localeOf(context).languageCode,
    discover: discover,
  );
}

// --------------------------------------------------------------------------
// Parties (no global catalog — fallback-on-empty only catches a party created
// on another device that hasn't synced back to this one yet).
// --------------------------------------------------------------------------

Future<List<PartySearchResult>> runPartySearch({
  required LocalRepository? repo,
  required ShopApi api,
  required bool online,
  required String shopId,
  required String query,
  required String typeCode,
  String rankBy = 'balance',
}) async {
  Future<List<PartySearchResult>> local() async {
    if (repo == null) return const [];
    final rows = await repo.searchParties(
      query,
      shopId: shopId,
      typeCode: typeCode,
      rankBy: rankBy,
    );
    return [for (final p in rows) repo.toPartySearchResult(p)];
  }

  Future<List<PartySearchResult>> network() async {
    try {
      return await api
          .searchParties(
            shopId: shopId,
            query: query,
            type: typeCode,
            rankBy: rankBy,
          )
          .timeout(kSearchTimeout);
    } catch (_) {
      return const [];
    }
  }

  if (repo == null) {
    if (!online) return const [];
    return network();
  }
  final l = await local();
  if (l.isNotEmpty || !online) return l;
  return network();
}

Future<List<PartySearchResult>> searchParties(
  BuildContext context, {
  required String shopId,
  String query = '',
  required String typeCode,
  String rankBy = 'balance',
}) {
  return runPartySearch(
    repo: useLocalDb(context) ? context.read<LocalRepository>() : null,
    api: context.read<ShopApi>(),
    online: context.read<ConnectivityStatus>().online,
    shopId: shopId,
    query: query,
    typeCode: typeCode,
    rankBy: rankBy,
  );
}

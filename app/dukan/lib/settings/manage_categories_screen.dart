// Owner-only "Manage categories" screen (backend migration 0076).
//
// Two lists behind a Products | Expenses toggle:
//   * Product categories — global ones (read-only "Default" badge) plus
//     this shop's custom ones (rename / hide).
//   * Expense categories — all shop-owned (rename / hide).
//
// Reads come from the local sqflite mirror so it works offline; writes
// go through the offline queue with an optimistic mirror write + a
// client-generated id/client_op_id, so a change shows instantly and
// posts (idempotently) when back online.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/shared/client_op_id.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/sync/local_repository.dart';

enum _CategoryKind { product, expense }

class ManageCategoriesScreen extends StatefulWidget {
  const ManageCategoriesScreen({required this.shop, super.key});
  final ShopSummary shop;

  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen> {
  _CategoryKind _kind = _CategoryKind.product;
  bool _loading = true;
  List<LocalCategory> _products = const [];
  List<LocalExpenseCategory> _expenses = const [];

  String get _shopId => widget.shop.id;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final repo = context.read<LocalRepository>();
    final products = await repo.productCategories(shopId: _shopId);
    final expenses = await repo.expenseCategories(shopId: _shopId);
    if (!mounted) return;
    setState(() {
      _products = products;
      _expenses = expenses;
      _loading = false;
    });
  }

  // --- mutation plumbing -------------------------------------------------

  Future<void> _runMutation({
    required String rpc,
    required String clientOpId,
    required Map<String, dynamic> params,
    required Future<void> Function() optimistic,
  }) async {
    String actorId = '';
    try {
      actorId = Supabase.instance.client.auth.currentUser?.id ?? '';
    } catch (_) {}
    final queue = context.read<OfflineQueueController>();
    try {
      await optimistic();
    } catch (_) {
      // A mirror-write failure must not sink the post; the next delta
      // sync overwrites the local row anyway.
    }
    await queue.enqueue(PendingPost(
      id: generateClientOpId('post'),
      clientOpId: clientOpId,
      shopId: _shopId,
      originalActorUserId: actorId,
      rpc: rpc,
      params: params,
      queuedAt: DateTime.now(),
    ));
    await _reload();
  }

  Future<void> _create(String name) async {
    final id = generateUuidV4();
    final repo = context.read<LocalRepository>();
    final isProduct = _kind == _CategoryKind.product;
    await _runMutation(
      rpc: isProduct ? 'create_shop_category' : 'create_expense_category',
      clientOpId: generateClientOpId('cat'),
      params: buildCreateCategoryParams(categoryId: id, name: name),
      optimistic: () => isProduct
          ? repo.upsertLocalProductCategory(
              categoryId: id, shopId: _shopId, name: name)
          : repo.upsertLocalExpenseCategory(
              categoryId: id, shopId: _shopId, name: name),
    );
  }

  Future<void> _rename(String categoryId, String name) async {
    final repo = context.read<LocalRepository>();
    final isProduct = _kind == _CategoryKind.product;
    await _runMutation(
      rpc: isProduct ? 'rename_shop_category' : 'rename_expense_category',
      clientOpId: generateClientOpId('cat'),
      params: buildRenameCategoryParams(categoryId: categoryId, name: name),
      optimistic: () => isProduct
          ? repo.renameLocalProductCategory(categoryId: categoryId, name: name)
          : repo.renameLocalExpenseCategory(categoryId: categoryId, name: name),
    );
  }

  Future<void> _hide(String categoryId) async {
    final repo = context.read<LocalRepository>();
    final isProduct = _kind == _CategoryKind.product;
    await _runMutation(
      rpc: isProduct
          ? 'set_shop_category_active'
          : 'set_expense_category_active',
      clientOpId: generateClientOpId('cat'),
      params: buildSetCategoryActiveParams(
          categoryId: categoryId, isActive: false),
      optimistic: () => isProduct
          ? repo.setLocalProductCategoryActive(
              categoryId: categoryId, isActive: false)
          : repo.setLocalExpenseCategoryActive(
              categoryId: categoryId, isActive: false),
    );
  }

  // --- UI ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.manageCategoriesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _onAdd(l),
        icon: const Icon(Icons.add),
        label: Text(l.manageCategoriesAdd),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<_CategoryKind>(
              segments: [
                ButtonSegment(
                  value: _CategoryKind.product,
                  label: Text(l.manageCategoriesProductsTab),
                ),
                ButtonSegment(
                  value: _CategoryKind.expense,
                  label: Text(l.manageCategoriesExpensesTab),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
          ),
          Expanded(child: _buildList(l)),
        ],
      ),
    );
  }

  Widget _buildList(L10n l) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final tiles = <Widget>[];
    if (_kind == _CategoryKind.product) {
      for (final c in _products) {
        tiles.add(_tile(
          l,
          name: c.name,
          editable: c.isCustom,
          onRename: () => _onRename(l, c.categoryId, c.name),
          onHide: () => _onHide(l, c.categoryId),
        ));
      }
    } else {
      for (final c in _expenses) {
        tiles.add(_tile(
          l,
          name: c.name,
          editable: true,
          onRename: () => _onRename(l, c.categoryId, c.name),
          onHide: () => _onHide(l, c.categoryId),
        ));
      }
    }
    if (tiles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l.manageCategoriesEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return ListView(children: tiles);
  }

  Widget _tile(
    L10n l, {
    required String name,
    required bool editable,
    required VoidCallback onRename,
    required VoidCallback onHide,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(name),
      onTap: editable ? onRename : null,
      trailing: editable
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: onRename,
                  child: Text(l.manageCategoriesRename),
                ),
                TextButton(
                  onPressed: onHide,
                  child: Text(l.manageCategoriesHide),
                ),
              ],
            )
          : Chip(
              avatar: Icon(
                Icons.lock_outline,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              label: Text(l.manageCategoriesDefaultBadge),
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              visualDensity: VisualDensity.compact,
            ),
    );
  }

  Future<void> _onAdd(L10n l) async {
    final name = await _promptName(l, title: l.manageCategoriesNewTitle);
    if (name != null && name.isNotEmpty) await _create(name);
  }

  Future<void> _onRename(
      L10n l, String categoryId, String current) async {
    final name = await _promptName(
      l,
      title: l.manageCategoriesRenameTitle,
      initial: current,
    );
    if (name != null && name.isNotEmpty && name != current) {
      await _rename(categoryId, name);
    }
  }

  Future<void> _onHide(L10n l, String categoryId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.manageCategoriesHideConfirmTitle),
        content: Text(l.manageCategoriesHideConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.manageCategoriesHide),
          ),
        ],
      ),
    );
    if (ok == true) await _hide(categoryId);
  }

  Future<String?> _promptName(
    L10n l, {
    required String title,
    String initial = '',
  }) {
    final controller = TextEditingController(text: initial);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l.manageCategoriesNameLabel,
                ),
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                child: Text(l.manageCategoriesSave),
              ),
            ],
          ),
        );
      },
    );
  }
}

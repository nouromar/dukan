// "+ Add packaging" bottom sheet — adds a non-base packaging to an
// existing shop_item.
//
// Single-sheet design (no nested sub-picker): this sheet has fewer
// fields than the Add new item flow (no name, no category), so the
// chip grid sourced from `suggest_item_packagings` lives inline above
// the form. Picking a chip locks in the packaging and reveals the
// price field; tapping the "+ Custom packaging" chip swaps the form
// area for a unit dropdown + conversion field. The picker stays
// visible the whole time so the cashier can switch picks without
// hunting for a "back" affordance.
//
// On confirm we call `create_shop_item_unit` and synthesize a
// `ReceiveUnitOption` mirroring the new row so the unit picker can
// close and the receive screen re-pre-fills against the new packaging —
// no extra round-trip.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/packaging_label.dart';
import 'package:dukan/shared/unit_compatibility.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

class AddPackagingSheet {
  /// Caller passes both the base unit's `code` (for the suggestion
  /// query + custom-mode filtering) and its display `label` (used in
  /// header chrome). `categoryId` ranks same-category packagings
  /// first; pass null when not known and we still get cross-category
  /// fallback suggestions.
  static Future<ReceiveUnitOption?> show(
    BuildContext context,
    String shopId,
    String shopItemId,
    String baseUnitCode,
    String baseUnitLabel, {
    String? categoryId,
  }) {
    return showModalBottomSheet<ReceiveUnitOption>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddPackagingBody(
        shopId: shopId,
        shopItemId: shopItemId,
        baseUnitCode: baseUnitCode,
        baseUnitLabel: baseUnitLabel,
        categoryId: categoryId,
      ),
    );
  }
}

class _AddPackagingBody extends StatefulWidget {
  const _AddPackagingBody({
    required this.shopId,
    required this.shopItemId,
    required this.baseUnitCode,
    required this.baseUnitLabel,
    required this.categoryId,
  });

  final String shopId;
  final String shopItemId;
  final String baseUnitCode;
  final String baseUnitLabel;
  final String? categoryId;

  @override
  State<_AddPackagingBody> createState() => _AddPackagingBodyState();
}

class _AddPackagingBodyState extends State<_AddPackagingBody> {
  late final TextEditingController _conversionController;
  late final TextEditingController _priceController;
  Future<List<PackagingSuggestion>>? _suggestionsFuture;
  Future<List<UnitOption>>? _unitsFuture;
  PackagingSuggestion? _pickedSuggestion;
  bool _customMode = false;
  UnitOption? _customUnit;
  bool _saving = false;
  String? _locale;

  /// Grocery-relevance order used in custom mode when the cashier
  /// falls off the picker. Server-ranked suggestions don't need this.
  static const _groceryOrder = <String>[
    'piece',
    'packet',
    'bottle',
    'bag',
    'carton',
    'box',
    'litre',
    'ml',
    'gram',
    'kg',
    'sack',
    'dozen',
  ];

  @override
  void initState() {
    super.initState();
    _conversionController = TextEditingController();
    _priceController = TextEditingController();
    _conversionController.addListener(_rebuild);
    _priceController.addListener(_rebuild);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = Localizations.localeOf(context).languageCode;
    if (_locale != current) {
      _locale = current;
      _suggestionsFuture = context.read<ShopApi>().suggestItemPackagings(
            shopId: widget.shopId,
            shopItemId: widget.shopItemId,
            baseUnitCode: widget.baseUnitCode,
            categoryId: widget.categoryId,
            locale: current,
          );
    }
  }

  @override
  void dispose() {
    _conversionController.removeListener(_rebuild);
    _priceController.removeListener(_rebuild);
    _conversionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  num? get _parsedConversion {
    final raw = _conversionController.text.trim();
    if (raw.isEmpty) return null;
    final value = num.tryParse(raw);
    if (value == null || value <= 0) return null;
    // Conversion = 1 means "same size as the base" — that IS the base
    // packaging. Server rejects it; filter so SAVE stays disabled.
    if (value == 1) return null;
    return value;
  }

  num? get _parsedPrice {
    final raw = _priceController.text.trim();
    if (raw.isEmpty) return null;
    final value = num.tryParse(raw);
    if (value == null || value < 0) return null;
    return value;
  }

  /// The packaging the cashier has currently chosen, expressed as a
  /// (unitCode, unitLabel, conversion) triple. Drives the price label
  /// and the save payload.
  ({String unitCode, String unitLabel, num conversion})? get _chosen {
    final picked = _pickedSuggestion;
    if (picked != null) {
      return (
        unitCode: picked.unitCode,
        unitLabel: picked.unitLabel,
        conversion: picked.conversionToBase,
      );
    }
    if (_customMode) {
      final u = _customUnit;
      final c = _parsedConversion;
      if (u != null && c != null) {
        return (unitCode: u.code, unitLabel: u.label, conversion: c);
      }
    }
    return null;
  }

  bool get _canSave {
    if (_saving) return false;
    if (_chosen == null) return false;
    if (_priceController.text.trim().isNotEmpty && _parsedPrice == null) {
      return false;
    }
    return true;
  }

  void _onPickSuggestion(PackagingSuggestion s) {
    setState(() {
      _pickedSuggestion = s;
      _customMode = false;
      _customUnit = null;
      _conversionController.text = '';
    });
  }

  void _onPickCustom() {
    setState(() {
      _pickedSuggestion = null;
      _customMode = true;
      _customUnit = null;
      _conversionController.text = '';
    });
    _unitsFuture ??= context.read<ShopApi>().listUnits().then(_sortUnits);
  }

  List<UnitOption> _sortUnits(List<UnitOption> units) {
    // Filter out the base unit + any unit that doesn't make sense as a
    // packaging for this base (e.g., "bottle" for a kg-base item). See
    // lib/shared/unit_compatibility.dart for the rule table.
    final filtered = filterPackagingsForBase<UnitOption>(
      widget.baseUnitCode,
      units,
      (u) => u.code,
    );
    return [...filtered]..sort((a, b) {
        final ai = _groceryOrder.indexOf(a.code);
        final bi = _groceryOrder.indexOf(b.code);
        if (ai == -1 && bi == -1) return a.code.compareTo(b.code);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });
  }

  Future<void> _onSave() async {
    final l = tr(context);
    final chosen = _chosen;
    if (chosen == null) return;
    final price = _parsedPrice;

    setState(() => _saving = true);
    final api = context.read<ShopApi>();
    final repo = useLocalDb(context) ? context.read<LocalRepository>() : null;
    try {
      final shopItemUnitId = await api.createShopItemUnit(
        shopId: widget.shopId,
        shopItemId: widget.shopItemId,
        unitCode: chosen.unitCode,
        conversionToBase: chosen.conversion,
        salePrice: price,
      );
      final label = packagingLabel(
        chosen.conversion,
        widget.baseUnitLabel,
        chosen.unitLabel,
      );
      // Optimistically mirror the new packaging so screens that read the local
      // DB (e.g. Product detail) reflect it immediately, not only after a sync.
      try {
        await repo?.insertLocalShopItemUnit(
          shopItemUnitId: shopItemUnitId,
          shopItemId: widget.shopItemId,
          unitCode: chosen.unitCode,
          packagingLabel: label,
          conversionToBase: chosen.conversion,
          salePrice: price,
        );
      } catch (_) {
        // Non-fatal — the next delta sync brings the row in.
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        ReceiveUnitOption(
          shopItemUnitId: shopItemUnitId,
          unitCode: chosen.unitCode,
          unitLabel: chosen.unitLabel,
          packagingLabel: label,
          conversionToBase: chosen.conversion.toDouble(),
          salePrice: price?.toDouble(),
          lastCost: null,
          // Brand new packaging — not the screen default, not the base.
          isDefault: false,
          isBaseUnit: false,
        ),
      );
    } on PostgrestException catch (error, stackTrace) {
      _handleFailure(error, stackTrace, l.addPackagingFailedMessage);
    } catch (error, stackTrace) {
      _handleFailure(error, stackTrace, l.addPackagingFailedMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _handleFailure(Object error, StackTrace stackTrace, String message) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan add-packaging',
        context: ErrorDescription('create_shop_item_unit'),
      ),
    );
    if (!mounted) return;
    showError(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final chosen = _chosen;
    final chosenLabel = chosen == null
        ? null
        : packagingLabel(
            chosen.conversion,
            widget.baseUnitLabel,
            chosen.unitLabel,
          );
    // Bigger cap than the AddNewItemSheet — no nested picker means this
    // sheet absorbs both the chip grid and the form. Mid-range Android
    // viewport gives us ~700dp; 92% leaves a sliver of the host visible
    // so the user knows what's behind.
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.92;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + viewInsets),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.addPackagingSheetTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l.addNewItemCancelButton,
                    icon: const Icon(Icons.close),
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BaseUnitChip(
                        label: l.addPackagingHeaderBaseUnit(
                          widget.baseUnitLabel,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l.addPackagingSuggestionsHeader,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _suggestionsArea(theme, l),
                      if (_customMode) ...[
                        const SizedBox(height: 12),
                        _customForm(theme, l),
                      ],
                      if (chosen != null) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _priceController,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: l.addPackagingPickedPriceLabel(
                              chosenLabel!,
                            ),
                            isDense: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      child: Text(l.addNewItemCancelButton),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _canSave ? _onSave : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(l.addPackagingSaveButton),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _suggestionsArea(ThemeData theme, AppLocalizations l) {
    return FutureBuilder<List<PackagingSuggestion>>(
      future: _suggestionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final hint = snapshot.hasError
            ? l.addPackagingLoadFailedHint
            : null;
        final suggestions = snapshot.data ?? const <PackagingSuggestion>[];
        final categoryRows = suggestions
            .where((r) => r.source == 'category')
            .toList(growable: false);
        final crossRows = suggestions
            .where((r) => r.source == 'cross_category')
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hint != null) ...[
              Text(hint, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
            ] else if (suggestions.isEmpty) ...[
              Text(
                l.addPackagingNoSuggestionsHint,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
            ],
            // Same-category chips first. When there are no cross-category
            // fallbacks the Custom chip rides the trailing edge of this
            // Wrap to keep things tight.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in categoryRows) _suggestionChip(s),
                if (crossRows.isEmpty) _customChip(l),
              ],
            ),
            if (crossRows.isNotEmpty) ...[
              if (categoryRows.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(
                    l.addPackagingLessCommonHeader,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in crossRows) _suggestionChip(s),
                  _customChip(l),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _suggestionChip(PackagingSuggestion s) {
    final label = packagingLabel(
      s.conversionToBase,
      widget.baseUnitLabel,
      s.unitLabel,
    );
    final picked = _pickedSuggestion;
    final selected = picked != null &&
        picked.unitCode == s.unitCode &&
        picked.conversionToBase == s.conversionToBase;
    return _ChoiceTile(
      label: label,
      selected: selected,
      onTap: _saving ? null : () => _onPickSuggestion(s),
    );
  }

  /// The custom entry is an ACTION (it opens an inline form), not another
  /// value to pick — so it's styled deliberately unlike the suggestion
  /// chips: primary-coloured outline + text, a leading "+", and a trailing
  /// chevron that flips to expand_less while the form is open. Reads as
  /// "go here", not "one of the options".
  Widget _customChip(AppLocalizations l) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Material(
      color: _customMode
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: color, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _saving ? null : _onPickCustom,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                l.addPackagingCustomEntry,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(
                _customMode ? Icons.expand_less : Icons.chevron_right,
                size: 18,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customForm(ThemeData theme, AppLocalizations l) {
    return FutureBuilder<List<UnitOption>>(
      future: _unitsFuture,
      builder: (context, snapshot) {
        final units = snapshot.data ?? const <UnitOption>[];
        final picked = _customUnit;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<UnitOption>(
              initialValue: picked,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l.addPackagingUnitLabel,
                hintText: l.addNewItemUnitChooseHint,
                isDense: true,
              ),
              items: [
                for (final u in units)
                  DropdownMenuItem(value: u, child: Text(u.label)),
              ],
              onChanged: _saving
                  ? null
                  : (u) => setState(() => _customUnit = u),
            ),
            // Conversion field only renders after a unit is picked, so
            // the label always reads the specific unit
            // ("How many Kg in 1 Bag?") instead of a generic
            // placeholder ("How many Kg in 1 Unit?").
            if (picked != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _conversionController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: l.addPackagingConversionLabel(
                    widget.baseUnitLabel,
                    picked.label,
                  ),
                  isDense: true,
                ),
              ),
              // Plain-prose readback to spot off-by-10 typos at a glance.
              if (_parsedConversion != null) ...[
                const SizedBox(height: 4),
                Text(
                  l.packagingConversionPreview(
                    picked.label,
                    _formatConversion(_parsedConversion!),
                    widget.baseUnitLabel,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

String _formatConversion(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

class _BaseUnitChip extends StatelessWidget {
  const _BaseUnitChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        avatar: const Icon(Icons.straighten, size: 18),
        label: Text(label),
      ),
    );
  }
}

/// Compact intrinsic-width pill used inside a `Wrap` so many options
/// pack onto few rows. Mirrors AddNewItemSheet's `_ChoiceTile`.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surface;
    final fg = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: fg),
          ),
        ),
      ),
    );
  }
}

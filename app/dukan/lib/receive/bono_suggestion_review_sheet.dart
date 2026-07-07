// Bono OCR suggestion UI for the Receive screen (Slice 5).
//
//   * BonoSuggestionBanner — a quiet inline strip: "Reading the bono…" while
//     the async OCR runs, then "N lines read — Review". Modelled on the
//     screen's existing _ReceiveUnknownScanPill / _AddNewItemBanner.
//   * BonoSuggestionReviewSheet — a bottom sheet grouping the lines by
//     confidence. Matched (high) + Likely (med) are pre-checked and applyable;
//     unmatched (low) lines are shown read-only as a reminder to enter them by
//     hand. APPLY pops the checked, bound suggestions back to the screen, which
//     merges them into the receive (manual lines win) and fires the learning
//     loop. See docs/bono-ocr-prepopulate.md.

import 'package:flutter/material.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/receive/bono_bind_item_sheet.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';

/// A resolved bono line the screen should add to the receive + learn. Unifies
/// pre-matched (high/med) suggestions and hand-bound "Not found" lines so the
/// caller applies them the same way.
class BonoApplyLine {
  const BonoApplyLine({
    required this.shopItemId,
    required this.shopItemUnitId,
    required this.itemId,
    required this.displayName,
    required this.packagingLabel,
    required this.baseUnitLabel,
    required this.quantity,
    required this.lineTotal,
    required this.rawText,
    required this.learnConfidence,
  });

  final String shopItemId;
  final String shopItemUnitId;
  final String? itemId;
  final String displayName;
  final String packagingLabel;
  final String baseUnitLabel;
  final double quantity;
  final double lineTotal;
  final String rawText;
  final double learnConfidence;
}

/// First-use teaching hint in the empty Receive state — advertises the photo
/// shortcut ("snap the bono, we'll fill it in"). Tapping it opens the attach
/// flow; dismiss hides it for the session.
class BonoHintBanner extends StatelessWidget {
  const BonoHintBanner({
    super.key,
    required this.onTap,
    required this.onDismiss,
  });

  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.document_scanner_outlined,
                    color: scheme.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.bonoHintTitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        l.bonoHintSubtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onTertiaryContainer),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  color: scheme.onTertiaryContainer,
                  onPressed: onDismiss,
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BonoSuggestionBanner extends StatelessWidget {
  const BonoSuggestionBanner({
    super.key,
    required this.loading,
    required this.count,
    required this.onReview,
    required this.onDismiss,
  });

  final bool loading;
  final int count;
  final VoidCallback onReview;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.receipt_long, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              loading ? l.bonoSuggestionsReading : l.bonoSuggestionsFound(count),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
          if (!loading) ...[
            FilledButton(
              onPressed: onReview,
              child: Text(l.bonoSuggestionsReview),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: onDismiss,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            ),
          ],
        ],
      ),
    );
  }
}

class BonoSuggestionReviewSheet extends StatefulWidget {
  const BonoSuggestionReviewSheet({
    super.key,
    required this.suggestions,
    required this.shop,
    this.supplierPartyId,
  });

  final List<BonoSuggestion> suggestions;
  final ShopSummary shop;
  final String? supplierPartyId;

  @override
  State<BonoSuggestionReviewSheet> createState() =>
      _BonoSuggestionReviewSheetState();
}

class _BonoSuggestionReviewSheetState extends State<BonoSuggestionReviewSheet> {
  // keyed by line_no; pre-matched lines start checked, hand-bound get checked
  // when the cashier picks an item for them.
  late final Map<int, bool> _checked = {
    for (final s in widget.suggestions)
      if (s.isBound) s.lineNo: true,
  };

  // Hand-bindings the cashier chose for "Not found" lines (keyed by line_no).
  final Map<int, BonoBindTarget> _bound = {};

  double _lineTotal(BonoSuggestion s) =>
      s.lineTotal ?? (s.unitPrice != null ? s.unitPrice! * s.quantity : 0);

  // The checked lines to apply: pre-matched suggestions + hand-bound ones.
  List<BonoApplyLine> _resolveSelected() {
    final out = <BonoApplyLine>[];
    for (final s in widget.suggestions) {
      if (_checked[s.lineNo] != true) continue;
      if (s.isBound) {
        out.add(BonoApplyLine(
          shopItemId: s.suggestedShopItemId!,
          shopItemUnitId: s.suggestedShopItemUnitId!,
          itemId: s.itemId,
          displayName: s.displayName ?? s.rawText,
          packagingLabel: s.unitCode ?? s.baseUnitCode ?? '',
          baseUnitLabel: s.baseUnitCode ?? '',
          quantity: s.quantity,
          lineTotal: _lineTotal(s),
          rawText: s.rawText,
          learnConfidence: s.confidence == 'high' ? 0.9 : 0.6,
        ));
      } else {
        final b = _bound[s.lineNo];
        if (b == null) continue;
        out.add(BonoApplyLine(
          shopItemId: b.shopItemId,
          shopItemUnitId: b.shopItemUnitId,
          itemId: b.itemId,
          displayName: b.displayName,
          packagingLabel: b.packagingLabel,
          baseUnitLabel: b.baseUnitLabel,
          quantity: s.quantity,
          lineTotal: _lineTotal(s),
          rawText: s.rawText,
          learnConfidence: 1, // explicit cashier binding
        ));
      }
    }
    return out;
  }

  Future<void> _bind(BonoSuggestion s) async {
    final target = await showBonoBindItemPicker(
      context,
      shop: widget.shop,
      supplierPartyId: widget.supplierPartyId,
      initialQuery: s.rawText,
    );
    if (target == null || !mounted) return;
    setState(() {
      _bound[s.lineNo] = target;
      _checked[s.lineNo] = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final high =
        widget.suggestions.where((s) => s.isBound && s.confidence == 'high');
    final med =
        widget.suggestions.where((s) => s.isBound && s.confidence != 'high');
    final low = widget.suggestions.where((s) => !s.isBound);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.bonoSuggestionsTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              children: [
                if (high.isNotEmpty)
                  _section(l.bonoSuggestionsMatchedSection, high.toList(),
                      checkable: true),
                if (med.isNotEmpty)
                  _section(l.bonoSuggestionsLikelySection, med.toList(),
                      checkable: true),
                if (low.isNotEmpty)
                  _unmatchedSection(l.bonoSuggestionsUnmatchedSection,
                      low.toList()),
                const SizedBox(height: 88),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _resolveSelected().isEmpty
                      ? null
                      : () =>
                          Navigator.of(context).pop(_resolveSelected()),
                  child: Text(l.bonoSuggestionsApply),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<BonoSuggestion> items,
      {required bool checkable}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            title,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
        for (final s in items)
          if (checkable)
            CheckboxListTile(
              value: _checked[s.lineNo] ?? false,
              onChanged: (v) =>
                  setState(() => _checked[s.lineNo] = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                s.displayName ?? s.rawText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: _subtitle(s),
              secondary: _moneyColumn(s),
            )
          else
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: Text(
                s.rawText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: _subtitle(s),
              trailing: _moneyColumn(s),
            ),
      ],
    );
  }

  // "Not found" lines: a "Choose item" button binds each to a real item; once
  // bound it renders as a checked row for the chosen item (raw text kept for
  // reference).
  Widget _unmatchedSection(String title, List<BonoSuggestion> items) {
    final theme = Theme.of(context);
    final l = tr(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            title,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
        for (final s in items)
          if (_bound[s.lineNo] != null)
            CheckboxListTile(
              value: _checked[s.lineNo] ?? true,
              onChanged: (v) =>
                  setState(() => _checked[s.lineNo] = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                _bound[s.lineNo]!.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: _subtitle(s),
              secondary: _moneyColumn(s),
            )
          else
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: Text(
                s.rawText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: _unboundSubtitle(s),
              trailing: OutlinedButton(
                onPressed: () => _bind(s),
                child: Text(l.bonoBindChooseItem),
              ),
            ),
      ],
    );
  }

  // Unbound "Not found" row: qty + money inline (the trailing slot holds the
  // "Choose item" button instead of the money column).
  Widget _unboundSubtitle(BonoSuggestion s) {
    final theme = Theme.of(context);
    final pkg = s.unitCode;
    final qty =
        '× ${_fmt(s.quantity)}${pkg != null && pkg.isNotEmpty ? ' $pkg' : ''}';
    final total = s.lineTotal != null
        ? ' · ${formatMoney(s.lineTotal!, widget.shop)}'
        : '';
    return Text(
      '$qty$total',
      style:
          theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  // Quantity line: big, plain "×<qty> <packaging>" so it's obvious how many
  // units, plus the raw bono text (for matched + hand-bound rows) to verify.
  Widget _subtitle(BonoSuggestion s) {
    final theme = Theme.of(context);
    final pkg = s.unitCode;
    final qty = '× ${_fmt(s.quantity)}${pkg != null && pkg.isNotEmpty ? ' $pkg' : ''}';
    final matched = s.rawText.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          qty,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (matched)
          Text(
            '“${s.rawText}”',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }

  // Line total, prominent + money-formatted; per-unit price muted below it.
  Widget _moneyColumn(BonoSuggestion s) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (s.lineTotal != null)
          Text(
            formatMoney(s.lineTotal!, widget.shop),
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        if (s.unitPrice != null)
          Text(
            '@ ${formatMoney(s.unitPrice!, widget.shop)}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }

  String _fmt(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();
}

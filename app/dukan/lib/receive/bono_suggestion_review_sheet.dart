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
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';

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
  });

  final List<BonoSuggestion> suggestions;
  final ShopSummary shop;

  @override
  State<BonoSuggestionReviewSheet> createState() =>
      _BonoSuggestionReviewSheetState();
}

class _BonoSuggestionReviewSheetState extends State<BonoSuggestionReviewSheet> {
  // keyed by line_no; only bound lines are checkable, pre-checked on.
  late final Map<int, bool> _checked = {
    for (final s in widget.suggestions)
      if (s.isBound) s.lineNo: true,
  };

  List<BonoSuggestion> get _selected => widget.suggestions
      .where((s) => s.isBound && _checked[s.lineNo] == true)
      .toList(growable: false);

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
                  _section(l.bonoSuggestionsUnmatchedSection, low.toList(),
                      checkable: false),
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
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_selected),
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
              title: Text(s.displayName ?? s.rawText),
              subtitle: _subtitle(s),
              secondary: _moneyColumn(s),
            )
          else
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: Text(s.rawText),
              subtitle: _subtitle(s),
              trailing: _moneyColumn(s),
            ),
      ],
    );
  }

  // Quantity line: big, plain "×<qty> <packaging>" so it's obvious how many
  // units, plus the raw bono text on matched rows so the cashier can verify.
  Widget _subtitle(BonoSuggestion s) {
    final theme = Theme.of(context);
    final pkg = s.unitCode;
    final qty = '× ${_fmt(s.quantity)}${pkg != null && pkg.isNotEmpty ? ' $pkg' : ''}';
    final matched = s.displayName != null && s.rawText.isNotEmpty;
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

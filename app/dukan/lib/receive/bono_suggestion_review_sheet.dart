// Bono OCR suggestion banners + the apply-line contract for the Receive screen.
//
//   * BonoHintBanner — a first-use teaching hint ("snap the bono, we'll fill it
//     in") in the empty Receive state.
//   * BonoSuggestionBanner — a quiet inline strip: "Reading the bono…" while the
//     async OCR runs, then "N lines read — Review".
//   * BonoApplyLine — a resolved bono line the review screen hands back to the
//     Receive screen to merge into the receive + learn.
//
// The review UI itself is now the full-screen BonoReviewScreen
// (lib/receive/bono_review_screen.dart) — it consumes the suggestions and
// returns a List<BonoApplyLine>. See docs/bono-ocr-prepopulate.md.

import 'package:flutter/material.dart';

import 'package:dukan/shared/l10n.dart';

/// A resolved bono line the screen should add to the receive + learn. Unifies
/// pre-matched suggestions and hand-bound / newly-created lines so the caller
/// applies them the same way.
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
    this.missed = false,
  });

  final bool loading;
  final int count;
  final VoidCallback onReview;
  final VoidCallback onDismiss;
  // OCR read nothing (failed / junk photo) — a dismissible "enter by hand"
  // note so the graceful degradation is visible, not a silently dropped spinner.
  final bool missed;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final warn = missed;
    final fg = warn ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: warn ? scheme.errorContainer : scheme.secondaryContainer,
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
            Icon(warn ? Icons.error_outline : Icons.receipt_long, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              warn
                  ? l.bonoSuggestionsFailed
                  : loading
                      ? l.bonoSuggestionsReading
                      : l.bonoSuggestionsFound(count),
              style: theme.textTheme.bodyMedium?.copyWith(color: fg),
            ),
          ),
          if (!loading && !warn)
            FilledButton(
              onPressed: onReview,
              child: Text(l.bonoSuggestionsReview),
            ),
          // Dismissible in every state — "Reading…", "N lines · Review", miss.
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: onDismiss,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          ),
        ],
      ),
    );
  }
}

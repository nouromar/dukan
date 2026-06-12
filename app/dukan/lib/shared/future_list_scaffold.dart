// The spinner → error → empty → list ladder repeated across every
// history screen (Sale, Receive, Payment, Expense), the Low-Stock
// report, and several detail screens. Each one rolled its own
// FutureBuilder + if-ladder + RefreshIndicator + ListView. This
// widget centralises the layout so a screen says only "fetch this,
// render this row, and these are the empty/error messages."

import 'package:flutter/material.dart';

class FutureListScaffold<T> extends StatelessWidget {
  const FutureListScaffold({
    required this.future,
    required this.itemBuilder,
    required this.emptyMessage,
    required this.errorMessage,
    required this.onRefresh,
    this.filter,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    super.key,
  });

  /// The in-flight load. The widget rebuilds whenever this changes —
  /// callers triggering a reload should `setState` a new future.
  final Future<List<T>>? future;

  /// Build a single row. Receives the row data + its index in the
  /// post-filter list.
  final Widget Function(BuildContext context, T row, int index) itemBuilder;

  /// Localized "nothing here yet" copy.
  final String emptyMessage;

  /// Localized "couldn't load — try again" copy. The full error stack
  /// is dropped on purpose (cashiers don't read stack traces); callers
  /// that need fine-grained handling should put a richer widget in
  /// place of this scaffold instead of layering one on top.
  final String errorMessage;

  /// Pull-to-refresh handler. Typically `() async => _reload()`.
  final Future<void> Function() onRefresh;

  /// Optional client-side filter (e.g. "hide voided rows", search
  /// query). Runs once per build over the loaded data — fine at v1
  /// page sizes; revisit when pagination + server-side search land.
  final bool Function(T row)? filter;

  /// Padding around the list. Use the default unless a screen needs
  /// something specific.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                errorMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          );
        }
        final all = snapshot.data ?? const <Never>[];
        final rows = filter == null
            ? all.cast<T>().toList(growable: false)
            : all.cast<T>().where(filter!).toList(growable: false);
        if (rows.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            // ListView so the empty state is pull-to-refreshable.
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
                  child: Text(
                    emptyMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.separated(
            padding: padding,
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => itemBuilder(context, rows[i], i),
          ),
        );
      },
    );
  }
}

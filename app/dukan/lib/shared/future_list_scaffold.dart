// The spinner → error → empty → list ladder repeated across every
// history screen (Sale, Receive, Payment, Expense), the Low-Stock
// report, and several detail screens. Each one rolled its own
// FutureBuilder + if-ladder + RefreshIndicator + ListView. This
// widget centralises the layout so a screen says only "fetch this,
// render this row, and these are the empty/error messages."

import 'package:flutter/material.dart';

class FutureListScaffold<T> extends StatefulWidget {
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
  State<FutureListScaffold<T>> createState() => _FutureListScaffoldState<T>();
}

class _FutureListScaffoldState<T> extends State<FutureListScaffold<T>> {
  // #370: hold the last successfully-resolved list so that
  // explicit reloads (filter change, pull-to-refresh, parent
  // setState with a new future) don't transition through the
  // spinner branch. Spinner only fires on the truly-cold path
  // where nothing was ever rendered. Used by every history screen
  // (Sale, Receive, Payment, Expense) via this shared widget.
  List<T>? _lastKnown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<T>>(
      future: widget.future,
      builder: (context, snapshot) {
        // Capture newly-resolved data so subsequent builds paint
        // from `_lastKnown` while a fresh load is in flight.
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          _lastKnown = snapshot.data;
        }
        final loaded = _lastKnown ?? snapshot.data;
        // Truly cold — nothing ever rendered + nothing landed yet.
        if (loaded == null) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          // Resolved with error and no previous data.
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  widget.errorMessage,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            );
          }
        }
        final all = loaded ?? const <Never>[];
        final rows = widget.filter == null
            ? all.cast<T>().toList(growable: false)
            : all.cast<T>().where(widget.filter!).toList(growable: false);
        if (rows.isEmpty) {
          return RefreshIndicator(
            onRefresh: widget.onRefresh,
            // ListView so the empty state is pull-to-refreshable.
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
                  child: Text(
                    widget.emptyMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView.separated(
            padding: widget.padding,
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => widget.itemBuilder(context, rows[i], i),
          ),
        );
      },
    );
  }
}

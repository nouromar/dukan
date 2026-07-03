// Scrollable line list shared by the Sale cart and Receive bono strips, with
// two size modes and an overflow cue.
//
//   * `fill: false` (normal) — the list is capped at [maxHeight] (20% of the
//     screen) and shrink-wraps to its content up to that cap.
//   * `fill: true` (full/review) — the list is `Expanded`, filling the drawer;
//     it must be placed as a child of a Flex (Column) whose parent gives it a
//     bounded height.
//
// When lines are scrolled out of view, a bottom-center down-chevron over a soft
// fade is drawn as an OVERLAY (a Stack layer) so it costs ~0 vertical space and
// never steals a row from the items. In normal mode the cue is tappable
// (`onExpandRequested` → grow to full); in full mode it's a passive
// "scroll for more" hint.
//
// Owns its own ScrollController so the Scrollbar doesn't collide with the
// PrimaryScrollController used by the item grid above.

import 'package:flutter/material.dart';

class ExpandableLineList extends StatefulWidget {
  const ExpandableLineList({
    required this.itemCount,
    required this.itemBuilder,
    required this.separatorBuilder,
    required this.maxHeight,
    required this.fill,
    this.onExpandRequested,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder separatorBuilder;

  /// Cap applied in normal mode (ignored when [fill] is true).
  final double maxHeight;

  /// True = full/review mode: fill the available height (`Expanded`).
  final bool fill;

  /// Tapped from the overflow cue in normal mode to grow to full. Null in
  /// full mode (the cue becomes a passive scroll hint).
  final VoidCallback? onExpandRequested;

  @override
  State<ExpandableLineList> createState() => _ExpandableLineListState();
}

class _ExpandableLineListState extends State<ExpandableLineList> {
  final _controller = ScrollController();
  bool _hasMoreBelow = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_recompute);
  }

  @override
  void dispose() {
    _controller.removeListener(_recompute);
    _controller.dispose();
    super.dispose();
  }

  /// True when the list can still scroll down (there are hidden lines below).
  void _recompute() {
    if (!_controller.hasClients) return;
    final p = _controller.position;
    final more = p.hasContentDimensions && p.maxScrollExtent > p.pixels + 4;
    if (more != _hasMoreBelow && mounted) {
      setState(() => _hasMoreBelow = more);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Content/size can change (lines added, mode flipped) without a scroll
    // event, so re-check after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());

    final stack = Stack(
      children: [
        Scrollbar(
          controller: _controller,
          child: ListView.separated(
            controller: _controller,
            primary: false,
            // Shrink-wrap in normal mode so a short list is a short drawer;
            // fill mode wants the ListView to take the whole Expanded box.
            shrinkWrap: !widget.fill,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: widget.itemCount,
            separatorBuilder: widget.separatorBuilder,
            itemBuilder: widget.itemBuilder,
          ),
        ),
        if (_hasMoreBelow)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _OverflowCue(onTap: widget.onExpandRequested),
          ),
      ],
    );

    return widget.fill
        ? Expanded(child: stack)
        : ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            child: stack,
          );
  }
}

/// Bottom-center down-chevron over a soft fade, hinting hidden lines below.
/// Tappable (grow to full) when [onTap] is non-null; otherwise a passive hint
/// that lets scroll gestures pass through.
class _OverflowCue extends StatelessWidget {
  const _OverflowCue({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fade = scheme.surfaceContainerHigh;
    final cue = Container(
      height: 26,
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fade.withValues(alpha: 0), fade],
        ),
      ),
      child: Icon(
        Icons.keyboard_arrow_down,
        size: 20,
        color: scheme.onSurfaceVariant,
      ),
    );
    if (onTap == null) return IgnorePointer(child: cue);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: cue,
    );
  }
}

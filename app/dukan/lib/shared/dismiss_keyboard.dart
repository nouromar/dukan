import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Use as a `TextField.onTapOutside` handler so a tap **anywhere except the
/// focused field** closes the keyboard — including on tiles, buttons, and
/// content, not just empty space.
///
/// Flutter's default mobile `onTapOutside` keeps focus (so toolbars can be
/// tapped); the daily-entry flows want the opposite — especially the numeric
/// keypad, which has no Done key, so without this the cashier can get stuck
/// with the keyboard up and SAVE underneath it.
void dismissKeyboardOnTapOutside(PointerDownEvent _) {
  FocusManager.instance.primaryFocus?.unfocus();
}

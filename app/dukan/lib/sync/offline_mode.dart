// Tiny helper for screens to check whether to read from the
// local mirror (offline_mode = full) or hit the network (light).
// Centralised so every screen branches the same way.

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:dukan/config/config_keys.dart';
import 'package:dukan/config/config_resolver.dart';

/// True when the resolved `offline_mode` for this session is
/// `full`. False otherwise — including when no [ConfigResolver]
/// is in scope (e.g. widget tests that don't wire one). Always
/// safe to call; never throws.
bool offlineModeFull(BuildContext context) {
  try {
    return context.read<ConfigResolver>().resolve(ConfigKeys.offlineMode) ==
        'full';
  } catch (_) {
    return false;
  }
}

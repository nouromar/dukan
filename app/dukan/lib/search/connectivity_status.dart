// A tiny, queryable "is the device online?" signal for the search layer.
//
// connectivity_plus is already a dependency, but its stream is consumed only
// internally in auth_bootstrap as an edge trigger. This lifts it into a
// provided ChangeNotifier the search service can read to GATE the network
// fallback: when offline, an empty local search returns instantly instead of
// hanging on a doomed request. It reports interface-presence (wifi/mobile),
// not true server reachability — a short request timeout covers the rest.

import 'package:flutter/foundation.dart';

class ConnectivityStatus extends ChangeNotifier {
  ConnectivityStatus({bool online = true}) : _online = online;

  bool _online;
  bool get online => _online;

  /// Set the current state; notifies only on an actual change.
  void set(bool value) {
    if (value == _online) return;
    _online = value;
    notifyListeners();
  }
}

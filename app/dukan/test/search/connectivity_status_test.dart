import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/search/connectivity_status.dart';

void main() {
  test('notifies on change, no-op on same value', () {
    final c = ConnectivityStatus(online: true);
    var n = 0;
    c.addListener(() => n++);

    c.set(true); // no change
    expect(n, 0);

    c.set(false);
    expect(n, 1);
    expect(c.online, isFalse);

    c.set(false); // no change
    expect(n, 1);

    c.set(true);
    expect(n, 2);
    expect(c.online, isTrue);
  });
}

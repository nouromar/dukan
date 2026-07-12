import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:dukan/settings/about_screen.dart';

import '../shared/wrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('About shows the installed app name + version (build)',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Dukan',
      packageName: 'com.dukan.dukan',
      version: '1.0.0',
      buildNumber: '17',
      buildSignature: '',
    );

    await tester.pumpWidget(wrapWithApp(const AboutScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Dukan'), findsWidgets);
    expect(find.text('1.0.0 (17)'), findsOneWidget);
  });
}

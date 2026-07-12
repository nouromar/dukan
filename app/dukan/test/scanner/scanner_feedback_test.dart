import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/scanner/scanner_feedback.dart';
import 'package:dukan/scanner/scanner_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final played = <SystemSoundType>[];

  setUp(() {
    played.clear();
    ScannerSettings.resetForTesting();
    ScannerFeedback.soundPlayer = (t) async => played.add(t);
  });

  tearDown(() {
    ScannerFeedback.soundPlayer = SystemSound.play;
    ScannerSettings.resetForTesting();
  });

  test('success beeps (alert) when sound is enabled', () async {
    await ScannerFeedback.success();
    expect(played, [SystemSoundType.alert]);
  });

  test('duplicate plays a soft click', () async {
    await ScannerFeedback.duplicate();
    expect(played, [SystemSoundType.click]);
  });

  test('no sound when soundEnabled is false (haptic still fires)', () async {
    ScannerSettings.install(const ScannerSettings(soundEnabled: false));
    await ScannerFeedback.success();
    await ScannerFeedback.duplicate();
    expect(played, isEmpty);
  });

  test('unknown + error stay silent (the pill / vibrate are the cue)',
      () async {
    await ScannerFeedback.unknownInMultiScan();
    await ScannerFeedback.error();
    expect(played, isEmpty);
  });
}

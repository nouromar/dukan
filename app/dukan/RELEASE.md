# Releasing DukanPro (TestFlight + Play internal testing)

The app↔backend is already validated (works on a test phone against hosted
Supabase). This covers turning that into store builds for testers.

## One-time setup

### Build-time config (both platforms)
1. Copy the template and fill in your hosted Supabase values (same ones the test
   phone uses):
   ```bash
   cp dart_defines.example.json dart_defines.json   # gitignored
   ```

### Android upload keystore (one-time, keep it FOREVER)
2. Generate an upload keystore. **If you lose this or its passwords, you can
   never update the app on Play** — back it up securely.
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
3. Create `android/key.properties` (gitignored) from the template:
   ```bash
   cp android/key.properties.example android/key.properties
   # edit: passwords, keyAlias=upload, storeFile=<absolute path to upload-keystore.jks>
   ```

### Store records
4. **App Store Connect** → create app: bundle id `com.dukan.dukan`, name DukanPro.
5. **Play Console** → create app, then **Internal testing** track. Package name
   `com.dukan.dukan`. Enable Play App Signing (recommended; you upload with the
   upload key, Google re-signs).

## Each release

```bash
tool/build-release.sh            # builds both; auto-bumps the build number
# or: tool/build-release.sh ios   |   tool/build-release.sh android
```
Artifacts:
- iOS: `build/ios/ipa/*.ipa`
- Android: `build/app/outputs/bundle/release/app-release.aab`

Then commit the `pubspec.yaml` build-number bump.

### Upload
- **iOS / TestFlight**: open the **Transporter** app (Mac App Store), drag the
  `.ipa`, Deliver. After it processes (~10–30 min), add it to a TestFlight group.
  *Internal* testers (your team) need no review; *external* testers need a one-time
  Beta App Review + a "What to test" note + contact email.
- **Android / Play**: Play Console → Internal testing → Create release → upload the
  `.aab` → add tester emails (or an email list) → roll out. Internal testing has no
  review delay; testers opt in via the share link.

## Notes
- `ITSAppUsesNonExemptEncryption=false` is set in Info.plist (app uses only
  standard HTTPS/TLS), so ASC won't ask the encryption question each build. If you
  ever add non-standard on-device crypto, revisit this.
- Both stores reject duplicate build numbers; the script bumps `+N` each run.
- The Android release build falls back to debug signing if `key.properties` is
  absent — fine for `flutter run --release`, but Play needs the real keystore.

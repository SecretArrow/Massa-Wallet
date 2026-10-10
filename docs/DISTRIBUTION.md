# Distribusi — Play Store, F-Droid, iOS

Panduan mempublikasikan Massa Wallet v1.2.0+ ke tiap kanal.

## 1. Play Store (Google Play)

CI (`release.yml`) sudah memproduksi **APK split-per-ABI** (arm64-v8a,
armeabi-v7a, x86_64). Untuk Play Store, Google mewajibkan **AAB
(App Bundle)** yang ditandatangani upload key milik Anda:

```bash
# 1. Buat upload keystore (sekali, simpan aman, JANGAN commit)
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload

# 2. Isi android/key.properties (JANGAN commit — tambahkan ke .gitignore)
#    storePassword=…  keyPassword=…  keyAlias=upload
#    storeFile=/absolute/path/upload-keystore.jks

# 3. Build AAB signed
flutter build appbundle --release

# Output: build/app/outputs/bundle/release/app-release.aab
```

Lalu di Play Console:
1. Buat aplikasi → `site.massawallet.app`
2. Production → Create release → upload `.aab`
3. Play App Signing menangani signing rilis dari upload key Anda.
4. Data safety: keys stay on device (no collection), RPC over HTTPS.

## 2. F-Droid

F-Droid membangun dari source, jadi metadata fdroiddata dibutuhkan.
Skeleton sudah disiapkan di `fastlane/metadata/android/site.massawallet.app/`.

Langkah proposal paket:
1. Fork https://gitlab.com/fdroid/fdroiddata
2. Salin `metadata/site.massawallet.app.yml` (contoh di folder ini) ke
   `fdroiddata/metadata/`.
3. Buat MR ke fdroiddata. Verifier akan build dari tag `v*` di repo ini.

Catatan kepatuhan F-Droid:
- ✅ Lisensi Apache-2.0 (lihat LICENSE)
- ✅ Tanpa tracker/ads; hanya network ke RPC publik Massa + CoinGecko (harga)
- ✅ Build reproducible-ish: Flutter toolchain ditetapkan 3.35.4 di CI
- Dependency semuanya pub.dev open source

## 3. iOS

CI menambahkan job `build-ios` (macos-15, `flutter build ios --no-codesign`)
yang menghasilkan **MassaWallet-ios-unsigned.zip** (Payload/Runner.app) di
setiap tag `v*`. Karena unsigned:

- **Sideload**: AltStore / Sideloadly / Xcode (personal cert, 7 hari).
- **TestFlight/App Store**: butuh Apple Developer ($99/tahun):
  ```bash
  flutter build ipa --release
  # Upload via Transporter ke App Store Connect
  ```

Bundle ID: `site.massawallet.app` (sama dengan Android applicationId).

## 4. Direct APK (sudah aktif)

Setiap tag `v*` → GitHub Actions → 3 APK split ABI + iOS zip otomatis di
https://github.com/SecretArrow/Massa-Wallet/releases

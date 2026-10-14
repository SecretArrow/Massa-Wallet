# 📲 Panduan Instalasi Pine Wallet (Android)

Panduan lengkap memasang APK Pine Wallet dari GitHub Releases, termasuk cara
memperbaiki galat **"App not installed as package appears to be invalid"**.
Dokumen versi bahasa Inggris menyusul paragraf Indonesia di tiap bagian.

---

## 1. Pilih file APK yang tepat

Setiap rilis menyediakan 4 file APK. Unduh **satu** yang sesuai HP Anda —
langsung **di HP**, bukan dulu di PC (mengurangi risiko file dimodifikasi
aplikasi lain saat dipindahkan):

| File | Untuk HP apa |
|---|---|
| `PineWallet-app-arm64-v8a-release.apk` | **Hampir semua HP sejak 2019** — pilihan utama |
| `PineWallet-app-armeabi-v7a-release.apk` | HP 32-bit lama (2015–2018 ke bawah) |
| `PineWallet-app-x86_64-release.apk` | Emulator, Chromebook, tablet x86 |
| `PineWallet-universal-release.apk` | **Bila ragu** — berisi semua arsitektur, ukurannya paling besar |

> Tidak tahu arsitektur HP? Pasang saja `universal` — fungsinya identik,
> hanya ukuran file lebih besar.

## 2. Uninstall versi lama dulu (WAJIB bila pernah memasang ≤ 1.8.0)

Rilis **v1.8.0 dan sebelumnya** ditandatangani dengan *debug key*. Rilis
**v1.8.1 ke atas** ditandatangani *release key* yang berbeda. Android tidak
mengizinkan memperbarui aplikasi dengan tanda tangan yang berbeda — dan pada
banyak merek HP (Xiaomi/MIUI, OPPO/ColorOS, vivo, Realme) galatnya tampil
sebagai:

> **"App not installed as package appears to be invalid"**

bukan sebagai "konflik paket". Jadi:

1. Buka **Setelan → Aplikasi** (Settings → Apps).
2. Cari **Pine Wallet** — atau **Pyramids Wallet** (nama lama, applicationId
   sama: `site.massawallet.app`).
3. **Uninstall**.
4. Baru pasang APK v1.8.1+ dari Releases.

> Sekali selesai: mulai v1.8.1 ke atas semuanya memakai release key yang
> sama, sehingga pembaruan berikutnya terpasang **di tempat (in-place) tanpa
> uninstall lagi**.

/ **EN** — Releases up to v1.8.0 were debug-signed; v1.8.1+ uses a dedicated
release key. Android refuses to update a debug-signed install with a
differently-signed APK, which many OEM skins report as "App not installed as
package appears to be invalid". Uninstall the old app once; all later
updates install in place.

## 3. Langkah instalasi

1. Unduh APK dari halaman
   [Releases](https://github.com/SecretArrow/Massa-Wallet/releases) langsung
   di browser HP.
2. Buka file yang terunduh (notifikasi atau lewat aplikasi *Files*).
3. Saat diminta, izinkan **"Install unknown apps"** untuk browser/aplikasi
   file yang Anda pakai (Setelan → Aplikasi → khusus → Izinkan dari sumber
   ini). Ini normal untuk APK di luar Play Store.
4. Jika **Play Protect** menampilkan peringatan pemindaian → **Install
   anyway / More details → Install anyway**. Wajar: APK di luar Play selalu
   dipindai ulang. Kode aplikasi ini terbuka penuh di repo ini.
5. Tunggu hingga "App installed", buka aplikasinya.

## 4. Verifikasi unduhan (SHA-256 & ukuran)

Unduhan terpotong/terkorup adalah penyebab tersering galat "package appears
to be invalid". Tabel ukuran byte persis + SHA-256 untuk setiap file **selalu
tercantum di isi (body) tiap Release** — bandingkan dengan file Anda:

- **Windows (CMD/PowerShell):** `certutil -hashfile PineWallet-app-arm64-v8a-release.apk SHA256`
- **Linux / macOS:** `sha256sum <file.apk>` / `shasum -a 256 <file.apk>`
- **Android:** aplikasi file manager yang menampilkan checksum (mis.
  Material Files), atau via ADB: `adb shell sha256sum /sdcard/Download/<file>.apk`
- **Ukuran byte** harus **persis sama** dengan tabel di release notes
  (mis. arm64 v1.9.0 = `50,974,423` byte). Selisih walau 1 byte = unduhan
  rusak → unduh ulang.

## 5. Troubleshooting

| Gejala | Penyebab paling mungkin | Solusi |
|---|---|---|
| **"App not installed as package appears to be invalid"** | ① Masih ada Pine/Pyramids Wallet lama (≤1.8.0, debug-signed) terpasang · ② unduhan terpotong · ③ file dimodifikasi aplikasi lain (cleaner/transfer app) | ① Uninstall versi lama dulu (bagian 2) · ② bandingkan ukuran byte & SHA-256 (bagian 4), unduh ulang · ③ unduh ulang langsung di HP, jangan pindahkan lewat aplikasi yang mengompres ulang |
| **"App not installed"** (tanpa keterangan) | Salah arsitektur (arm64 dipasang di HP 32-bit, dsb.) atau storage penuh | Pasang `PineWallet-universal-release.apk`; pastikan sisa storage ≥ 1 GB |
| **"App not installed as package conflicts with an existing package"** | Konflik tanda tangan dengan instalasi lama | Sama dengan bagian 2 — uninstall dulu |
| **"App not installed as a newer version is already installed"** | versionCode terpasang lebih tinggi (mis. sempat pasang build CI yang lebih baru) | Uninstall dulu, lalu pasang rilis yang diinginkan |
| Proses install berhenti di *Stalling…* / *Pending* | Installer session macet, storage/instalasi lain menunggu | Restart HP, ulangi install |
| **"App not installed (SDK version not supported)"** | Android di bawah 7.0 (minSdk 24) | Perangkat tidak didukung — butuh Android 7.0+ |
| Terpasang tapi tampil "Pine Wallet" versi lama | Benar-benar update in-place; cek versi di More → Settings | Pastikan mengunduh dari tag rilis terbaru |

## 6. Keamanan

- Unduh **hanya** dari halaman Releases resmi:
  `https://github.com/SecretArrow/Massa-Wallet/releases`
- Sertifikat penandatangan rilis (SHA-256):
  `7A:E2:22:80:AB:9E:E7:11:82:3E:71:A4:06:18:FA:48:4E:61:07:B9:42:28:DB:33:26:AB:CD:E3:B4:04:94:E9`
- APK rilis diverifikasi otomatis di CI (`apksigner verify`, skema v1+v2+v3)
  sebelum diunggah ke Release; detail teknis di [docs/SIGNING.md](SIGNING.md).

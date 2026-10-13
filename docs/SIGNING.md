# Signing — Kunci Rilis APK

Setiap APK rilis (tag `v*`) ditandatangani otomatis di CI dengan release key
**pine-wallet**. Kunci tidak pernah disimpan sebagai file biasa di repo —
hanya sebagai satu arsip terenkripsi AES-256 yang di-commit:
`key-sign-apk.zip`.

## Berkas & rahasia

| Item | Lokasi | Keterangan |
|---|---|---|
| `key-sign-apk.zip` | root repo (ter-commit) | Berisi `pine-release.keystore`, dienkripsi **AES-256** (format WinZip-AES; `unzip` standar tidak bisa membuka — pakai `7z`/pyzipper) |
| `KEY_SIGN_PASSWORD` | GitHub Actions secret | Password zip sekaligus password keystore. **Tidak pernah di-commit** |
| `android/key.properties` | dibuat sementara saat build | Dibuat CI/script, dihapus setelah selesai, sudah di-.gitignore |
| `*.keystore` (hasil unzip) | di-.gitignore | Tidak akan pernah masuk git secara tidak sengaja |

## Detail kunci

- Alias: `pine-wallet`
- Algoritma: RSA 4096, SHA384withRSA, PKCS12
- Validity: 10.950 hari (~30 tahun, s/d Oktober 2056)
- Sertifikat SHA-256:
  `7A:E2:22:80:AB:9E:E7:11:82:3E:71:A4:06:18:FA:48:4E:61:07:B9:42:28:DB:33:26:AB:CD:E3:B4:04:94:E9`

Fingerprint di atas adalah identitas aplikasi (dipakai untuk verifikasi
kepemilikan, mis. API dengan pembatasan signature). Selama memakai kunci
yang sama, APK tetap ter-update in-place (applicationId `site.massawallet.app`).

## Alur di CI (`release.yml` → job `build-apk`)

1. **Restore** — `key-sign-apk.zip` diekstrak ke `$RUNNER_TEMP/signing`
   dengan secret `KEY_SIGN_PASSWORD` (via `7z`), lalu `android/key.properties`
   dibuat menunjuk ke keystore tersebut. Fingerprint dicetak ke job summary.
2. **Build** — Gradle memakai `signingConfigs.release`; bila secret/zip tidak
   ada, fallback ke debug key agar CI tetap hijau (ada warning di log).
3. **Verify** — `apksigner verify --print-certs` dijalankan pada tiap APK
   split, hasilnya masuk job summary.
4. **Wipe** — hasil unzip + `key.properties` dihapus dari runner
   (step `if: always()`, dijalankan walau build gagal).

## Sign manual di lokal

```bash
# password tidak boleh disimpan di file — isi via env sesi
export KEY_SIGN_PASSWORD='...'

# bungkus perintah build apa pun; kunci aktif selama perintah berjalan,
# hasil unzip otomatis dihapus setelahnya (sukses maupun gagal):
scripts/with_signing_key.sh flutter build apk --release --split-per-abi
```

`with_signing_key.sh` mengekstrak zip (7z; fallback python+pyzipper),
menulis `android/key.properties`, menjalankan perintah, lalu SELALU
menghapus hasil unzip + `key.properties` (trap EXIT).

## Ekstrak manual (tanpa script)

```bash
export KEY_SIGN_PASSWORD='...'

# buka ke folder sementara
7z x key-sign-apk.zip -p"$KEY_SIGN_PASSWORD" -o/tmp/signing
# atau, tanpa 7z:
python3 -c "import os,pyzipper; z=pyzipper.AESZipFile('key-sign-apk.zip'); z.setpassword(os.environ['KEY_SIGN_PASSWORD'].encode()); z.extractall('/tmp/signing')"

# …pakai key-nya…

# …hapus setelah selesai
rm -rf /tmp/signing
```

## Aturan keamanan

- Password TIDAK PERNAH ditulis ke file mana pun di repo (workflow, script,
  issue, README — semuanya dilarang). Hanya dua tempat: GitHub secret
  `KEY_SIGN_PASSWORD` dan hafalan pemilik.
- Kehilangan kunci = tidak bisa update in-place (pengguna harus
  uninstall → install ulang). Simpan password dengan aman.
- Bila kunci terkompromikan: buat keystore baru, naikkan versionCode, dan
  distribusikan sebagai rilis besar (tidak ada migrasi otomatis).
- Zip di-commit memakai AES-256 (bukan ZipCrypto `zip -P` yang lemah dan
  bisa diserak known-plaintext).

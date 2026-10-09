<div align="center">

# 🔐 Massa Wallet

**Secure self-custodial Flutter wallet for the Massa blockchain**

*Wallet self-custodial aman untuk blockchain Massa (Flutter)*

[![CI](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/ci.yml/badge.svg)](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/ci.yml)
[![E2E](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/e2e.yml/badge.svg)](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/e2e.yml)
[![Auto-fix](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/autofix.yml/badge.svg)](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/autofix.yml)
[![Release](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/release.yml/badge.svg)](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/release.yml)

Flutter • Android • Bilingual (🇮🇩 Indonesia / 🇬🇧 English)

</div>

---

## ⚡ What is this? / Apa ini?

**EN** — A production-grade, self-custodial mobile wallet for the [Massa blockchain](https://massa.net), built with Flutter. It runs as a **light client** talking to Massa's public JSON-RPC v2 API (or your own node), with a fully local crypto stack ported 1:1 from the official `@massalabs/massa-web3` SDK and validated against its official test vectors. Includes staking, smart-contract read-only calls, background balance sync with income notifications, hardware-backed key storage, biometric unlock, and an experimental "connect to your own node" mode.

**ID** — Wallet mobile self-custodial kualitas production untuk [blockchain Massa](https://massa.net), dibangun dengan Flutter. Berjalan sebagai **light client** yang terhubung ke API publik Massa JSON-RPC v2 (atau node milik Anda sendiri), dengan tumpukan kripto lokal yang diporting 1:1 dari SDK resmi `@massalabs/massa-web3` dan divalidasi terhadap test vector resminya. Termasuk staking, panggilan read-only smart contract, sinkronisasi saldo latar belakang dengan notifikasi, penyimpanan kunci hardware-backed, buka kunci biometrik, dan mode eksperimental "hubungkan ke node sendiri".

---

## 📐 Architecture / Arsitektur

```text
┌───────────────────────────────────────────────────────────────┐
│                     Massa Wallet (Flutter)                     │
├───────────────┬───────────────────────────────────────────────┤
│   UI Layer    │  Onboarding · Dashboard · Send/Receive (QR)   │
│ (Bilingual)   │  Staking · Contracts · Node mode · Settings   │
├───────────────┴───────────────────────────────────────────────┤
│  Services: WalletProvider · Settings · Security (biometric +  │
│  auto-lock + FLAG_SECURE) · BackgroundSync (foreground svc)   │
├───────────────────────────────────────────────────────────────┤
│  Core crypto (pure Dart, vector-verified): Base58Check,       │
│  Ed25519, BLAKE3, varint, OperationSerializer, KeystoreFile   │
├───────────────────────────────────────────────────────────────┤
│  API: MassaRpcClient (JSON-RPC v2) → Buildnet / Mainnet /     │
│  custom node (http://127.0.0.1:33035 via Termux, LAN, VPS)    │
└───────────────────────────────────────────────────────────────┘
```

### Crypto compatibility / Kompatibilitas kripto

All wire formats are byte-identical to `@massalabs/massa-web3` v5 — proven by unit tests using the SDK's **official test vectors**:

*Semua format kawat identik byte dengan `@massalabs/massa-web3` v5 — dibuktikan unit test menggunakan **test vector resmi** SDK:*

| Object | Format | Status |
|---|---|---|
| Private key | `S` + base58check(varint(0) + 32B seed) | ✅ vector-verified |
| Public key | `P` + base58check(varint(0) + 32B pubkey) | ✅ vector-verified |
| Address | `AU` + base58check(varint(0) + blake3(versioned pubkey)) | ✅ vector-verified |
| Signature | base58check(varint(0) + 64B) (no prefix) | ✅ vector-verified |
| Operation | LEB128 fields, type 0–4 (Tx, RollBuy, RollSell, ExecuteSC, CallSC) | ✅ vector-verified |
| Canonical | u64BE(chainId) ‖ versioned pubkey ‖ serialized op | ✅ vector-verified |
| Keystore file | PBKDF2-HMAC-SHA256 (600k) + AES-256-GCM (Massa Standard) | ✅ vector-verified |

Chain IDs: **Mainnet** `77658377` · **Buildnet** `77658366`
RPC: `https://mainnet.massa.net/api/v2` · `https://buildnet.massa.net/api/v2`

---

## 🧩 Wallet + Node + Background: the honest answer / Jawaban jujur soal wallet + node + background

**EN** — Massa full nodes are written in Rust and currently need **~4 cores + 8 GB RAM** (per the official FAQ). Embedding a full node inside a phone app is technically possible (cross-compile Rust with `cargo-ndk`, run inside an Android foreground service) but is impractical today: battery drain, thermal throttling, storage growth, and most phones have <8 GB RAM to spare. Every serious mobile wallet (including the community's MassaConnect) therefore uses the **light client** pattern — sign locally, read via RPC. This app implements that properly, and adds an honest **Node mode (experimental)**.

**ID** — Full node Massa ditulis dalam Rust dan saat ini butuh **~4 core + 8 GB RAM** (sesuai FAQ resmi). Menanam full node di dalam aplikasi HP secara teknis memungkinkan (cross-compile Rust dengan `cargo-ndk`, dijalankan dalam foreground service Android) tapi tidak praktis saat ini: boros baterai, throttling panas, storage membengkak, dan kebanyakan HP punya RAM <8 GB. Semua wallet mobile serius (termasuk MassaConnect dari komunitas) memakai pola **light client** — tanda tangan lokal, baca via RPC. Aplikasi ini mengimplementasikannya dengan benar, plus **Node mode (eksperimental)** yang jujur.

| Mode | How it works / Cara kerja | Use case |
|---|---|---|
| **Light client** *(default)* | Public RPC (Buildnet/Mainnet), keys stay on device | Daily use / Pemakaian harian |
| **Node mode** *(experimental)* | Point the app at `http://127.0.0.1:33035` — run a massa-node on-device via [Termux](https://termux.dev) (Proot/Ubuntu) or on your LAN/VPS. The app's background service keeps polling **your** node. | Self-sovereignty / Kedaulatan penuh |

> Roadmap for a true in-app node / *Peta jalan node di dalam app*: cross-compile `massa-node` (Rust → `aarch64-linux-android` via cargo-ndk) → bundle as a foreground-service executable → IPC over localhost JSON-RPC. The `NodeModeService` class already isolates this integration point, so the UI/wallet layer will not change. / *Cross-compile massa-node, bundle sebagai foreground-service executable, IPC via localhost JSON-RPC. Class NodeModeService sudah mengisolasi titik integrasi ini.*

### Background processes / Proses latar belakang

- **Foreground service** (`flutter_background_service`, `dataSync` type) keeps syncing balances every N minutes even when the app is closed
- *Foreground service terus menyinkronkan saldo tiap N menit meski aplikasi ditutup*
- **Local notifications** alert you on balance changes (income detection)
- *Notifikasi lokal saat saldo berubah (deteksi dana masuk)*
- **Boot persistence** via `RECEIVE_BOOT_COMPLETED`
- *Otomatis jalan lagi setelah HP di-restart*

---

## 🛡️ Security model / Model keamanan

| Layer | Implementation |
|---|---|
| Key storage | `flutter_secure_storage` → Android Keystore (hardware-backed), AES-GCM |
| Unlock | `local_auth` — fingerprint / face / device PIN (BiometricPrompt) |
| Auto-lock | Idle timer (1/2/5 min), re-lock on app pause |
| Anti-screenshot | `FLAG_SECURE` via platform channel — screen recording & recents preview blocked |
| Privacy | Hide-balances toggle |
| Export | Massa Standard keystore file (PBKDF2-SHA256 600k + AES-256-GCM), password-protected |
| Mainnet guard | Confirmation dialog before switching to mainnet |

---

## 🚀 Getting started / Mulai

### Build the app / Build aplikasi

```bash
git clone https://github.com/SecretArrow/Massa-Wallet.git
cd Massa-Wallet
flutter pub get
flutter run                 # debug
flutter build apk --release --split-per-abi   # release APKs
```

Or simply download a signed APK from [Releases](https://github.com/SecretArrow/Massa-Wallet/releases) — every `v*` tag triggers an automatic release build. / *Atau unduh APK dari Releases — setiap tag `v*` otomatis memicu build release.*

### Get test MAS (Buildnet faucet) / Dapatkan MAS test

1. Create a wallet in the app → copy your `AU...` address / *Buat wallet → salin alamat*
2. Visit / *Kunjungi* https://faucet.buildnet.massa.net/
3. Paste address, receive test MAS / *Tempel alamat, terima MAS test*

### CI/CD pipelines / Pipeline CI/CD

| Workflow | Trigger | What it does / Yang dilakukan |
|---|---|---|
| **CI** | every push/PR | `dart format` check (report), `flutter analyze`, all unit+widget tests, coverage artifact — *fast, no Gradle, ~3 min* |
| **Auto-fix** | weekly + manual | `dart fix --apply` + `dart format` → re-tests → opens a **PR automatically** |
| **E2E** | weekly + manual | Integration test on a real Android emulator (KVM, api-33) |
| **Release** | tag `v*` + manual | analyze → test → `flutter build apk --split-per-abi` → **GitHub Release with APKs** |

Build time optimizations / *Optimasi waktu build*: pub cache via `flutter-action`, Gradle cache via `setup-gradle`, `concurrency` cancellation, no-emulator CI path, split-per-ABI APKs.

---

## 📁 Project layout / Struktur project

```text
lib/
├── core/
│   ├── crypto/          # base58check, varint, massa_keys (Ed25519+BLAKE3),
│   │                    # operation_serializer, keystore_file (PBKDF2+AES-GCM)
│   ├── api/             # massa_rpc (JSON-RPC v2), massa_models, massa_amount
│   ├── services/        # wallet_repository (secure store), wallet_provider,
│   │                    # settings, security_service, background_sync,
│   │                    # node_mode_service (experimental)
│   └── i18n/            # bilingual ID/EN (no codegen)
├── features/            # onboarding, wallet, send, receive, staking,
│                        # contracts, node, settings
└── ui/                  # theme + shared widgets
test/                    # 29 tests: official vectors, RPC mocks, widgets
integration_test/        # e2e on emulator
android/                 # Gradle, manifest, MainActivity (FLAG_SECURE)
.github/workflows/       # ci · autofix · e2e · release
```

---

## ⚠️ Disclaimer / Penafian

**EN** — Self-custodial means **you** are responsible for your keys. The secret key (`S...`) is the only way to recover the wallet. This software is provided as-is, without warranty. Audit before using with real funds on mainnet.

**ID** — Self-custodial berarti **Anda** bertanggung jawab atas kunci Anda. Secret key (`S...`) adalah satu-satunya cara memulihkan wallet. Perangkat lunak ini disediakan apa adanya, tanpa jaminan. Lakukan audit sebelum digunakan dengan dana nyata di mainnet.

## 📜 License

MIT — see [LICENSE](LICENSE).

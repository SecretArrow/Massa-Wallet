<div align="center">

# 🔺 Pyramids Wallet

**Secure self-custodial Flutter wallet for the Massa blockchain — with a built-in dApp browser**

*Wallet self-custodial aman untuk blockchain Massa (Flutter)*

[![CI](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/ci.yml/badge.svg)](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/ci.yml)
[![E2E](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/e2e.yml/badge.svg)](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/e2e.yml)
[![Auto-fix](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/autofix.yml/badge.svg)](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/autofix.yml)
[![Release](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/release.yml/badge.svg)](https://github.com/SecretArrow/Massa-Wallet/actions/workflows/release.yml)

Flutter • Android • Material Design 3 (dark/light/system) • Bilingual (🇮🇩 Indonesia / 🇬🇧 English)

</div>

---

## ⚡ What is this? / Apa ini?

**EN** — A production-grade, self-custodial mobile wallet for the [Massa blockchain](https://massa.net), built with Flutter. It runs as a **light client** talking to Massa's public JSON-RPC v2 API (or your own node), with a fully local crypto stack ported 1:1 from the official `@massalabs/massa-web3` SDK and validated against its official test vectors. Includes a **built-in DApp browser for on-chain `.massa` websites (DeWeb)** with an injected `window.massa` provider, **MRC-20 token management**, activity history, address book, staking, smart-contract calls, background balance sync with income notifications, hardware-backed key storage, biometric unlock, dark/light themes, an experimental "connect to your own node" mode, and — new in v1.3.0 — a **true hybrid**: pick between Public RPC, your own Custom RPC, or an **embedded real massa-node binary running inside the app sandbox** (Buildnet, experimental).

**ID** — Wallet mobile self-custodial kualitas production untuk [blockchain Massa](https://massa.net), dibangun dengan Flutter. Berjalan sebagai **light client** yang terhubung ke API publik Massa JSON-RPC v2 (atau node milik Anda sendiri), dengan tumpukan kripto lokal yang diporting 1:1 dari SDK resmi `@massalabs/massa-web3` dan divalidasi terhadap test vector resminya. Termasuk **browser dApp bawaan untuk situs `.massa` on-chain (DeWeb)** dengan provider `window.massa` terinjeksi, **pengelolaan token MRC-20**, riwayat aktivitas, buku alamat, staking, panggilan smart contract, sinkronisasi saldo latar belakang dengan notifikasi, penyimpanan kunci hardware-backed, buka kunci biometrik, tema gelap/terang, mode eksperimental "hubungkan ke node sendiri", dan — baru di v1.3.0 — **hybrid sejati**: pilih antara RPC Publik, RPC Kustom milik Anda, atau **node massa-node asli yang berjalan di dalam sandbox aplikasi** (Buildnet, eksperimental).

## 🆕 What's new in v1.4.0

| Feature | Description / Keterangan |
|---|---|
| 🔺 **Pyramids Wallet rebrand** | New name, new golden-pyramid app icon (regenerated launcher + adaptive icons). Same applicationId, so existing installs update in place. / *Nama baru & ikon piramida emas; applicationId tetap sehingga instalasi lama bisa update.* |
| 🏠 **Browser start page** | The dApp browser now opens on a rich start page: curated Massa dApps (explorers, docs, faucet info), on-chain DeWeb sites, **bookmarks** and **persistent history** (star any page to bookmark). / *Halaman awal browser berisi dApp Massa pilihan, situs DeWeb, bookmark, dan riwayat permanen.* |
| ✍️ **Canonical dApp `signOperation`** | dApp signing requests are now decoded (operation type, recipient, amount, fee) and signed with the correct canonical bytes — `u64BE(chainId) ‖ versionedPubkey ‖ serializedOp` — matching massa-web3 exactly. Opaque blobs are flagged. / *Permintaan tanda tangan dApp kini didekode dan ditandatangani dengan byte kanonik yang benar.* |
| 🚰 **Buildnet faucet helper** | Receive screen (buildnet) tries the legacy HTTP faucet first; when it is offline (it currently is — the official faucet is the Discord `#buildnet-faucet` channel), a fallback sheet offers one-tap Discord + docs links opened in the in-app browser. / *Tombol faucet buildnet dengan fallback ke kanal Discord resmi.* |
| 🧹 **Memory & CPU hygiene** | WebView state cleanup, capped persisted history (30 entries), per-operation RPC client disposal, theme-aware light/dark polish. / *Kebersihan memori: pembersihan WebView, riwayat terbatas, penutupan klien RPC per operasi.* |

## 🆕 What's new in v1.3.0

| Feature | Description / Keterangan |
|---|---|
| 🧬 **Embedded node — a real massa-node inside the app** | The official `massa-node` binary (pinned to the `DEVN.30.2` tag — the version buildnet runs today) is cross-compiled in CI to Android arm64 (cargo-ndk + NDK) and bundled into the APK as `jniLibs/arm64-v8a/libmassa_node.so`. Android extracts it into `nativeLibraryDir` — the only W^X-compliant location where an app may `exec()` a binary — and the app spawns it as a child process **inside its own sandbox**: same UID, no root, no Termux, RPC bound to `127.0.0.1` only. The foreground service keeps it alive and restarts it if it dies. This is the practical equivalent of a JNI-integrated node for a Rust binary (a binary crate cannot be loaded as an .so into a process). / *Binary `massa-node` resmi dibundel dan dijalankan langsung di dalam sandbox aplikasi — tanpa root, tanpa Termux, RPC loopback saja. Foreground service menjaganya tetap hidup.* |
| 🔀 **Connection modes — user's choice** | Node settings now offers three modes as selectable cards: **Public RPC** (official endpoints, light client), **Custom RPC** (your own node — LAN/VPS/Termux), **Embedded node** (in-app, Buildnet). The choice is persisted, every feature (balances, send, staking, MNS, DeWeb, MRC-20, deferred calls, background sync) honors `effectiveEndpoint`, and switching is instant. Embedded mode is Buildnet-only; on Mainnet the wallet keeps using the public RPC automatically. / *Tiga mode koneksi — RPC Publik, RPC Kustom, atau Node Tertanam — dipilih pengguna, berlaku di seluruh fitur.* |
| 🎨 **Material 3 polish** | Full M3 design system: seeded color schemes, InkSparkle ripples, 28 dp bottom sheets with drag handle, rounded dialogs, updated chips/segmented buttons/switches, theme-aware components everywhere. / *Desain Material 3 modern menyeluruh untuk light & dark.* |
| 📐 **Edge-to-edge layout** | Content draws behind the status bar and the gesture navigation bar with transparent system bars and per-brightness icon colors — no more collision with the Android system UI. / *Konten aman dari nav bar bawah dan status bar atas — sistem bar transparan, ikon menyesuaikan tema.* |
| 🌗 **Theme switch, M3 edition** | Dark / Light / System as an M3 `SegmentedButton` in Settings. / *Tema Gelap/Terang/Sistem dengan SegmentedButton.* |

## 🆕 What's new in v1.2.0

| Feature | Description / Keterangan |
|---|---|
| 🔄 **Roll auto-compound** | When a new staking cycle starts and rewards have landed (deferred credits), the surplus above a 1 MAS fee reserve is automatically reinvested into **whole rolls** (100 MAS each). Runs from the staking screen AND the background sync isolate, with a decision log (cycle, rolls bought, op id). / *Saat siklus baru dimulai dan reward masuk, surplus otomatis direinvestasi jadi roll utuh — jalan di layar staking maupun service latar belakang.* |
| 👁️ **Watch-only addresses** | Track any address without a private key: balance, rolls and history visible; signing/spending impossible (guarded at provider level). Add via Import → "Watch only". / *Pantau alamat tanpa private key — lihat saldo & riwayat, tidak bisa kirim.* |
| 🌐 **MNS everywhere** | Type `name.massa` (or a bare domain) in Send or Add-contact: it resolves through the MNS contracts and saves the domain into the contact. / *Kirim ke `nama.massa` langsung — resolusi otomatis via kontrak MNS, tersimpan di buku alamat.* |
| 💾 **Encrypted multi-account backup** | Export **all accounts + address book into ONE `.massabak` file** (PBKDF2-SHA256 600k → AES-256-GCM, same primitives as the Massa Standard keystore). Restore merges back missing accounts/contacts; watch-only entries carry no key material. Settings → Encrypted backup / Restore backup. / *Ekspor semua akun ke satu file terenkripsi; pulihkan kapan pun.* |
| 📱 **Homescreen balance widget** | Android AppWidget (RemoteViews) showing balance, rolls, address and network. Refreshed by the app and background sync, self-refresh every 30 min. / *Widget saldo di homescreen Android.* |
| 🍎 **iOS build (unsigned)** | New `ios/` platform + CI job `build-ios` (macos, `--no-codesign`) producing a sideloadable `Payload/Runner.app` zip on every tag. See `docs/DISTRIBUTION.md` for Play Store (AAB), F-Droid (fdroiddata recipe included) and TestFlight paths. / *Build iOS unsigned di CI + panduan distribusi Play Store/F-Droid/iOS.* |
| ✅ **Node binary honesty** | The wallet bundles **no node binary** — Node mode now shows the official massalabs release links and the `sha256sum` verification step right in the app. / *App tidak membundel binary node; layar Node kini menampilkan sumber resmi + cara verifikasi checksum.* |

## 🆕 What's new in v1.1.0

| Feature | Description / Keterangan |
|---|---|
| 🌐 **DApp Browser (DeWeb)** | Browse websites stored **directly on the blockchain** (`name.massa`). Files are fetched from the smart-contract datastore (sha256 path hash + 64 KB chunks — the official DeWeb standard) and served to the WebView via a loopback-only local server. / *Jelajahi situs yang tersimpan langsung di blockchain; file diambil dari datastore SC dan disajikan via server lokal 127.0.0.1.* |
| 🪝 **`window.massa` provider** | dApps running inside the browser can connect through an injected provider with **user-confirmed** dialogs for connect / sign / send / buy-rolls / sell-rolls / callSC. Every action requires explicit approval. / *dApp terhubung lewat provider terinjeksi; setiap aksi wajib konfirmasi pengguna.* |
| 🪙 **MRC-20 tokens** | Official token registry (WMAS, USDC, DAI, WETH, WBTC…) + add custom tokens by address. Balances read from `BALANCE<addr>` datastore entries, transfers compute the storage-cost coins automatically. / *Registry token resmi + token kustom; transfer otomatis menghitung biaya storage.* |
| 🧾 **Activity history** | Local operation log with on-chain finality status (the public RPC has no history indexer — this is the honest approach). / *Log operasi lokal dengan status finalitas on-chain.* |
| 📒 **Address book** | Save contacts, pick from the send screen. / *Simpan kontak, pilih langsung di layar kirim.* |
| 💱 **Price ticker** | MAS price in USD/IDR (CoinGecko, offline-tolerant). / *Harga MAS USD/IDR, tahan offline.* |
| 🎨 **Themes** | Dark / light / follow-system. / *Gelap / terang / ikuti sistem.* |
| ⏱️ **Deferred calls (ASC)** | Slot planner (time ↔ period/thread using the live node clock), booking quotes via `get_deferred_call_quote`, lookup by deferred-call ID, and guided booking through a scheduler contract (CallSC, e.g. the official `deferred-call-manager` example). / *Perencana slot, harga booking on-chain, pencarian ID, dan pemesanan terpandu via kontrak scheduler.* |

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

## 🌐 How the DeWeb browser works / Cara kerja browser DeWeb

Websites on Massa are ordinary smart contracts whose **datastore** holds the files. The in-app browser implements the official standard (verified against `massalabs/DeWeb` server code **and live buildnet data**):

*Situs di Massa adalah smart contract biasa yang menyimpan file di **datastore**-nya. Browser bawaan mengimplementasikan standar resmi (diverifikasi terhadap kode server `massalabs/DeWeb` dan data live buildnet):*

```text
1. name.massa ──dnsResolve──▶ MNS contract ──▶ SC address (AS1…)
   (mainnet: AS1q5hUf… · buildnet: AS12qKAVj…)
2. path "x" (no leading slash; "" → "index.html") → hash = sha256(path)
3. chunk count  = datastore[\x01FILE + hash + \x04CHUNK_NB]        (u32 LE)
4. content      = concat(datastore[\x01FILE + hash + \x03CHUNK + i]) for i < n
                  (64 KB chunks)
5. served over http://127.0.0.1:<random port> (cleartext allowed ONLY for
   loopback via network_security_config) with proper MIME types
```

### `window.massa` API (injected provider)

dApps inside the browser can use the injected provider — methods are confirmed by native dialogs before anything is signed:

```js
await window.massa.enable();              // → [accountAddress]
await window.massa.accounts();            // → [{address, name}]
await window.massa.network();             // → {chainId, name}
await window.massa.balance(address?);     // → "12.5" (MAS)
await window.massa.sign(data);            // → ed25519 signature (base58check)
await window.massa.sendTransaction(to, amountMAS);
await window.massa.buyRolls(countMAS);    // 1 roll = 100 MAS
await window.massa.sellRolls(countMAS);
await window.massa.callSC(target, func, argsBase58, coinsMAS);
// or the generic surface:
await window.massa.request({ method: 'enable', params: {} });
```

> The provider listens for the `massa#initialized` event, so dApps can detect it immediately. No signing ever happens without an explicit user approval dialog. / *Provider memancarkan event `massa#initialized`; tidak ada tanda tangan tanpa dialog persetujuan eksplisit.*

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
│   │                    # operation_serializer, keystore_file, sc_args
│   ├── api/             # massa_rpc (JSON-RPC v2), massa_models, massa_amount
│   ├── contracts/       # mns_service (name resolution), deweb_service +
│   │                    # local_site_server (on-chain websites),
│   │                    # mrc20_service (tokens), web3_provider (window.massa)
│   ├── services/        # wallet_repository (secure store), wallet_provider,
│   │                    # settings, security_service, background_sync,
│   │                    # activity_history, address_book, price_service,
│   │                    # node_mode_service (experimental)
│   └── i18n/            # bilingual ID/EN (no codegen)
├── features/            # onboarding, wallet, send, receive, staking,
│                        # contracts, node, settings, browser (DeWeb),
│                        # tokens, history, address book
└── ui/                  # dark+light themes + shared widgets
test/                    # 65 tests: official vectors, live-format RPC mocks,
                         # MNS/DeWeb/MRC-20/services, widgets
integration_test/        # e2e on emulator
android/                 # Gradle, manifest, MainActivity (FLAG_SECURE),
                         # network_security_config (cleartext loopback only)
.github/workflows/       # ci · autofix · e2e · release
```

---

## ⚠️ Disclaimer / Penafian

**EN** — Self-custodial means **you** are responsible for your keys. The secret key (`S...`) is the only way to recover the wallet. This software is provided as-is, without warranty. Audit before using with real funds on mainnet.

**ID** — Self-custodial berarti **Anda** bertanggung jawab atas kunci Anda. Secret key (`S...`) adalah satu-satunya cara memulihkan wallet. Perangkat lunak ini disediakan apa adanya, tanpa jaminan. Lakukan audit sebelum digunakan dengan dana nyata di mainnet.

## 📜 License

MIT — see [LICENSE](LICENSE).

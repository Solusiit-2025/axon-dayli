# Axon Dayli

Aplikasi Android untuk mengelola kegiatan harian, jadwal kerja dengan progres,
keuangan pribadi, dan aset (dipisah antara **Pribadi** dan **Perusahaan**) —
lengkap dengan pengingat kegiatan.

Prinsip utama: **offline-first**. Semua data disimpan di HP lebih dulu, aplikasi
tetap berjalan tanpa internet, lalu perubahan dikirim ke server saat online.

```
apps/
  mobile/   Aplikasi Flutter (Android) + database lokal SQLite (Drift)
  server/   API Node.js + Fastify + Prisma + PostgreSQL
docs/
  PRD-Aplikasi-Kegiatan-Harian.md   Dokumen kebutuhan produk
scripts/
  dev-db.ps1        Nyalakan/matikan PostgreSQL dev (port 5544)
  smoke-test.mjs    Uji end-to-end API (36 pemeriksaan)
  seed-demo.mjs     Isi akun demo dengan data contoh
  serve-web.mjs     Sajikan hasil build web di http://127.0.0.1:8080
  run-device.ps1    Jalankan app di HP via USB + adb reverse
```

## 1. Yang perlu terpasang

| Kebutuhan | Versi yang dipakai |
| --- | --- |
| Flutter | 3.41.x (stable) |
| Node.js | 24.x |
| PostgreSQL | 18 (hanya folder `bin` yang dipakai) |
| JDK | 21 (bawaan Android Studio) |
| Android SDK | 36.x |

## 2. Menjalankan (urutannya penting)

### a. Nyalakan database dev

```powershell
.\scripts\dev-db.ps1 start
```

Script ini membuat cluster PostgreSQL **terpisah** di folder temp
(`%LOCALAPPDATA%\Temp\opencode\pgdev`), port **5544**, autentikasi trust, dan
database `dailypilot`.

> Kenapa tidak memakai service PostgreSQL yang sudah ada? Password user
> `postgres` tidak diketahui, dan cluster di dalam folder project crash dengan
> kode `0xC0000142`. Jadi script membuat cluster sendiri — service 5432 kamu
> tidak disentuh.

Perintah lain:

```powershell
.\scripts\dev-db.ps1 stop     # matikan
.\scripts\dev-db.ps1 reset    # hapus semua data dev, buat ulang dari nol
```

### b. Siapkan server

```powershell
cd apps\server
npm install
npx prisma migrate dev     # bikin tabel
npm run dev                # jalan di http://127.0.0.1:4000
```

Cek cepat: <http://127.0.0.1:4000/health> → `{"ok":true,...}`

Konfigurasi ada di `apps/server/.env` (sudah disiapkan untuk dev).
Kalau database baru di-reset, jalankan `npm run db:migrate` lagi.

### c. Jalankan aplikasi

**Di browser (paling cepat):**

```powershell
cd apps\mobile
flutter build web
cd ..\..
node scripts\serve-web.mjs        # http://127.0.0.1:8080
```

Data web disimpan di IndexedDB, jadi tetap jalan tanpa server API.
Mau langsung lihat data contoh? `node scripts\seed-demo.mjs` lalu masuk dengan
`demo@dailypilot.test` / `Demo12345`.

**Di Android:**

```powershell
cd apps\mobile
flutter pub get
dart run build_runner build     # hanya jika tabel Drift berubah
flutter run
```

Kalau HP terhubung lewat USB, pakai `.\scripts\run-device.ps1` — skrip ini
memasang `adb reverse tcp:4000 tcp:4000` sehingga HP memakai
`http://127.0.0.1:4000` (bebas masalah firewall). Tanpa kabel, isi alamat
server dengan IP LAN laptop.

Alamat server default adalah `http://127.0.0.1:4000` dan **tidak perlu diisi
di layar login**. Agar perangkat bisa mencapai server laptop:

- **HP via USB** -> jalankan `adb reverse tcp:4000 tcp:4000` (otomatis oleh
  `scripts/run-device.ps1`), lalu `127.0.0.1:4000` di HP mengarah ke laptop.
- **Emulator Android** -> `http://10.0.2.2:4000` (ubah di **Lainnya -> Alamat
  server**), atau pakai `adb reverse` juga.
- **Browser (Flutter web)** -> otomatis `http://127.0.0.1:4000`.
- Alamat bisa diubah kapan saja di **Lainnya -> Alamat server** (mis. untuk
  server produksi).

### Server sendiri (VPS)

Kalau server Axon Dayli dipasang di VPS di belakang nginx, naikkan batas ukuran
body — foto lampiran dikirim sebagai base64 di dalam payload sinkronisasi:

```nginx
server {
    # ...
    client_max_body_size 30m;   # default nginx hanya 1 MB → error 413
}
```

Server sendiri memakai batas 25 MB (`bodyLimit`). Aplikasi juga memecah batch
sinkronisasi otomatis (±800 KB per request) dan mengecilkan foto (maks 1600 px,
kualitas 70) supaya hemat kuota.

**Pengingat di Android:** aplikasi meminta izin notifikasi saat pertama kali
menyimpan pengingat. Agar alarm berbunyi tepat waktu:

1. Buka **Pengingat** → jika muncul kartu "Alarm tepat waktu belum diizinkan",
   ketuk **Izinkan alarm tepat waktu**.
2. Di pengaturan Samsung: **Baterai → Batas penggunaan latar belakang** →
   pastikan Axon Dayli tidak masuk daftar "Aplikasi tidur".
3. Tombol ikon lonceng-plus di kanan atas layar Pengingat = tes notifikasi
   10 detik.

Daftar akun baru dari aplikasi. Saat registrasi, server otomatis membuat dua
ruang kerja (Pribadi & Perusahaan) beserta kategori dan dompet awal, lalu
mengirimnya ke HP. Setelah login pertama, aplikasi bisa dipakai sepenuhnya
offline.

## 3. Fitur

- **Hari Ini** — ringkasan kegiatan hari ini, tenggat terdekat, progres kerja,
  saldo, dan pengingat berikutnya.
- **Kegiatan** — daftar tugas dengan filter status/pencarian, sub-tugas
  (checklist), progres, log progres, estimasi vs realisasi waktu, prioritas,
  tenggat, dan pengingat per tugas.
- **Jadwal kerja** — proyek + tugas dengan progres yang dipantau; grafik
  progres dan penyelesaian.
- **Keuangan** — transaksi pemasukan/pengeluaran (termasuk biaya admin),
  dompet, kategori, ringkasan bulanan, grafik per kategori, **anggaran
  bulanan** per kategori, dan catatan **utang/piutang** dengan pembayaran.
- **Aset** — daftar aset terpisah per ruang kerja, nilai sekarang, penyusutan
  garis lurus, riwayat valuasi, dan catatan perawatan.
- **Pengingat** — notifikasi lokal (tetap berbunyi tanpa internet), sekali /
  harian / mingguan, bisa dikaitkan ke tugas. Mengetuk notifikasi membuka
  detail tugas.
- **Kalender** — agenda dan tenggat per tanggal.
- **Pemisahan data** — ruang kerja Pribadi dan Perusahaan punya data, kategori,
  dompet, dan warna aksen sendiri. Tidak ada data yang tercampur.

## 4. Cara kerja sinkronisasi

- Setiap baris punya `id` UUID v7 yang dibuat di HP, `version`, `updatedAt`,
  `deletedAt` (tombstone), dan `deviceId`.
- Perubahan masuk ke tabel `outbox` di SQLite. Saat online (atau saat app
  dibuka / jaringan kembali), outbox dikirim ke `POST /sync/push` dalam batch
  maksimal 200 operasi.
- Setiap operasi punya `opId` unik → server idempoten, aman dikirim ulang.
- Konflik versi: server menolak `version <= versi tersimpan` dengan status
  `conflict`. Klien membuang operasi lokal tersebut lalu menarik versi server.
- Perubahan dari server diambil lewat `GET /sync/pull?cursor=<seq>`; `SyncLog.seq`
  menjadi kursor. Penghapusan dikirim sebagai tombstone (`deletedAt` terisi).
- Uang dikirim sebagai `number` (rupiah bulat), disimpan `BigInt` di PostgreSQL
  dan `int` di SQLite. Tanggal dikirim sebagai epoch milidetik.

## 5. Perintah bermanfaat

```powershell
# server
cd apps\server
npm run typecheck
npm test
npm run db:studio

# aplikasi
cd apps\mobile
flutter analyze
flutter test
flutter build apk --debug
flutter build web
cd ..\..
node scripts\serve-web.mjs
node scripts\seed-demo.mjs

# uji API end-to-end (server harus jalan)
node scripts\smoke-test.mjs
```

Build release memblokir HTTP biasa kecuali ke `10.0.2.2`, `127.0.0.1`, dan
`localhost` (lihat `android/app/src/main/res/xml/network_security_config.xml`).
Build debug mengizinkan HTTP ke jaringan lokal untuk pengujian di HP fisik.
Untuk produksi, pakai HTTPS.

Hasil build: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`
(untuk uji di HP, pakai build debug agar bisa terhubung ke server lokal).

## 6. Struktur kode aplikasi

```
apps/mobile/lib/
  app/          router, providers Riverpod, auth controller
  core/         tema, format uang & tanggal, notifikasi lokal
  data/
    local/      tabel Drift, database + query, mapper wire
    remote/     ApiClient (token refresh), session store
    sync/       SyncEngine + penjadwal sync
  features/     today, tasks, finance, planning, assets, calendar,
                reminders, settings, shell, auth, common
```

## 7. Belum dikerjakan (opsional)

- Transfer antar dompet (model sudah ada, UI/efek saldo sengaja ditunda).
- Enkripsi database lokal (SQLCipher).
- Tugas berulang otomatis (pengingat berulang sudah jalan).
- UI khusus proyek dan lampiran berkas.

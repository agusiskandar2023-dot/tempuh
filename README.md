# Tempuh

*Setiap kilometer yang kamu tempuh.* Aplikasi tracker lari, jalan kaki, jogging, dan sepeda (Flutter, Android).

Created by KangAIs.

## Unduh APK

Buka **Releases** di repo ini dari HP Android, unduh `Tempuh.apk` versi terbaru, lalu pasang
(izinkan "Instal aplikasi tidak dikenal" untuk browser bila diminta). Setiap push ke `main` membuat
rilis baru secara otomatis lewat GitHub Actions.

## Fitur versi 0.2

- Nama, ikon launcher adaptif (T-Rute), ikon notifikasi, dan tampilan sesuai mockup desain.
- Rekam GPS untuk 4 jenis olahraga: start, pause, lanjut, selesai.
- **Tetap merekam saat layar mati / HP sleep**: foreground service lokasi + notifikasi tetap + wake lock.
  Disarankan menekan kartu "Izinkan berjalan di latar belakang" di layar Rekam agar penghemat baterai
  tidak mematikan aplikasi.
- **Peta live** (OpenStreetMap): garis rute, posisi saat ini, kamera mengikuti; tombol kembali ke posisi.
- Metrik: jarak, waktu aktif vs total, pace / kecepatan, elevasi, split per km, estimasi kalori.
- Filter GPS: akurasi buruk, lonjakan posisi, dan drift saat diam dibuang.
- Offline-first: semua data di SQLite HP, checkpoint tiap 10 detik; sesi yang terputus bisa dipulihkan.
- Riwayat dengan filter olahraga, detail aktivitas dengan peta rute dan split.
- **Garmin Forerunner**:
  - Health Connect: baca sesi latihan 30 hari terakhir (jarak, kalori, detak jantung) yang disinkron
    Garmin Connect, dan tambahkan detak jantung Garmin ke aktivitas yang direkam HP.
  - Impor file `.FIT` (Garmin Connect web > aktivitas > Export Original) lengkap dengan rute.

## Struktur

```
lib/
  core/        tema, pembuat UUID
  data/        SQLite (sqflite) + repository
  domain/      metrik & filter GPS (Dart murni, diuji unit test)
  models/      Activity, TrackPoint, Split
  services/    tracking (geolocator), Health Connect, parser FIT
  screens/     Beranda, Rekam, Riwayat, Detail, Garmin
  widgets/     peta rute, stat tile
ci/            build.sh, patch Android, keystore debug
```

Folder `android/` dibuat otomatis oleh `ci/build.sh` (`flutter create` + `ci/patch_android.py`).

## Build lokal

```
bash ci/build.sh
```

Catatan: APK ditandatangani dengan keystore debug di `ci/` (cukup untuk pemakaian pribadi;
belum untuk rilis Play Store).

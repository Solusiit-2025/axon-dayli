# ─────────────────────────────────────────────────────────────
# Jalankan DailyPilot di HP yang terhubung lewat USB.
#
# Kenapa lewat USB + adb reverse?
#   - HP bisa akses server di laptop lewat http://127.0.0.1:4000
#     tanpa bergantung pada firewall Wi-Fi.
#   - Tidak perlu tahu IP LAN laptop.
#
# Pakai:
#   .\scripts\run-device.ps1              # jalankan flutter run
#   .\scripts\run-device.ps1 -InstallOnly # cuma pasang APK debug
# ─────────────────────────────────────────────────────────────

param(
    [switch]$InstallOnly
)

$ErrorActionPreference = 'Stop'

$Adb    = Join-Path $env:LOCALAPPDATA 'Android\sdk\platform-tools\adb.exe'
$Mobile = Join-Path $PSScriptRoot '..\apps\mobile'
$Apk    = Join-Path $Mobile 'build\app\outputs\flutter-apk\app-debug.apk'
$Port   = 4000

if (-not (Test-Path $Adb)) {
    "adb tidak ditemukan di $Adb"
    exit 1
}

function Get-Devices {
    & $Adb devices |
        Select-Object -Skip 1 |
        Where-Object { $_ -match '\tdevice$' } |
        ForEach-Object { ($_ -split '\t')[0].Trim() }
}

$devices = @(Get-Devices)

if ($devices.Count -eq 0) {
    @'
HP belum terdeteksi. Cek berurutan:

  1. Kabel harus kabel data (HP menampilkan indikator charging).
  2. Di HP: Setelan > Tentang ponsel > ketuk "Nomor build" 7x.
  3. Setelan > Opsi pengembang > "USB debugging" ON.
  4. Cabut-colok, pilih mode "File transfer/MTP", lalu izinkan
     dialog "Izinkan debugging USB?" (centang selalu izinkan).
  5. Coba port USB lain di laptop, hindari hub.

Kalau adb devices masih kosong padahal HP terisi daya, coba kabel lain.
Driver Samsung (kalau perlu): https://developer.samsung.com/android-usb-driver
'@
    exit 1
}

$serial = $devices[0]
"Perangkat: $serial"
& $Adb -s $serial reverse "tcp:$Port" "tcp:$Port" | Out-Null
"Server laptop dipetakan ke HP: http://127.0.0.1:$Port"

if ($InstallOnly) {
    if (-not (Test-Path $Apk)) {
        Set-Location $Mobile
        & flutter build apk --debug
    }
    & $Adb -s $serial install -r $Apk
    "APK terpasang. Buka DailyPilot, lalu isi alamat server http://127.0.0.1:$Port"
    exit 0
}

Set-Location $Mobile
& flutter run -d $serial

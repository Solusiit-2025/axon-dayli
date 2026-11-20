# ─────────────────────────────────────────────────────────────
# Database dev lokal untuk Axon Dayli
#
# Kenapa tidak memakai service PostgreSQL yang sudah terpasang?
#   - Password user `postgres` tidak diketahui.
#   - Cluster terpisah di dalam folder project gagal start
#     (backend crash 0xC0000142), kemungkinan karena ACL/OneDrive.
#
# Script ini membuat cluster sendiri di folder temp, port 5544,
# autentikasi trust (hanya listen di 127.0.0.1).
# ─────────────────────────────────────────────────────────────

$ErrorActionPreference = 'Stop'

$Bin  = 'C:\Program Files\PostgreSQL\18\bin'
$Data = Join-Path $env:LOCALAPPDATA 'Temp\opencode\pgdev'
$Log  = Join-Path $env:LOCALAPPDATA 'Temp\opencode\pgdev.log'
$Port = 5544

function Test-Running {
    param([int]$Port)
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    return [bool]$conn
}

switch ($args[0]) {
    'start' {
        if (Test-Running -Port $Port) { "Cluster dev sudah berjalan di port $Port"; break }

        if (-not (Test-Path $Data)) {
            "Membuat cluster baru di $Data ..."
            & "$Bin\initdb.exe" -D $Data -U postgres --auth=trust --encoding=UTF8 --no-locale | Out-Null
        }

        # Jalankan langsung (bukan pg_ctl) supaya proses tetap milik user ini.
        Start-Process -FilePath "$Bin\postgres.exe" `
            -ArgumentList @('-D', $Data, '-p', "$Port") `
            -RedirectStandardOutput "$Log.out" `
            -RedirectStandardError "$Log" `
            -WindowStyle Hidden | Out-Null

        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Milliseconds 500
            if (Test-Running -Port $Port) { break }
        }

        if (-not (Test-Running -Port $Port)) {
            "Gagal start. Cek log: $Log"
            Get-Content $Log -Tail 20 -ErrorAction SilentlyContinue
            exit 1
        }

        $exists = & "$Bin\psql.exe" -h 127.0.0.1 -p $Port -U postgres -w -tAc "select 1 from pg_database where datname='dailypilot'"
        if ($exists.Trim() -ne '1') {
            & "$Bin\psql.exe" -h 127.0.0.1 -p $Port -U postgres -w -c "CREATE DATABASE dailypilot" | Out-Null
            "Database 'dailypilot' dibuat."
        }

        "PostgreSQL dev siap: postgresql://postgres@127.0.0.1:$Port/dailypilot"
    }

    'stop' {
        Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
        "Cluster dev dihentikan."
    }

    'reset' {
        & $PSCommandPath stop
        Start-Sleep -Seconds 1
        if (Test-Path $Data) { Remove-Item $Data -Recurse -Force }
        & $PSCommandPath start
    }

    default {
        @"
Pemakaian: scripts\dev-db.ps1 <start|stop|reset>

  start   Nyalakan PostgreSQL dev (port 5544) + pastikan database dailypilot ada
  stop    Matikan cluster dev
  reset   Hapus semua data dev lalu buat ulang dari nol
"@
    }
}

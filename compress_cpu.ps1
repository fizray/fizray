# Memastikan antarmuka grafis dimuat untuk komponen pemilihan folder
Add-Type -AssemblyName System.Windows.Forms

# Validasi ketersediaan engine FFmpeg di Environment Variables OS
if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) {
    Write-Host "FFmpeg tidak terdeteksi. Pastikan FFmpeg terinstal dan terdaftar di dalam PATH." -ForegroundColor Red
    exit
}

# 1. Instansiasi dialog GUI untuk memilih direktori
$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Pilih folder yang berisi video untuk dikompres (File video tersembunyi secara visual di sini)"
$folderBrowser.ShowNewFolderButton = $false

$dialogResult = $folderBrowser.ShowDialog()
if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host "Operasi dibatalkan. Folder tidak dipilih." -ForegroundColor Yellow
    exit
}

$sourceDir = $folderBrowser.SelectedPath
$doneDir = Join-Path -Path $sourceDir -ChildPath "done"

# Membaca file dan memfilter ekstensinya secara akurat menggunakan Regex (Case-Insensitive)
$videos = Get-ChildItem -Path $sourceDir -File | Where-Object { $_.Extension -match '(?i)\.(mp4|mov|mkv|avi|webm)$' }

if (-not $videos) {
    Write-Host "Tidak ada video berekstensi valid yang ditemukan pada: $sourceDir" -ForegroundColor Yellow
    exit
}

# Buat folder khusus output (done) jika belum diprovisikan
if (-not (Test-Path -Path $doneDir)) {
    New-Item -ItemType Directory -Path $doneDir | Out-Null
}

$videoCount = @($videos).Count
Write-Host "Ditemukan $videoCount video. Memulai alur kompresi dengan CPU (libx265) ke 1080p..." -ForegroundColor Cyan
$report = @()

# 2. Iterasi pemrosesan (Batch processing per video)
foreach ($video in $videos) {
    $originalSizeMB = [math]::Round($video.Length / 1MB, 2)

    # 3. Manipulasi string untuk nama file tujuan (Akhiran '_ok')
    $newName = "$($video.BaseName)_ok$($video.Extension)"
    $outPath = Join-Path -Path $doneDir -ChildPath $newName

    Write-Host "Sedang memproses: $($video.Name) ($originalSizeMB MB)... " -NoNewline

    # PERBAIKAN: Menggunakan libx265 (CPU), preset veryslow, crf 28, dan downscale max 1080p
    $ffmpegArgs = @(
        "-i", $video.FullName,
        "-map_metadata", "0",
        "-hide_banner",
        "-loglevel", "warning", # Menampilkan peringatan saja agar rapi
        "-stats",               # Memunculkan baris progres (frame, fps, size, time) secara real-time
        # Filter scale: Max 1920x1080, pertahankan rasio aspek, pad untuk pastikan resolusi genap
        #"-vf", "scale='min(1920,iw)':'min(1080,ih)':force_original_aspect_ratio=decrease,pad=ceil(iw/2)*2:ceil(ih/2)*2",
        "-c:v", "libx265",     # Menggunakan CPU HEVC
        "-preset", "slow", # Memaksimalkan kompresi (ukuran terkecil, namun proses komputasi lebih lama)
        "-crf", "28",          # Nilai Constant Rate Factor (28 memberikan ukuran yang sangat kecil dengan kualitas yang masih bisa diterima untuk x265)
        "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        "-c:a", "copy",        # Menyalin audio asli tanpa kompresi ulang
        "-y", $outPath
    )

    # Eksekusi child process FFmpeg
    $process = Start-Process -FilePath "ffmpeg" -ArgumentList $ffmpegArgs -Wait -NoNewWindow -PassThru

    # Evaluasi status keluaran operasi kompresi
    if ($process.ExitCode -eq 0 -and (Test-Path $outPath)) {
        $outFile = Get-Item $outPath
        $compressedSizeMB = [math]::Round($outFile.Length / 1MB, 2)
        Write-Host "Selesai!" -ForegroundColor Green

        $report += [PSCustomObject]@{
            FileName = $newName
            Original = $originalSizeMB
            Compressed = $compressedSizeMB
        }
    } else {
        Write-Host "Gagal/Corrupt!" -ForegroundColor Red
    }
}

# 4. Pencetakan laporan rekapitulasi akhir
Write-Host "`n==============================================" -ForegroundColor Cyan
Write-Host "TABEL KALKULASI UKURAN KOMPRESI" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

foreach ($item in $report) {
    Write-Host "$($item.FileName): $($item.Original) MB -> $($item.Compressed) MB" -ForegroundColor White
}
Write-Host "==============================================" -ForegroundColor Cyan

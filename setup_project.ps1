# =====================================================================
#  Progress Tracker — one-time Android scaffolding + patch script
#
#  `flutter create` regenerates the platform folders but would clobber our
#  hand-written pubspec/lib/manifest/MainActivity with its demo defaults.
#  So we: back up our files -> scaffold -> restore -> patch minSdk to 23.
#
#  Run from the project root:   powershell -ExecutionPolicy Bypass -File .\setup_project.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

# Files WE authored that flutter create must not overwrite.
$preserve = @(
    'pubspec.yaml',
    'analysis_options.yaml',
    'lib',
    'test',
    'android\app\src\main\AndroidManifest.xml',
    'android\app\src\main\kotlin\com\example\progress_tracker\MainActivity.kt'
)

$backup = Join-Path $env:TEMP ("pt_backup_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backup | Out-Null
Write-Host "Backing up authored files -> $backup"
foreach ($p in $preserve) {
    if (Test-Path $p) {
        $dest = Join-Path $backup $p
        $d = Split-Path $dest; if ($d) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        Copy-Item $p $dest -Recurse -Force
    }
}

Write-Host "Scaffolding Android platform files (flutter create)..."
flutter create --platforms=android --org com.example --project-name progress_tracker .

Write-Host "Restoring authored files..."
foreach ($p in $preserve) {
    $src = Join-Path $backup $p
    if (Test-Path $src) {
        $d = Split-Path $p; if ($d) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        Copy-Item $src $p -Recurse -Force
    }
}

# Patch minSdk to 23 (required for NotificationManager DND control).
$gradleCandidates = @('android\app\build.gradle.kts', 'android\app\build.gradle')
foreach ($g in $gradleCandidates) {
    if (Test-Path $g) {
        Write-Host "Patching minSdk -> 23 in $g"
        $txt = Get-Content $g -Raw
        $txt = $txt -replace 'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion', 'minSdk = 23'
        $txt = $txt -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23'
        Set-Content $g $txt -Encoding utf8
    }
}

Write-Host "flutter pub get..."
flutter pub get

Write-Host "`nDone. Next: run tests  ->  flutter test" -ForegroundColor Green
Write-Host "Then run on a device  ->  flutter run" -ForegroundColor Green

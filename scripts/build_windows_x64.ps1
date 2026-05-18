Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$DistRoot = Join-Path $RepoRoot "dist"
$PackageRoot = Join-Path $DistRoot "windows-x64"
$ZipPath = Join-Path $DistRoot "ConvertVideo2MP3-windows-x64.zip"

Set-Location $RepoRoot

swift test --filter ExternalDependencyCheckTests
swift build -c release --product ConvertVideo2MP3CLI
$BinPath = swift build -c release --product ConvertVideo2MP3CLI --show-bin-path

if (Test-Path $PackageRoot) {
    Remove-Item -Recurse -Force $PackageRoot
}
New-Item -ItemType Directory -Force $PackageRoot | Out-Null

$ExePath = Join-Path $BinPath "ConvertVideo2MP3CLI.exe"
if (!(Test-Path $ExePath)) {
    $ExePath = Join-Path $BinPath "ConvertVideo2MP3CLI"
}

if (!(Test-Path $ExePath)) {
    Write-Host "SwiftPM bin path: $BinPath"
    Get-ChildItem -Path $BinPath -ErrorAction SilentlyContinue | Format-Table -AutoSize
    throw "Unable to find ConvertVideo2MP3CLI executable in SwiftPM bin path"
}

Copy-Item $ExePath (Join-Path $PackageRoot "ConvertVideo2MP3CLI.exe")

$SwiftCommand = Get-Command swift -ErrorAction Stop
$SwiftBin = Split-Path $SwiftCommand.Source -Parent
Get-ChildItem -Path $SwiftBin -Filter "*.dll" -ErrorAction SilentlyContinue |
    Copy-Item -Destination $PackageRoot -Force

Get-ChildItem -Path $BinPath -Filter "*.dll" -ErrorAction SilentlyContinue |
    Copy-Item -Destination $PackageRoot -Force

@"
ConvertVideo2MP3 Windows x64 CLI

Commands:
  ConvertVideo2MP3CLI.exe check-deps
  ConvertVideo2MP3CLI.exe convert "C:\path\to\videos" --concurrency 4
  ConvertVideo2MP3CLI.exe pitch "C:\in.mp3" "C:\out.mp3" --stem background --mode pitch --direction up --semitones 6

External tools:
  - ffmpeg and ffprobe are required for video conversion.
  - rubberband is required for pitch shifting.
  - demucs is required for vocals/background separation.

Run `ConvertVideo2MP3CLI.exe check-deps` first on a new machine.
"@ | Set-Content -Encoding UTF8 (Join-Path $PackageRoot "README-Windows.txt")

if (Test-Path $ZipPath) {
    Remove-Item -Force $ZipPath
}
Compress-Archive -Path (Join-Path $PackageRoot "*") -DestinationPath $ZipPath

Write-Host "Built: $PackageRoot"
Write-Host "Package: $ZipPath"

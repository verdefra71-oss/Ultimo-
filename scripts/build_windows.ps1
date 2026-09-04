$ErrorActionPreference = 'Stop'

Write-Host '=== Gestione Preventivi - Il Tornitore ===' -ForegroundColor Cyan
Write-Host 'Preparazione progetto Windows...'

flutter config --enable-windows-desktop
flutter create --platforms=windows --project-name preventivi_app .

if (Test-Path 'assets/app_icon.ico') {
    New-Item -ItemType Directory -Force 'windows/runner/resources' | Out-Null
    Copy-Item 'assets/app_icon.ico' 'windows/runner/resources/app_icon.ico' -Force
}

flutter pub get
flutter analyze
flutter build windows --release

Write-Host ''
Write-Host 'BUILD COMPLETATO' -ForegroundColor Green
Write-Host 'Portable: build/windows/x64/runner/Release/'

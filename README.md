# Gestione Preventivi - Il Tornitore

## Windows

Questo progetto è predisposto per creare una vera applicazione Windows x64.
La cartella `windows/` viene generata automaticamente dal comando Flutter `flutter create --platforms=windows` così da usare il template Windows della versione Flutter installata.

### Build locale su Windows

Prerequisiti:
- Flutter stable
- Visual Studio 2022 con **Desktop development with C++**
- Windows 10/11 SDK

Da PowerShell nella cartella del progetto:

```powershell
.\scripts\build_windows.ps1
```

Oppure:

```powershell
flutter config --enable-windows-desktop
flutter create --platforms=windows --project-name preventivi_app .
flutter pub get
flutter build windows --release
```

L'eseguibile viene creato in:

`build/windows/x64/runner/Release/preventivi_app.exe`

## GitHub Actions

Il workflow `.github/workflows/build-apk.yml` compila:
- APK Android
- applicazione Windows x64
- installer Windows `.exe` tramite Inno Setup

Su GitHub: **Actions → Build Preventivi Android e Windows → Run workflow**.
Alla fine scaricare l'artifact **Gestione-Preventivi-Windows-Installer**.

### Nota importante

Il file ZIP del sorgente non contiene un `.exe` precompilato: un'app Flutter Windows deve essere compilata su un ambiente Windows con Visual Studio/C++ e Windows SDK. GitHub Actions usa `windows-latest` e genera automaticamente il progetto Windows prima della compilazione.

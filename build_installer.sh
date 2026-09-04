#!/bin/bash

# ==========================================
# DONVERTER MAC BUILD AUTOMATION SCRIPT
# ==========================================
# Script ini akan:
# 1. Mem-build ulang backend Python dengan PyInstaller
# 2. Meng-copy biner ke Xcode Project Resources
# 3. Mem-build ulang Xcode App (Release Mode)
# 4. Ad-hoc Code Sign supaya bisa jalan di Mac lain
# 5. Membungkus menjadi file .dmg Installer
# ==========================================

echo "🚀 Memulai proses Build Otomatis Donverter..."

# 1. Tentukan Direktori Vitals secara dinamis
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
APP_PATH="$PROJECT_DIR/Donverter/build/Release/Donverter.app"

# Cari Python Virtual Environment / PyInstaller
if [ -d "$PROJECT_DIR/venv/bin" ]; then
  PYTHON_VENV="$PROJECT_DIR/venv/bin"
else
  PYTHON_VENV=""
fi

if [ -n "$PYTHON_VENV" ] && [ -f "$PYTHON_VENV/pyinstaller" ]; then
  PYINSTALLER_BIN="$PYTHON_VENV/pyinstaller"
elif command -v pyinstaller &> /dev/null; then
  PYINSTALLER_BIN="pyinstaller"
else
  echo "❌ Error: pyinstaller tidak ditemukan! Aktifkan virtualenv Python yang berisi pyinstaller terlebih dahulu."
  exit 1
fi

cd "$PROJECT_DIR" || exit

echo "🐍 1/5 Mengkompilasi ulang Backend Python ke Biner Mandiri..."
"$PYINSTALLER_BIN" --onefile --clean "$PROJECT_DIR/backend/downloader_cli.py" \
  --add-binary "$PROJECT_DIR/backend/bin/ffmpeg:." \
  --add-binary "$PROJECT_DIR/backend/bin/ffprobe:." \
  --distpath "$PROJECT_DIR/backend/dist" --workpath "$PROJECT_DIR/backend/build" --specpath "$PROJECT_DIR/backend"
"$PYINSTALLER_BIN" --onefile --clean "$PROJECT_DIR/backend/image_converter_cli.py" --distpath "$PROJECT_DIR/backend/dist" --workpath "$PROJECT_DIR/backend/build" --specpath "$PROJECT_DIR/backend"

echo "📂 2/5 Memasukkan Biner baru ke Xcode Resources..."
mkdir -p "$PROJECT_DIR/Donverter/Donverter/Resources"
cp "$PROJECT_DIR/backend/dist/downloader_cli" "$PROJECT_DIR/Donverter/Donverter/Resources/"
cp "$PROJECT_DIR/backend/dist/image_converter_cli" "$PROJECT_DIR/Donverter/Donverter/Resources/"

echo "🛠️ 3/5 Mem-Build Ulang Xcode Swift App (.app)..."
cd "$PROJECT_DIR/Donverter" || exit
# Bersihkan folder build manual — Xcode versi baru menolak `clean` untuk
# SYMROOT custom di luar DerivedData, jadi kita hapus sendiri lalu build.
rm -rf "$PROJECT_DIR/Donverter/build"
xcodebuild build \
  -project Donverter.xcodeproj \
  -scheme Donverter \
  -configuration Release \
  SYMROOT="$PROJECT_DIR/Donverter/build" \
  OBJROOT="$PROJECT_DIR/Donverter/build/obj" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# Guard: pastikan executable utama benar-benar dihasilkan
if [ ! -f "$APP_PATH/Contents/MacOS/Donverter" ]; then
  echo "❌ Error: Build gagal — executable utama tidak ada di bundle!"
  echo "   Cek apakah ada file .swift duplikat (mis. 'File 2.swift') yang"
  echo "   menyebabkan 'Invalid redeclaration'."
  exit 1
fi

echo "✍️  4/5 Ad-hoc Code Signing App & Semua Binary di dalamnya..."
# PENTING: folder proyek ada di ~/Documents yang tersync cloud (iCloud/file
# provider). File provider terus meng-inject atribut `com.apple.fileprovider`
# & FinderInfo ke bundle, membuat codesign gagal ("detritus not allowed")
# walau sudah di-strip. Solusi: salin app ke lokasi non-sync (/tmp), lalu
# strip + sign di sana. Semua langkah packaging berikutnya pakai salinan ini.
SIGN_DIR="$(mktemp -d /tmp/donverter_sign.XXXXXX)"
SIGNED_APP="$SIGN_DIR/Donverter.app"
ditto "$APP_PATH" "$SIGNED_APP"

# Buang extended attributes; di /tmp strip ini "nempel" (tidak di-re-inject).
xattr -cr "$SIGNED_APP"

# Sign binary PyInstaller di dalam Resources dulu (dari dalam ke luar)
codesign --force --sign - --timestamp=none "$SIGNED_APP/Contents/Resources/downloader_cli"
codesign --force --sign - --timestamp=none "$SIGNED_APP/Contents/Resources/image_converter_cli"

# Sign seluruh .app bundle terakhir (deep untuk mencakup framework Swift)
codesign --force --deep --sign - --timestamp=none "$SIGNED_APP"

# Verifikasi hasil signing (strict)
echo "🔍 Verifikasi Code Signing:"
if codesign --verify --deep --strict --verbose=2 "$SIGNED_APP" 2>&1; then
  echo "✅ Signing sukses!"
else
  echo "❌ Signing GAGAL — app akan dianggap 'damaged'. Hentikan build."
  rm -rf "$SIGN_DIR"
  exit 1
fi

echo "📦 5/5 Membungkus menjadi Installer DonverterInstaller.pkg..."
cd "$PROJECT_DIR" || exit

APP_SIZE=$(du -sh "$SIGNED_APP" 2>/dev/null | cut -f1)
echo "   ✅ App tersigning siap dipackage ($APP_SIZE)"

# Staging & pkgbuild HARUS di /tmp (non-sync). Kalau di $PROJECT_DIR (dalam
# ~/Documents yang tersync), file provider akan re-inject FinderInfo ke app
# setelah signing → signature rusak → app "damaged" saat diinstall.
PKG_BUILD_DIR="$(mktemp -d /tmp/donverter_pkg.XXXXXX)"
PKG_STAGING="$PKG_BUILD_DIR/staging"
PKG_OUTPUT="$HOME/Downloads/DonverterInstaller.pkg"
INSTALLER_DIR="$PROJECT_DIR/installer"

# Bersihkan direktori build sementara
rm -rf "$PKG_BUILD_DIR"
mkdir -p "$PKG_STAGING/Applications"

# Copy app TERSIGNING dari /tmp ke staging
ditto "$SIGNED_APP" "$PKG_STAGING/Applications/Donverter.app"

# Step 5a: Buat component package
pkgbuild \
  --root "$PKG_STAGING" \
  --identifier "com.bryandanendra.Donverter" \
  --version "1.0" \
  --install-location "/" \
  "$PKG_BUILD_DIR/Donverter.pkg"

# Step 5b: Buat installer product dengan wizard UI
rm -f "$PKG_OUTPUT"
productbuild \
  --distribution "$INSTALLER_DIR/Distribution.xml" \
  --resources "$INSTALLER_DIR/resources" \
  --package-path "$PKG_BUILD_DIR" \
  "$PKG_OUTPUT"

# Bersihkan sisa
rm -rf "$PKG_BUILD_DIR"
rm -rf "$SIGN_DIR"

echo ""
echo "✅ SELESAI! Installer tersedia di: ~/Downloads/DonverterInstaller.pkg"
echo ""
echo "📋 CATATAN UNTUK DISTRIBUSI:"
echo "   - App sudah di-sign secara ad-hoc (gratis, tanpa Apple Developer Account)"
echo "   - Installer menggunakan wizard macOS standar (Introduction → Readme → License → Install → Done)"
echo "   - Teman kamu mungkin perlu klik 'Open Anyway' di System Settings > Privacy & Security"
echo "   - Ini hanya perlu dilakukan SEKALI saja"
echo "   - Kalau mau tanpa popup sama sekali, perlu Apple Developer Account (\$99/tahun)"

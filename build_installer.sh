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
elif [ -d "/Users/a1234/Documents/CODING/Donverter/venv/bin" ]; then
  PYTHON_VENV="/Users/a1234/Documents/CODING/Donverter/venv/bin"
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
xcodebuild clean build \
  -project Donverter.xcodeproj \
  -scheme Donverter \
  -configuration Release \
  SYMROOT="$PROJECT_DIR/Donverter/build" \
  OBJROOT="$PROJECT_DIR/Donverter/build/obj" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

echo "✍️  4/5 Ad-hoc Code Signing App & Semua Binary di dalamnya..."
# Sign semua binary PyInstaller di dalam Resources
codesign --force --deep --sign - "$APP_PATH/Contents/Resources/downloader_cli" 2>/dev/null || true
codesign --force --deep --sign - "$APP_PATH/Contents/Resources/image_converter_cli" 2>/dev/null || true

# Sign seluruh .app bundle secara menyeluruh (deep)
codesign --force --deep --sign - "$APP_PATH"

# Verifikasi hasil signing
echo "🔍 Verifikasi Code Signing:"
codesign --verify --verbose "$APP_PATH" && echo "✅ Signing sukses!" || echo "⚠️  Signing mungkin ada masalah, cek output di atas"

echo "📦 5/5 Membungkus menjadi Installer DonverterInstaller.dmg..."
cd "$PROJECT_DIR" || exit

# Bersihkan direktori build sementara jika ada
rm -rf "$PROJECT_DIR/dmg_build"
mkdir -p "$PROJECT_DIR/dmg_build"

# Copy App yang baru dibuild ke folder pembungkus DMG
cp -R "$APP_PATH" "$PROJECT_DIR/dmg_build/"

# Buat jalan pintas (alias icon) ke folder Applications sistem
ln -s /Applications "$PROJECT_DIR/dmg_build/Applications"

# Hapus Installer DMG lama (jika ada) supaya aman nimpa
rm -f "/Users/a1234/Downloads/DonverterInstaller.dmg"

# Ciptakan DMG
hdiutil create -volname "Donverter" -srcfolder "$PROJECT_DIR/dmg_build" -ov -format UDZO "/Users/a1234/Downloads/DonverterInstaller.dmg"

# Bersihkan sisa
rm -rf "$PROJECT_DIR/dmg_build"

echo ""
echo "✅ SELESAI! Installer tersedia di: ~/Downloads/DonverterInstaller.dmg"
echo ""
echo "📋 CATATAN UNTUK DISTRIBUSI:"
echo "   - App sudah di-sign secara ad-hoc (gratis, tanpa Apple Developer Account)"
echo "   - Teman kamu mungkin perlu klik 'Open Anyway' di System Settings > Privacy & Security"
echo "   - Ini hanya perlu dilakukan SEKALI saja"
echo "   - Kalau mau tanpa popup sama sekali, perlu Apple Developer Account (\$99/tahun)"

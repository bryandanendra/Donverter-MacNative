#!/bin/bash

# ==========================================
# DONVERTER MAC BUILD AUTOMATION SCRIPT
# ==========================================
# Script ini akan:
# 1. Mem-build ulang backend Python dengan PyInstaller
# 2. Meng-copy biner ke Xcode Project Resources
# 3. Mem-build ulang Xcode App (Release Mode)
# 4. Membungkus menjadi file .dmg Installer
# ==========================================

echo "🚀 Memulai proses Build Otomatis Donverter..."

# 1. Tentukan Direktori Vitals
PROJECT_DIR="/Users/a1234/Documents/CODING/Donverter-MacNative"
PYTHON_VENV="/Users/a1234/Documents/CODING/Donverter/venv/bin"

cd "$PROJECT_DIR" || exit

echo "🐍 1/4 Mengkompilasi ulang Backend Python ke Biner Mandiri..."
"$PYTHON_VENV/pyinstaller" --onefile --clean "$PROJECT_DIR/backend/downloader_cli.py" --distpath "$PROJECT_DIR/backend/dist" --workpath "$PROJECT_DIR/backend/build" --specpath "$PROJECT_DIR/backend"
"$PYTHON_VENV/pyinstaller" --onefile --clean "$PROJECT_DIR/backend/image_converter_cli.py" --distpath "$PROJECT_DIR/backend/dist" --workpath "$PROJECT_DIR/backend/build" --specpath "$PROJECT_DIR/backend"

echo "📂 2/4 Memasukkan Biner baru ke Xcode Resources..."
mkdir -p "$PROJECT_DIR/Donverter/Donverter/Resources"
cp "$PROJECT_DIR/backend/dist/downloader_cli" "$PROJECT_DIR/Donverter/Donverter/Resources/"
cp "$PROJECT_DIR/backend/dist/image_converter_cli" "$PROJECT_DIR/Donverter/Donverter/Resources/"

echo "🛠️ 3/4 Mem-Build Ulang Xcode Swift App (.app)..."
cd "$PROJECT_DIR/Donverter" || exit
xcodebuild clean build -project Donverter.xcodeproj -scheme Donverter -configuration Release

echo "📦 4/4 Membungkus menjadi Installer DonverterInstaller.dmg..."
cd "$PROJECT_DIR" || exit
# Bersihkan direktori build sementara jika ada
rm -rf "$PROJECT_DIR/dmg_build"
mkdir -p "$PROJECT_DIR/dmg_build"

# Copy App yang baru dibuild ke folder pembungkus DMG
cp -R "$PROJECT_DIR/Donverter/build/Release/Donverter.app" "$PROJECT_DIR/dmg_build/"
# Buat jalan pintas (alias icon) ke folder Applications sistem
ln -s /Applications "$PROJECT_DIR/dmg_build/Applications"

# Hapus Installer DMG lama (jika ada) supaya aman nimpa
rm -f "/Users/a1234/Downloads/DonverterInstaller.dmg"

# Ciptakan DMG
hdiutil create -volname "Donverter" -srcfolder "$PROJECT_DIR/dmg_build" -ov -format UDZO "/Users/a1234/Downloads/DonverterInstaller.dmg"

# Bersihkan sisa
rm -rf "$PROJECT_DIR/dmg_build"

echo "✅ SELESAI! SILAKAN CEK FOLDER ~/Downloads ANDA!"

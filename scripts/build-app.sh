#!/usr/bin/env bash
# 릴리스 빌드 후 더블클릭으로 실행할 수 있는 MyPSX.app 을 build/ 폴더에 만듭니다.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="MyPSX"
DISPLAY_NAME="My PSX"
BUNDLE_ID="com.hjt1629.mypsx"
VERSION="${VERSION:-0.1.0}"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleDevelopmentRegion</key><string>ko</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSDesktopFolderUsageDescription</key><string>데스크탑 폴더의 사진을 보고 편집하기 위해 필요합니다.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>문서 폴더의 사진을 보고 편집하기 위해 필요합니다.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>다운로드 폴더의 사진을 보고 편집하기 위해 필요합니다.</string>
    <key>NSRemovableVolumesUsageDescription</key><string>외장 디스크의 사진을 보고 편집하기 위해 필요합니다.</string>
</dict>
</plist>
PLIST

# 로컬 실행용 임시 서명 (Apple 개발자 계정 불필요)
codesign --force --sign - "$APP"

echo "완료: $APP"

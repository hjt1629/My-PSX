#!/usr/bin/env bash
# 릴리스 빌드 후 더블클릭으로 실행할 수 있는 MyPSX.app 을 build/ 폴더에 만듭니다.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="MyPSX"
DISPLAY_NAME="My PSX"
BUNDLE_ID="com.hjt1629.mypsx"
VERSION="${VERSION:-0.1.0}"
# 빌드 번호는 커밋 해시 — 설정 창 아래에 표시돼 어떤 빌드인지 알 수 있습니다.
BUILD="${BUILD:-$(git rev-parse --short HEAD 2>/dev/null || echo "$VERSION")}"
BUILD="${BUILD:0:7}"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

# 문서·데스크탑 폴더(iCloud 동기화)에서는 macOS가 파일에 Finder 정보 같은 확장 속성을 붙여
# 서명이 "resource fork, Finder information, or similar detritus not allowed"로 실패합니다.
# 그래서 앱은 임시 폴더에서 만들고 서명한 뒤 build/ 로 옮깁니다.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/${APP_NAME}.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# 앱 아이콘: Resources/AppIcon.png (1024×1024) → AppIcon.icns
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

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
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
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
xattr -cr "$APP"
codesign --force --sign - "$APP"

OUT="build/${APP_NAME}.app"
mkdir -p build
rm -rf "$OUT"
ditto --norsrc --noextattr "$APP" "$OUT"

echo "완료: $OUT"

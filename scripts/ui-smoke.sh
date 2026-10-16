#!/usr/bin/env bash
# CI(macOS)에서 실제 앱을 띄우고 키보드/마우스로 조작하면서 단계별 스크린샷을 남깁니다.
# 사용법: scripts/ui-smoke.sh   (먼저 scripts/build-app.sh 실행)
set -uo pipefail
cd "$(dirname "$0")/.."

APP_BIN="build/MyPSX.app/Contents/MacOS/MyPSX"
OUT="build/screenshots"
WORK="$(mktemp -d)/사진 테스트"
mkdir -p "$OUT" "$WORK/하위 폴더"

# macOS에 기본으로 들어 있는 사진을 테스트 폴더로 복사
find -L "/Library/User Pictures/Animals" "/Library/User Pictures/Flowers" -type f \( -iname '*.heic' -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.png' -o -iname '*.jpg' \) 2>/dev/null \
    | head -8 | while IFS= read -r f; do cp "$f" "$WORK/"; done
ls -la "$WORK"
PHOTO="$(find "$WORK" -maxdepth 1 -type f | sort | head -1)"
echo "편집할 사진: $PHOTO"

PID=""
launch() {
    "$APP_BIN" "$1" > "$OUT/app.log" 2>&1 &
    PID=$!
    sleep 4
    osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $PID) to true" \
        || echo "⚠️ 앱을 앞으로 가져오지 못함"
    sleep 1
}
quit_app() { [ -n "$PID" ] && kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; PID=""; }
shot() { sleep "${2:-1.5}"; screencapture -x -t jpg "$OUT/$1.jpg" && echo "📸 $1" || echo "⚠️ 스크린샷 실패: $1"; }
key() { osascript -e "tell application \"System Events\" to keystroke \"$1\" ${2:-}" || echo "⚠️ 키 입력 실패: $1 ${2:-}"; }
keycode() { osascript -e "tell application \"System Events\" to key code $1 ${2:-}" || echo "⚠️ 키 입력 실패: $1"; }
window_bounds() {
    osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to get {position, size} of front window" 2>/dev/null
}

# 1. 폴더 보기
launch "$WORK"
echo "창 위치/크기: $(window_bounds)"
shot 01-browser 2
quit_app

# 2. 사진 편집
launch "$PHOTO"
shot 02-editor 2

key "]" "using command down";                  shot 03-rotate-right
key "[" "using command down"
key "[" "using command down";                  shot 04-rotate-left-twice

# 자르기: 사진 바깥 왼쪽 위에서 가운데로 드래그 → 왼쪽 위 영역 선택
key "k" "using command down";                  shot 05-crop-mode
BOUNDS="$(window_bounds)"
echo "창: $BOUNDS"
if command -v cliclick >/dev/null && [ -n "$BOUNDS" ]; then
    IFS=', ' read -r WX WY WW WH <<< "$BOUNDS"
    SX=$((WX + 240)); SY=$((WY + 95))
    EX=$((WX + 240 + (WW - 240) / 2)); EY=$((WY + WH / 2))
    cliclick "dd:$SX,$SY" "dm:$(( (SX + EX) / 2 )),$(( (SY + EY) / 2 ))" "dm:$EX,$EY" "du:$EX,$EY"
fi
shot 06-crop-dragged
keycode 36;                                    shot 07-crop-applied 2

key "i" "using {command down, option down}";   shot 08-resize-sheet
key "a" "using command down"
key "300" ""
keycode 48;                                    shot 09-resize-typed
keycode 36;                                    shot 10-resized 2

key "b" "using {command down, shift down}";    shot 11-background-removed 10

key "z" "using command down";                  shot 12-undo
key "z" "using {command down, shift down}";    shot 13-redo

key "s" "using {command down, shift down}";    shot 14-save-as-panel 2
keycode 36;                                    shot 15-after-save 3

keycode 124;                                   shot 16-next-photo 3
keycode 53;                                    shot 17-back-to-grid 3
quit_app

echo "---- 저장된 파일 ----"
ls -la "$WORK"
for f in "$WORK"/*_편집.*; do
    [ -e "$f" ] && sips -g pixelWidth -g pixelHeight -g hasAlpha "$f"
done
echo "---- 앱 로그 ----"
cat "$OUT/app.log" || true

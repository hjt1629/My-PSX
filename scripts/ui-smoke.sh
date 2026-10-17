#!/usr/bin/env bash
# CI(macOS)에서 실제 앱을 띄우고 키보드/마우스로 조작하면서 단계별 스크린샷을 남깁니다.
# 사용법: scripts/ui-smoke.sh   (먼저 scripts/build-app.sh 실행)
set -uo pipefail
cd "$(dirname "$0")/.."

APP_BIN="build/MyPSX.app/Contents/MacOS/MyPSX"
OUT="build/screenshots"
# 폴더 트리가 저절로 펼쳐지는지 보려고 사진 폴더 안 깊숙이 만듭니다.
WORK="$HOME/Pictures/PSX 테스트/2024/사진 테스트"
rm -rf "$HOME/Pictures/PSX 테스트"
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

# 1. 뷰어 탭: 폴더 트리 / 키보드 선택 / 크게 보기 / 위로·뒤로
launch "$WORK"
echo "창 위치/크기: $(window_bounds)"
shot 01-viewer 2
keycode 124; keycode 124; keycode 125;         shot 02-viewer-keyboard
keycode 36;                                    shot 03-preview 2
keycode 124;                                   shot 04-preview-next 2
keycode 53;                                    shot 05-back-to-grid
osascript -e 'tell application "System Events" to key code 126 using command down' || true
                                               shot 06-folder-up 2
key "[" "using command down";                  shot 07-history-back 2
quit_app

# 2. 사진 편집 탭
launch "$PHOTO"
shot 08-editor 2

key "]" "using command down";                  shot 09-rotate-right
key "[" "using command down"
key "[" "using command down";                  shot 10-rotate-left-twice

# 자르기: 사진 바깥 왼쪽 위 여백에서 가운데로 드래그
key "k" "using command down";                  shot 11-crop-mode
BOUNDS="$(window_bounds)"
echo "창: $BOUNDS"
if command -v cliclick >/dev/null && [ -n "$BOUNDS" ]; then
    IFS=', ' read -r WX WY WW WH <<< "$BOUNDS"
    # 왼쪽 탐색 패널(280) 오른쪽, 위쪽 탭 줄·제목 막대 아래의 빈 여백에서 시작
    SX=$((WX + 300)); SY=$((WY + 125))
    EX=$((WX + 280 + (WW - 550) / 2)); EY=$((WY + WH / 2))
    cliclick "dd:$SX,$SY" "dm:$(( (SX + EX) / 2 )),$(( (SY + EY) / 2 ))" "dm:$EX,$EY" "du:$EX,$EY"
fi
shot 12-crop-dragged
keycode 36;                                    shot 13-crop-applied 2

# 크기 조절 (오른쪽 패널) — 너비 칸에 300 입력
key "i" "using {command down, option down}";   shot 14-resize-panel
key "a" "using command down"
key "300" "";                                  shot 15-resize-typed
keycode 36;                                    shot 16-resized 2

# 오른쪽 패널 탭: 조정(밝기 슬라이더 끌기 → 미리보기 → Return 적용) / AI / 설정 창
BOUNDS="$(window_bounds)"
if command -v cliclick >/dev/null && [ -n "$BOUNDS" ]; then
    IFS=', ' read -r WX WY WW WH <<< "$BOUNDS"
    PX=$((WX + WW - 270))
    cliclick "c:$((PX + 91)),$((WY + 92))";       shot 16a-adjust-panel 1
    SLY=$((WY + 171))   # 색온도 슬라이더
    cliclick "dd:$((PX + 135)),$SLY" "dm:$((PX + 180)),$SLY" "dm:$((PX + 215)),$SLY" "du:$((PX + 215)),$SLY"
                                                   shot 16b-adjust-preview 2
    keycode 36;                                    shot 16c-adjust-applied 2
    cliclick "c:$((PX + 147)),$((WY + 92))";       shot 16d-ai-panel 1
    cliclick "c:$((PX + 35)),$((WY + 92))"
fi
key "," "using command down";                  shot 16e-settings 2
key "w" "using command down";                  sleep 1

# 오려내기 탭: 배경 제거 (가상 머신에서는 실패하고 오류 창이 뜸 → 닫기)
key "b" "using {command down, shift down}";    shot 17-cutout-removed 10
keycode 36;                                    shot 18-cutout-panel 1

key "2" "using command down"
key "z" "using command down";                  shot 19-undo
key "z" "using {command down, shift down}";    shot 20-redo

key "s" "using {command down, shift down}";    shot 21-save-as-panel 2
keycode 36;                                    shot 22-after-save 3

keycode 124;                                   shot 23-next-photo 3
keycode 53;                                    shot 24-back-to-viewer 3

# 좌우 패널 너비 끌어서 조절 (사진 편집 탭)
key "2" "using command down";                  sleep 2
BOUNDS="$(window_bounds)"
if command -v cliclick >/dev/null && [ -n "$BOUNDS" ]; then
    IFS=', ' read -r WX WY WW WH <<< "$BOUNDS"
    MY=$((WY + WH / 2))
    LX=$((WX + 280)); RX=$((WX + WW - 271))
    cliclick "dd:$LX,$MY" "dm:$((LX + 40)),$MY" "dm:$((LX + 80)),$MY" "du:$((LX + 80)),$MY"
    cliclick "dd:$RX,$MY" "dm:$((RX - 40)),$MY" "dm:$((RX - 80)),$MY" "du:$((RX - 80)),$MY"
                                                   shot 24b-resized-panes 1
    # 더블클릭하면 원래 너비로
    cliclick "dc:$((LX + 80)),$MY" "dc:$((RX - 80)),$MY"
                                                   shot 24c-panes-reset 1
fi

# 좁은 창에서도 도구 막대가 잘리지 않는지
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to set size of front window to {1000, 640}" \
    || echo "⚠️ 창 크기 변경 실패"
shot 25-narrow-window 2
quit_app

echo "---- 저장된 파일 ----"
trap 'rm -rf "$HOME/Pictures/PSX 테스트"' EXIT
ls -la "$WORK"
for f in "$WORK"/*_편집.*; do
    [ -e "$f" ] && sips -g pixelWidth -g pixelHeight -g hasAlpha "$f"
done
echo "---- 앱 로그 ----"
cat "$OUT/app.log" || true

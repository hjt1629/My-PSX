#!/usr/bin/env bash
# 맥북에 받아 둔 코드로 최신 My PSX를 만들어 응용 프로그램 폴더에 설치하고 다시 켭니다.
# 처음:   git clone https://github.com/hjt1629/My-PSX.git ~/My-PSX
#         ~/My-PSX/scripts/install.sh
# 이후:   앱 메뉴 My PSX → 업데이트… (또는 이 스크립트를 다시 실행)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="/Applications/MyPSX.app"
BUNDLE_ID="com.hjt1629.mypsx"

notify() {
    osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}
trap 'notify "My PSX 업데이트 실패" "자세한 내용: ~/Library/Logs/MyPSX-update.log"; echo "✘ 실패"' ERR

if ! xcode-select -p >/dev/null 2>&1; then
    echo "✘ Command Line Tools가 없습니다. 터미널에서 'xcode-select --install'을 먼저 실행해 주세요."
    exit 1
fi

echo "▶ 최신 코드 받는 중…"
git fetch --quiet origin master
# 예전 작업 브랜치로 받아 둔 경우, 그 내용이 master에 합쳐졌으면 master로 옮겨 갑니다.
branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$branch" != "master" ] && git merge-base --is-ancestor HEAD origin/master; then
    echo "  · '$branch' → master 로 전환"
    git checkout --quiet master 2>/dev/null || git checkout --quiet -b master --track origin/master
fi
git pull --ff-only

echo "▶ 앱 만드는 중… (처음은 몇 분, 이후는 1분 정도)"
./scripts/build-app.sh

echo "▶ 설치하는 중…"
if pgrep -x MyPSX >/dev/null; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x MyPSX >/dev/null || break; sleep 0.5; done
    pkill -x MyPSX || true
fi
rm -rf "$APP"
ditto --norsrc --noextattr build/MyPSX.app "$APP"

# 앱의 「업데이트…」 메뉴가 이 폴더를 찾을 수 있도록 기억해 둡니다.
defaults write "$BUNDLE_ID" sourcePath "$(pwd)"

echo "✔ 설치 완료: $APP ($(git rev-parse --short HEAD))"
notify "My PSX" "최신 버전($(git rev-parse --short HEAD))으로 업데이트했습니다."
open "$APP"

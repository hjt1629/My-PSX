# My PSX

PhotoScape X에서 영감을 받은 macOS용 사진 뷰어 & 간단 편집기입니다.
Swift + SwiftUI로 만든 네이티브 앱이라 빠르고 가볍습니다.

## 기능

**뷰어**
- 폴더 단위로 사진을 썸네일 격자로 보기 (하위 폴더 더블클릭으로 이동)
- 사이드바: 홈 / 사진 / 데스크탑 / 다운로드, 즐겨찾기 폴더
- 썸네일 크기 조절, 마지막으로 연 폴더 기억
- JPEG, PNG, HEIC, TIFF, GIF, WebP, RAW(CR2, NEF, ARW, DNG 등) 등 macOS가 읽을 수 있는 모든 형식

**편집**
- 회전 (왼쪽 / 오른쪽), 좌우 / 상하 반전
- 자르기: 드래그로 영역 선택, 비율 고정 (1:1, 4:3, 3:2, 16:9 …)
- 크기 조절: 픽셀 지정, 비율 유지, 25% / 50% / 75% / 200%
- 배경 제거: macOS 내장 Vision 프레임워크 사용 (인터넷 연결이나 추가 설치 불필요)
- 실행 취소 / 다시 실행 (최대 30단계)
- 저장 시 촬영 날짜, 카메라, GPS 등 원본 정보 유지
- 투명 배경은 PNG로 저장

## 요구 사항

- macOS 14 (Sonoma) 이상
- Xcode 15 이상 (또는 `xcode-select --install` 로 설치한 Command Line Tools)

## 실행 방법

### 1) 바로 실행 (개발용)
```bash
swift run
```

### 2) Xcode로 열기
`Package.swift` 를 더블클릭해서 Xcode로 연 뒤 ▶︎ 버튼을 누릅니다.

### 3) 앱(.app)으로 만들기
```bash
./scripts/build-app.sh
open build/MyPSX.app
```
만들어진 `build/MyPSX.app` 을 `응용 프로그램` 폴더로 옮기면 일반 앱처럼 쓸 수 있습니다.

## 단축키

| 동작 | 단축키 |
|---|---|
| 폴더 열기 | ⌘O |
| 상위 폴더 | ⌘↑ |
| 새로고침 | ⌘R |
| 선택한 사진 열기 | Return 또는 더블클릭 |
| 이전 / 다음 사진 | ← / → |
| 목록으로 돌아가기 | Esc |
| 왼쪽 / 오른쪽 회전 | ⌘[ / ⌘] |
| 자르기 | ⌘K (적용: Return, 취소: Esc) |
| 크기 조절 | ⌥⌘I |
| 배경 제거 | ⇧⌘B |
| 실행 취소 / 다시 실행 | ⌘Z / ⇧⌘Z |
| 저장 / 다른 이름으로 저장 | ⌘S / ⇧⌘S |

## 구조

```
Sources/
  PSXCore/          이미지 불러오기·편집·저장 (UI 없음, 테스트 대상)
    ImageLoader     파일 → 이미지, 썸네일
    ImageOps        회전, 반전, 자르기, 크기 조절, 배경 제거
    ImageExporter   이미지 → 파일 (메타데이터 유지, 안전한 덮어쓰기)
  MyPSX/            SwiftUI 앱
    FolderBrowser   폴더 탐색 상태
    PhotoEditor     편집 상태 / 실행 취소 기록
    Views/          화면
Tests/PSXCoreTests  편집 기능 테스트 (`swift test`)
```

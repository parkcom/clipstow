# ClipStow

> 지금 캡처하고, 나중에 정리하세요.

[English](../README.md)

ClipStow는 메뉴막대와 사용자가 지정한 전역 단축키에서 빠르게 여는 macOS 13+ Markdown 노트 앱입니다. 일반 노트는 로컬 JSON으로 저장하고, Copy Capture로 수집한 Scratchpad는 노트로 저장하기 전까지 메모리에만 둡니다.

## 주요 기능

- 메뉴막대 아이콘이나 전역 단축키로 열기·닫기
- 카테고리와 최근 수정 순 노트 목록
- Markdown 편집 및 미리보기
- 복사한 텍스트를 메모리 전용 Scratchpad에 수집
- Scratchpad 항목을 개별 또는 한 번에 노트로 저장
- 팝오버 크기 조절·고정과 영역별 글자 크기 설정
- 로그인 시 실행, 단축키 변경과 충돌 안내
- 영어·한국어·일본어 UI
- 중복 앱 인스턴스 실행 방지

## 요구 사항

- macOS 13 Ventura 이상
- Xcode 26 이상

현재는 소스 코드만 제공합니다. 서명·공증된 설치 파일은 아직 제공하지 않습니다.

## 빌드 및 실행

```sh
git clone https://github.com/parkcom/clipstow.git
cd clipstow
open ClipStow.xcodeproj
```

Xcode에서 `ClipStow` scheme과 `My Mac` destination을 선택한 뒤 실행합니다. 앱은 Dock 대신 메뉴막대에 표시됩니다.

명령줄 검증:

```sh
xcodebuild -project ClipStow.xcodeproj -scheme ClipStow -destination 'platform=macOS' test
xcodebuild -project ClipStow.xcodeproj -scheme ClipStow -destination 'platform=macOS' -configuration Debug build
```

## 사용법

- 최초 전역 단축키는 `⌥ Space`이며 설정에서 변경할 수 있습니다.
- 노트 목록 상단의 작성 버튼으로 현재 카테고리에 노트를 만듭니다.
- 목록에서 제목을 더블클릭하면 제목을 변경할 수 있습니다.
- 카테고리 사이드바를 접으면 목록 상단의 콤보박스로 카테고리를 선택할 수 있습니다.
- 카테고리를 삭제하면 포함된 모든 노트도 영구 삭제되며 실행 전에 확인합니다.
- Scratchpad에서 Copy Capture를 켜면 다른 앱에서 복사한 텍스트가 누적됩니다.
- Scratchpad 항목은 개별적으로 노트에 복사하거나 삭제할 수 있습니다.
- 팝오버 크기와 고정 상태, 앱 언어, 단축키 및 글자 크기는 설정에서 변경합니다.

## 저장과 개인정보

노트는 앱 샌드박스의 Application Support 아래 `ClipStow/store.json`에 원자적으로 저장됩니다. 일반적인 경로는 다음과 같습니다.

```text
~/Library/Containers/com.parkcom.clipstow/Data/Library/Application Support/ClipStow/store.json
```

Scratchpad 텍스트는 디스크에 저장하지 않습니다. 계정, 분석 도구, 텔레메트리, 클라우드 동기화 및 앱 자체 네트워크 통신도 없습니다. 자세한 내용은 [개인정보 안내](../PRIVACY.md)를 참고하세요.

Copy Capture는 `⌘C` 키를 감시하거나 가로채지 않고 `NSPasteboard.changeCount`를 250ms 간격으로 확인합니다. macOS가 Pasteboard 접근을 요청할 수 있으며, 거부했다면 시스템 설정에서 다시 허용해야 합니다.

## 제한사항

- 한 번의 폴링 사이에 덮어쓴 중간 클립보드 내용은 복구할 수 없습니다.
- 검색, 첨부 파일, 태그, 동기화, 공유, 버전 기록 및 삭제 복구는 제공하지 않습니다.
- 저장하지 않은 Scratchpad는 앱 종료 시 사라집니다.
- 현재 공개 소스는 배포용으로 서명·공증된 빌드가 아닙니다.

버그 제보와 기여 방법은 [CONTRIBUTING.md](../CONTRIBUTING.md), 보안 문제 신고 방법은 [SECURITY.md](../SECURITY.md)를 확인하세요.

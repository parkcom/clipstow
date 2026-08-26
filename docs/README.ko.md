# ClipStow

> 지금 캡처하고, 나중에 정리하세요.

<p align="center">
  <img src="assets/clipstow-icon.png" width="160" alt="ClipStow 앱 아이콘">
</p>

[English](../README.md)

ClipStow는 메뉴막대와 사용자가 지정한 전역 단축키에서 빠르게 여는 macOS 13+ Markdown 노트 앱입니다. 일반 노트는 로컬 JSON으로 저장하고, Copy Capture로 수집한 Scratchpad는 노트로 저장하기 전까지 메모리에만 둡니다.

## 주요 기능

- 메뉴막대 아이콘이나 전역 단축키로 열기·닫기
- 카테고리와 최근 수정 순 노트 목록
- Markdown 편집 및 미리보기
- 복사한 텍스트를 메모리 전용 Scratchpad에 수집
- Scratchpad 항목을 개별 또는 한 번에 노트로 저장
- 사용자가 선택한 폴더의 자동 갱신 탐색, 이름·수정일·크기별 양방향 정렬, `Command+A` 전체 선택, Finder형 파일 작업, 확인 후 macOS 휴지통 이동, Quick Look 미리보기 및 다른 앱으로 파일 첨부 드래그
- 팝오버 크기 조절·고정과 영역별 글자 크기 설정
- 로그인 시 실행, 단축키 변경과 충돌 안내
- 영어·한국어·일본어 UI
- 중복 앱 인스턴스 실행 방지

## 다운로드 및 설치

1. [GitHub Releases](https://github.com/parkcom/clipstow/releases)에서 최신 `ClipStow-*.dmg`를 다운로드합니다.
2. DMG를 열고 **ClipStow**를 **Applications(응용 프로그램)** 폴더로 드래그합니다.
3. 응용 프로그램 폴더에서 ClipStow를 실행합니다. Dock 대신 메뉴막대에 표시됩니다.

배포 파일은 Developer ID로 서명하고 Apple 공증을 거칩니다. macOS 13 Ventura 이상에서 실행되며 Apple Silicon과 Intel Mac을 모두 지원합니다.

아직 자동 업데이트 기능은 없습니다. 새 버전이 나오면 같은 Releases 페이지에서 내려받아 설치하세요.

## 소스에서 빌드

소스 빌드에는 Xcode 26 이상이 필요합니다.

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
- 폴더 탭에서 폴더를 선택하면 외부에서 파일을 추가·삭제·변경할 때 목록이 자동 갱신됩니다. 이름·수정일·크기 헤더로 양방향 정렬하고, Command-클릭으로 다중 선택하거나 `Command+A`로 모두 선택할 수 있습니다. 우클릭 메뉴에서는 열기, 다음으로 열기, 빠른 보기, Finder에서 보기, 이름 변경, 복제, 복사, 정보 가져오기와 확인 후 휴지통 이동을 사용할 수 있습니다. 파일 행은 다른 앱으로 드래그해 첨부할 수 있습니다.
- 팝오버 크기와 고정 상태, 앱 언어, 단축키 및 글자 크기는 설정에서 변경합니다.

## 저장과 개인정보

노트는 앱 샌드박스의 Application Support 아래 `ClipStow/store.json`에 원자적으로 저장됩니다. 일반적인 경로는 다음과 같습니다.

```text
~/Library/Containers/com.parkcom.clipstow/Data/Library/Application Support/ClipStow/store.json
```

Scratchpad 텍스트는 디스크에 저장하지 않습니다. 폴더 접근은 사용자가 선택한 폴더로 제한되며, 쓰기 권한은 사용자가 이름 변경, 복제 또는 확인 후 macOS 휴지통 이동을 명시적으로 실행할 때만 사용합니다. 앱 재실행 후 접근을 복원하기 위한 보안 범위 북마크만 저장합니다. 계정, 분석 도구, 텔레메트리, 클라우드 동기화 및 앱 자체 네트워크 통신도 없습니다. 자세한 내용은 [개인정보 안내](../PRIVACY.md)를 참고하세요.

Copy Capture는 `⌘C` 키를 감시하거나 가로채지 않고 `NSPasteboard.changeCount`를 250ms 간격으로 확인합니다. macOS가 Pasteboard 접근을 요청할 수 있으며, 거부했다면 시스템 설정에서 다시 허용해야 합니다.

## 제한사항

- 한 번의 폴링 사이에 덮어쓴 중간 클립보드 내용은 복구할 수 없습니다.
- 검색, 노트 내부 첨부 파일 저장, 태그, 동기화, 공유, 버전 기록 및 삭제 복구는 제공하지 않습니다.
- 저장하지 않은 Scratchpad는 앱 종료 시 사라집니다.
- 자동 업데이트는 제공하지 않으며 새 버전은 GitHub Releases에서 직접 설치해야 합니다.

버그 제보와 기여 방법은 [CONTRIBUTING.md](../CONTRIBUTING.md), 보안 문제 신고 방법은 [SECURITY.md](../SECURITY.md)를 확인하세요.

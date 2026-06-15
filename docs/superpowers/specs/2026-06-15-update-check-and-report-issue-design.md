# Update Check & Report Issue — Design Spec

- **Date**: 2026-06-15
- **Status**: Draft (awaiting user review)
- **Owner**: BottlePumpkin

---

## 1. Overview

두 가지 사용자 기능을 한 spec에 묶는다.

**Check for Updates** — Parallel이 새 버전이 나왔는지 GitHub Releases API로 확인하고, 새 버전이 있으면 사용자에게 알린다. 사용자는 release 페이지를 열거나 install 명령어를 복사해 직접 업데이트한다.

**Report Issue** — 사용자가 메뉴에서 issue를 보고하면 GitHub Issues "new issue" 페이지를 query string으로 prefill해 기본 브라우저로 연다. 사용자는 이미 GitHub에 로그인된 상태로 본문을 확인하고 Submit 한다.

### 한 줄 정의
두 기능 모두 **GitHub로 위임**한다. 앱은 API 호출(읽기) + URL 생성(쓰기 안내)만 책임지고, 인증·토큰·자동 설치는 하지 않는다.

### 비-목표 (안 하는 것)
- 자동 다운로드·설치 (Sparkle 같은 framework 도입 X — release 페이지로 안내만)
- OAuth / Personal Access Token / Keychain 토큰 관리
- 앱 안에서 직접 issue POST 또는 코멘트
- 로그 파일 본문 자동 첨부 (경로만 안내, 사용자가 첨부 여부 결정)
- enterprise GitHub 지원 (github.com 전용)

### 왜 만드나
- v0.1.x 시리즈에서 사용자가 새 버전을 알 길이 install 명령어 재실행밖에 없음
- 버그 신고 채널이 없어 사용자가 직접 GitHub에 가서 form을 채워야 함
- 두 기능 모두 작지만 OSS 앱의 표준 흐름이고, 추가 의존성 없이 가능

---

## 2. Tech Stack

| 영역 | 선택 | 이유 |
|---|---|---|
| HTTP | URLSession | 표준, dep 추가 없음 |
| JSON 디코드 | Codable | Release JSON 스키마는 단순 |
| 영속화 | UserDefaults | 마지막 체크 시각·skip 버전 같은 가벼운 메타 (workspace.json 안 건드림) |
| 브라우저 열기 | NSWorkspace | macOS 표준 |
| UI | SwiftUI Sheet + Alert | 기존 패턴 |
| 테스트 | XCTest + URLProtocol stub | URLSession을 격리해 모의 응답 |

새 의존성 0.

---

## 3. Architecture

### 파일 구조

```
Sources/Parallel/
├─ Services/
│  └─ UpdateChecker.swift          # GitHub Releases API + 캐시
├─ Util/
│  ├─ AppVersion.swift             # 현재 버전·OS·architecture 시그니처
│  ├─ IssueReporter.swift          # input → new-issue URL + 브라우저
│  └─ SemanticVersion.swift        # "0.1.4" 비교
└─ Views/
   ├─ Commands.swift               # 메뉴 두 항목 추가 (기존 파일 수정)
   └─ Sheets/
      ├─ UpdateAvailableSheet.swift
      └─ ReportIssueSheet.swift

Tests/ParallelTests/
├─ SemanticVersionTests.swift
├─ UpdateCheckerTests.swift        # URLProtocol stub
├─ IssueReporterTests.swift
└─ AppVersionTests.swift
```

### 컴포넌트 책임

| 컴포넌트 | 책임 | 의존 |
|---|---|---|
| **SemanticVersion** | "v0.1.4" 또는 "0.1.4" 입력을 `[Int]`로 파싱, Comparable | Foundation |
| **AppVersion** | 현재 앱 버전(Bundle), macOS 버전(ProcessInfo), architecture(`uname`)를 텍스트로 조립 | Bundle, ProcessInfo |
| **UpdateChecker** | `https://api.github.com/repos/BottlePumpkin/Parallel/releases/latest` GET. 결과를 `@Observable` published property로. 6시간 캐시. force flag로 캐시 무시 | URLSession, AppVersion |
| **IssueReporter** | title·body → GitHub Issues new URL (percent-encoded query). NSWorkspace.open. 실패 시 URL 클립보드 복사 | NSWorkspace |
| **UpdateAvailableSheet** | UpdateInfo를 받아 release notes + install 명령어 표시. 버튼: Open Release Page, Copy, Skip This Version, Later | UpdateChecker |
| **ReportIssueSheet** | title TextField + body TextEditor. body는 AppVersion 환경 정보로 prefill. "Open in Browser" 버튼 | IssueReporter, AppVersion |
| **Commands.swift** | 기존 ParallelCommands에 "Check for Updates…", "Report Issue…" 추가. `ContentActions`에 두 콜백 필드 추가 | — |

### 분리 원칙
- UpdateChecker는 UI를 모름 — 결과를 publish, sheet/alert가 관찰
- IssueReporter는 URL 빌드와 브라우저 열기만, GitHub 직접 통신 0
- AppVersion은 read-only static — 어디서든 호출

---

## 4. Data Model

```swift
struct SemanticVersion: Comparable, Equatable {
    let components: [Int]           // [0, 1, 4]
    init?(_ raw: String)            // "v0.1.4" / "0.1.4" → 통과. 그 외 nil
    var description: String         // "0.1.4"
}

// Pre-release / build metadata 정책:
// "0.1.5-beta1", "0.1.5+sha.abc" 같은 입력은 `-` / `+`에서 잘라 numeric core만 사용
// ("0.1.5"로 파싱). MVP 단계에선 pre-release를 따로 다루지 않는다.

struct UpdateInfo: Equatable {
    let latestTag: String           // "v0.1.5"
    let latestVersion: SemanticVersion
    let releaseURL: URL             // html_url
    let releaseNotes: String        // body (마크다운)
    let publishedAt: Date
}

enum UpdateCheckResult {
    case upToDate(current: SemanticVersion)
    case available(UpdateInfo)
    case failed(Error)
}

enum AppVersion {
    static var current: SemanticVersion  // CFBundleShortVersionString 파싱
    static var environmentSignature: String
        // """
        // - Parallel: 0.1.4
        // - macOS: 15.1 (24B83)
        // - Architecture: arm64
        // - Log: ~/Library/Logs/Parallel/parallel-<timestamp>.log
        // """
}
```

### Codable for GitHub Release

```swift
private struct ReleasePayload: Decodable {
    let tagName: String
    let htmlUrl: URL
    let body: String?
    let publishedAt: Date
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
        case publishedAt = "published_at"
    }
}
```

---

## 5. UserDefaults Keys

```swift
extension UserDefaults {
    var lastUpdateCheckAt: Date?       // "parallel.updateCheck.lastAt"
    var skippedUpdateVersion: String?  // "parallel.updateCheck.skippedVersion"
}
```

`workspace.json`은 worktree 데이터 전용으로 유지. 업데이트 메타는 분리.

---

## 6. Data Flow Scenarios

### Scenario A: 시작 시 자동 체크 (조용히)

```
ParallelApp.init → UpdateChecker 인스턴스
  → ContentView.task(id: "update-startup") {
        await checker.checkIfStale()
    }
  → checkIfStale:
       - lastUpdateCheckAt < 6시간 전 또는 nil이면 진행
       - URLSession GET (timeout 5s)
       - 200 OK → JSON 디코드 → SemanticVersion 비교
       - lastUpdateCheckAt = now
       - 새 버전이면 checker.updateAvailable = UpdateInfo
       - skipped 버전이면 publish 안 함 (조용)
       - 실패 → AppLogger.app.error만, publish 0
  → ContentView: onChange(of: checker.updateAvailable) 관찰
  → updateAvailable != nil, skipped와 다르면 UpdateAvailableSheet 표시
```

### Scenario B: 수동 체크

```
사용자 → 메뉴 Parallel → "Check for Updates…"
  → ContentActions.checkForUpdates() 호출
  → 작은 "Checking…" sheet
  → checker.check(force: true)
       - 캐시 무시, 항상 네트워크 호출
  → 결과:
       available → UpdateAvailableSheet
       upToDate  → Alert "You're on the latest version (0.1.4)"
       failed    → Alert "Couldn't reach GitHub: <msg>" + Retry / Cancel
```

수동은 결과를 항상 사용자에게 보여줌(자동과 차이).

### Scenario C: 새 버전 다이얼로그

UpdateAvailableSheet 내용:
- "Parallel 0.1.5 is available (you're on 0.1.4)"
- Release notes (스크롤 가능 영역, body 마크다운을 plain text로 표시)
- Install command 한 줄: `curl -fsSL https://raw.githubusercontent.com/BottlePumpkin/Parallel/master/scripts/install.sh | bash` + Copy 버튼
- 버튼 3개:
  - **Skip This Version** — `skippedUpdateVersion = "0.1.5"` 저장, sheet 닫기
  - **Later** — sheet만 닫기 (다음 체크 때 다시)
  - **Open Release Page** — `NSWorkspace.shared.open(releaseURL)`, sheet 닫기

### Scenario D: 이슈 신고

```
사용자 → 메뉴 Parallel → "Report Issue…"
  → ReportIssueSheet 표시
       Title:  [______________________]
       Body:   ## What happened?
               (입력)

               ## Steps to reproduce
               (입력)

               ---
               <!-- 자동 추가, 사용자가 지울 수 있음 -->
               **Environment**
               - Parallel: 0.1.4
               - macOS: 15.1 (24B83)
               - Architecture: arm64
               - Log: ~/Library/Logs/Parallel/parallel-<timestamp>.log
  → [Open in Browser] 클릭
  → IssueReporter.openNewIssue(title:, body:, labels: ["user-report"])
       - URL 빌드:
           https://github.com/BottlePumpkin/Parallel/issues/new
             ?title=<encoded>
             &body=<encoded>
             &labels=user-report
       - NSWorkspace.open
       - 실패 시: URL을 NSPasteboard에 복사 + 알림
  → sheet 닫기
```

---

## 7. Menu Integration

`Sources/Parallel/Views/Commands.swift`의 `ParallelCommands` 본문에 추가:

```swift
CommandGroup(replacing: .appInfo) {
    Button("About Parallel") { /* 기존 */ }
}
CommandGroup(after: .appInfo) {
    Button("Check for Updates…") { actions?.checkForUpdates() }
    Divider()
    Button("Report Issue…") { actions?.reportIssue() }
}
```

`ContentActions`에 두 필드 추가:
```swift
struct ContentActions {
    // 기존 …
    var checkForUpdates: () -> Void = {}
    var reportIssue: () -> Void = {}
}
```

`ContentView.focusedActions`에서 두 콜백 연결.

---

## 8. Error Handling

| 상황 | 자동 체크 | 수동 체크 |
|---|---|---|
| 5초 timeout | 조용 (log only) | "Couldn't reach GitHub" + Retry |
| HTTP 4xx/5xx | 조용 | 메시지에 status code |
| JSON 디코드 실패 | 조용 (본문 첫 100자 log) | "Unexpected response from GitHub" |
| 이미 최신 | 표시 없음 | "You're on the latest version (X.Y.Z)" |
| 사용자가 skip한 버전 | 표시 없음 | 표시 — 사용자가 manual 요청했으니 |

`NSWorkspace.open` 실패 (Issue Reporter):
- URL을 `NSPasteboard.general`에 복사
- "Couldn't open browser — URL copied to clipboard" 알림

---

## 9. Testing Strategy

### Unit (XCTest)

**SemanticVersionTests**
- `init("v0.1.4")` → components `[0,1,4]`
- `init("0.1.4")` 마찬가지
- `init("1.2")` 통과 (2-요소 OK)
- `init("not a version")` → nil
- `0.1.4 < 0.1.5`
- `0.1.10 > 0.1.9`
- `0.1.4 < 0.2.0`
- `1.0.0 > 0.99.99`

**UpdateCheckerTests** (URLProtocol stub)
- 200 OK + newer tag → `.available`
- 200 OK + same tag → `.upToDate`
- 200 OK + older tag → `.upToDate` (downgrade 안 권장)
- 403 rate limit → `.failed`
- timeout → `.failed`
- 잘못된 JSON → `.failed`
- 캐시: `lastUpdateCheckAt < 6시간`이면 네트워크 호출 안 함 (mock으로 검증)
- `force: true`이면 캐시 무시

**IssueReporterTests**
- title에 `#`, `&`, `?`, 줄바꿈, 한글 → percent-encoded
- body가 비어 있어도 URL 빌드 가능
- labels 배열이 `,` 조인되어 인코딩
- URL이 `https://github.com/BottlePumpkin/Parallel/issues/new?...` 형식

**AppVersionTests**
- `current`가 Bundle infoDictionary의 `CFBundleShortVersionString`을 SemanticVersion으로 파싱
- `environmentSignature`가 4줄 (Parallel/macOS/Architecture/Log) 포함

### Manual
- UpdateAvailableSheet 모든 버튼 동작 확인
- ReportIssueSheet에서 본문 편집 → Open in Browser → GitHub Issues 페이지가 prefill된 채로 열림 확인
- 메뉴 단축키 없음, 메뉴 클릭으로만

새 unit test 약 15-20개.

---

## 10. Operational Defaults

| # | 항목 | 결정 |
|---|---|---|
| 1 | 자동 체크 주기 | 마지막 체크 후 6시간 |
| 2 | 자동 체크 실패 | 조용 (log only) |
| 3 | 수동 체크 결과 | 항상 사용자에게 표시 |
| 4 | Skip 처리 | `skippedUpdateVersion` UserDefaults |
| 5 | 새 더 높은 버전 나오면 | skip 무효 — 다시 알림 |
| 6 | 자동 다운로드/설치 | X — release 페이지 또는 install 명령어 안내 |
| 7 | Issue body 환경 정보 | 버전·macOS·architecture·로그 경로 4줄 prefill |
| 8 | Issue labels | `user-report` 자동 |
| 9 | Issue 본문 로그 첨부 | X — 경로만, 사용자가 GitHub에서 직접 첨부 |
| 10 | 네트워크 timeout | 5초 |
| 11 | 캐시 정책 | "지난 체크 시각"만 UserDefaults 영속화. 응답 본문은 캐시하지 않음 — 다음 체크 때 새로 GET |
| 12 | 메뉴 위치 | `Parallel` 앱 메뉴, About 아래 |
| 13 | 인증 | 0 (GitHub 위임) |

---

## 11. Effort Estimate

| 페이즈 | 내용 | 시간 |
|---|---|---|
| 1 | SemanticVersion + tests | 1h |
| 2 | AppVersion + tests | 1h |
| 3 | UpdateChecker + tests (URLProtocol stub) | 2-3h |
| 4 | IssueReporter + tests | 1h |
| 5 | UpdateAvailableSheet | 1.5h |
| 6 | ReportIssueSheet | 1.5h |
| 7 | Commands.swift 통합, focusedActions 연결 | 0.5h |
| 8 | 폴리시 (에러 메시지, copy 토스트 등) | 1-2h |
| **합계** | | **9-12h ≈ 2-3일 저녁** |

---

## 12. Open Questions / v2 Ideas

MVP 범위 밖 — 기록만.

- About 다이얼로그 자체 구현 (현재 macOS 기본 사용 중)
- Sparkle로 자동 다운로드/설치 도입
- Issue 신고 시 스크린샷 캡처 첨부 (현재는 텍스트만)
- 사내 GHE 지원을 위한 base URL 설정
- 자동 체크 주기 사용자 설정화 (현재 6시간 고정)
- "Don't check for updates" 토글 (현재 항상 체크)

---

## 13. Out of Scope (재확인)

- GitHub OAuth/Device Flow
- 앱 안에서 직접 POST API 호출 (issues, comments, reactions)
- 로그 본문을 issue body에 자동 첨부
- 자동 download/install (release zip 받기, 압축 풀기, /Applications 교체)
- 사용자 알림 권한 흐름 (현재 UNUserNotification만 사용 — 업데이트는 sheet/alert)

이상.

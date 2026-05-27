# Parallel — Design Spec

- **Date**: 2026-05-27
- **Status**: Draft (awaiting user review)
- **Owner**: BottlePumpkin

---

## 1. Overview

**Parallel**은 macOS용 데스크탑 앱이다. 사용자는 여러 git worktree를 동시에 만들어두고 각각 다른 작업(Claude Code 세션 포함)을 병렬로 돌리는데, 터미널 탭이 산만하게 늘어나는 문제를 해결한다.

### 한 줄 정의
worktree 목록을 한 윈도우에서 시각화하고, 각 worktree마다 전용 PTY 세션을 띄워 한 곳에서 전환·관리할 수 있게 한다.

### 비-목표 (안 하는 것)
- Git 호스팅(GitHub/GHE) API 통합 — 모든 git 동작은 CLI 호출
- PR 생성·머지·diff viewer
- Claude Code·기타 AI agent 특수 통합 — PTY 안에서 사용자가 직접 실행
- 터미널 multiplexing(분할·여러 PTY 동시 표시)

### 왜 만드나 (Why)
- Conductor는 좋았으나 사내 git enterprise 호환 문제로 회사에서 못 씀
- 사용자가 30개 가까운 worktree를 ad-hoc하게 운영 중 (`my-flutter-app/.claude/worktrees/feat-ISSUE-XXXX`)
- 터미널 탭이 많아져 어디가 무엇인지 추적이 안 되는 게 1순위 페인 포인트
- 본인 작성 앱이면 신뢰·배포·notarization을 본인이 통제 가능

---

## 2. Tech Stack

| 영역 | 선택 | 이유 |
|---|---|---|
| 언어/UI | Swift + SwiftUI | 네이티브 macOS, 사용자 Swift 경험 있음 |
| 터미널 렌더링 | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | xterm escape sequence 지원 성숙도, PTY 통합 예제 제공 |
| Git | `Process`로 git CLI 호출 | enterprise 호환의 핵심 — 어떤 git host든 동작 |
| 영속화 | `Codable` + JSON 파일 | 의존성 최소화, 사람이 읽을 수 있음 |
| 로깅 | `os.Logger` | Console.app 통합, 디버그 빌드만 파일 로깅 |
| 배포 | (v2) Apple Developer 계정으로 공증 | 본인 + 동료 배포 가능하게 |

---

## 3. App Shape

Conductor형 메인 윈도우.

```
╔═══════════════════════════════════════════════════════╗
║ + New worktree                                         ║
╠═══════════════════╦═══════════════════════════════════╣
║ ▾ my-flutter-app     ║ $ flutter run                     ║
║   ● ISSUE-3625      ║ ... terminal output ...           ║
║   ● ISSUE-3640  ⚠️  ║                                   ║
║   ○ ISSUE-3679      ║                                   ║
║   ○ feat/ad-bs    ║                                   ║
║   💤 crow-flying  ║                                   ║
║ ▾ monetization    ║                                   ║
║   ● fix/something ║                                   ║
║                   ║ [3 changed]   [branch: feat/...]  ║
╚═══════════════════╩═══════════════════════════════════╝
```

- 좌측 사이드바: repo 그룹 헤더 + worktree 항목. 상태 표시(active ●, idle ○, dead 💤, error ⚠️)
- 우측 패널: 선택된 worktree의 SwiftTerm view. 하단에 변경파일 수·브랜치명 표시
- 상단 toolbar: "+ New worktree" 버튼

---

## 4. Architecture

### 폴더 구조

```
Parallel/
├─ ParallelApp.swift              # SwiftUI App entry
├─ Views/
│  ├─ ContentView.swift           # NavigationSplitView 컨테이너
│  ├─ SidebarView.swift           # worktree 리스트
│  ├─ TerminalPaneView.swift      # SwiftTerm 호스트
│  └─ Sheets/
│     ├─ AddRepoSheet.swift       # repo 등록
│     └─ NewWorktreeSheet.swift   # worktree 생성
├─ Services/
│  ├─ WorktreeService.swift       # git CLI wrapper
│  ├─ SessionManager.swift        # PTY ↔ Worktree 매핑
│  └─ StatusWatcher.swift         # git status 폴링
├─ Models/
│  ├─ Worktree.swift
│  ├─ Repo.swift
│  ├─ WorktreeStatus.swift
│  └─ Session.swift
└─ Persistence/
   └─ WorkspaceStore.swift        # workspace.json 읽기/쓰기
```

### 컴포넌트 책임

| 컴포넌트 | 책임 | 의존 |
|---|---|---|
| WorktreeService | `git worktree add/remove/list` 호출, 결과 파싱, 디렉토리 sanitize | `Process`, FileManager |
| SessionManager | worktree마다 PTY 한 개 lifecycle (fork·종료·재시작·SIGTERM/SIGKILL) | SwiftTerm, posix PTY |
| StatusWatcher | 등록된 worktree들에 대해 5초마다 `git status --porcelain` 호출, 결과를 Store에 반영. 창 비활성 시 일시정지 | WorkspaceStore (읽기) |
| WorkspaceStore | repos·worktrees·lastSelectedId를 JSON으로 영속화. `@Observable`로 SwiftUI 관찰 | Codable |
| SidebarView | 리스트·배지·선택 이벤트 발행 | WorkspaceStore |
| TerminalPaneView | 현재 선택된 Session의 SwiftTerm view 표시. 세션 없으면 placeholder + Restart 버튼 | SessionManager |
| AddRepoSheet | 폴더 선택 → repo 등록 → 기존 worktree 자동 발견 후 import 옵션 | WorktreeService, WorkspaceStore |
| NewWorktreeSheet | 브랜치명·base 입력 → `WorktreeService.create()` → setup 명령 prefill | WorktreeService, SessionManager |

### 분리 원칙
- View는 상태 표시·이벤트 발행만 (git/PTY 직접 호출 금지)
- Service는 한 외부 시스템만 담당 (Worktree=git, Session=PTY)
- Store가 단일 진실 원천 — 모든 View가 Store를 관찰

---

## 5. Data Model

```swift
struct Repo: Identifiable, Codable {
    let id: UUID
    var root: URL                       // 메인 repo 경로
    var displayName: String             // 사이드바 그룹 헤더
    var worktreeBaseDir: String         // 기본 ".claude/worktrees"
    var defaultSetupCommands: [String]  // 새 worktree 생성 시 prefill될 명령
}

struct Worktree: Identifiable, Codable {
    let id: UUID
    var repoId: UUID
    var path: URL                       // 실제 worktree 경로
    var branch: String                  // 체크아웃된 브랜치
    var displayName: String             // 사용자 수정 가능
    var createdAt: Date
    var lastUsedAt: Date
    var setupCommands: [String]         // 이 worktree 한정 명령 (생성 시 repo default에서 복사 후 수정 가능)
}

struct WorktreeStatus: Equatable {      // 영속화 X — StatusWatcher가 채움
    var isDirty: Bool
    var changedFiles: Int
    var ahead: Int
    var behind: Int
    var lastCheckedAt: Date
    var lastError: String?              // status 실패 시 ⚠️ 배지 표시용
}

// 영속화 안 함 — 앱 재시작 시 SessionManager가 새로 fork
final class Session {
    let worktreeId: UUID
    var pid: pid_t
    var terminal: TerminalView          // SwiftTerm
    var state: SessionState             // .running | .exited(code: Int32)
}
```

---

## 6. Directory Convention

```
<repo.root>/<repo.worktreeBaseDir>/<sanitized-branch>
```

- 기본 base = `.claude/worktrees` (사용자가 my-flutter-app에서 이미 쓰는 패턴)
- sanitize: `/` → `-`, 공백 제거, 소문자 권장 (`feature/ISSUE-3625` → `feat-ISSUE-3625`)
- 같은 이름 존재 시 `-2`, `-3` suffix. 다이얼로그에서 최종 경로 미리보기
- `.gitignore`에 `.claude/worktrees/` 한 줄 추가 권장 (onboarding에서 안내)

---

## 7. PTY Integration

### 셸 선택
1. `SHELL` 환경변수
2. fallback `/bin/zsh`

### Fork 시 환경
- `cwd` = worktree path
- `TERM=xterm-256color`
- 사용자 `.zshrc`/`.bashrc`는 셸이 자동 로드 (PATH, fvm, mise 등 보존)
- 추가 env 주입은 v2 (MVP는 빈 dict)

### Setup 명령 자동 입력
- 셸 prompt 노출 후 500ms 지연
- PTY stdin에 명령 + `\n` 한 줄씩 enqueue
- 이전 명령 완료 여부 확인 X — 사용자가 직접 친 것처럼 처리
- 실패해도 별도 알림 X (사용자가 출력 보고 판단)

### 세션 라이프사이클
- worktree 생성 시 즉시 fork (lazy 안 함)
- 셸 종료(`exit`) 시 `state = .exited`, 사이드바 💤 아이콘, 터미널 영역에 "Restart Session" 버튼
- worktree 삭제 시 SIGTERM → 2초 후 SIGKILL
- 앱 종료 시 모든 세션에 SIGTERM (cleanup)

### 영속성 한계 (수용)
- 앱 재시작 → PTY 다시 fork → **스크롤백·실행 중이던 명령 사라짐**
- onboarding에서 1줄 안내
- detach/reattach는 v2 검토

---

## 8. Data Flow Scenarios

### Scenario A: 새 worktree 생성
```
User → "+ New worktree" 클릭
  → NewWorktreeSheet 표시 (selectedRepo의 defaultSetupCommands가 prefill)
  → User: branch="feat/foo", setup=["fvm flutter pub get"], 확인
  → WorktreeService.create(repo:branch:base:dir:)
      ← git worktree add <path> -b <branch> <base>
  → 성공 시 WorkspaceStore.addWorktree(...)
  → SessionManager.startSession(for: worktree)   // PTY fork
  → 500ms 후 setup 명령 자동 입력
  → SidebarView 자동 갱신, 새 항목 선택
  실패 시: 모달 다이얼로그로 에러 표시, sheet 유지
```

### Scenario B: worktree 전환
```
User → 사이드바 항목 클릭
  → ContentView.selectedWorktreeId 변경
  → TerminalPaneView가 SessionManager.session(for: id) 가져옴
  → SwiftTerm view 교체 (백그라운드 PTY는 계속 살아있음)
```

### Scenario C: 상태 갱신
```
StatusWatcher (5초 타이머, 창 active일 때만)
  → 모든 worktree 순회
  → 각각 비동기로 `git status --porcelain` + `git rev-list --count`
  → 결과 차이 있으면 WorkspaceStore의 status 갱신
  → SwiftUI가 사이드바 배지 자동 재렌더
실패 시: WorktreeStatus.lastError 설정 → ⚠️ 배지 + 클릭 시 상세
```

### Scenario D: worktree 삭제
```
User → 사이드바 항목 우클릭 → "Delete worktree" 또는 Cmd+Shift+⌫
  → 확인 다이얼로그
  → SessionManager.terminate(worktreeId)   // SIGTERM → SIGKILL
  → WorktreeService.remove(path: force: false)
      git worktree remove <path>
  → 실패 시(uncommitted 변경 등) "Force delete?" 다이얼로그
  → 성공 시 WorkspaceStore.removeWorktree(id)
```

### Scenario E: 기존 worktree 임포트
```
User → "Add Repository" → 폴더 선택
  → WorktreeService.list(repo:)
      git worktree list --porcelain
  → 기존 worktree 발견 시 체크박스 리스트로 표시 ("Select which to import")
  → 선택된 것만 WorkspaceStore에 추가
  → 각각 SessionManager가 PTY fork
```

---

## 9. Operational Defaults

| # | 항목 | 결정 |
|---|---|---|
| 1 | StatusWatcher 폴링 주기 | 5초. 창 비활성/최소화 시 일시정지. 동시 실행 한도 4 (worktree 많을 때 시스템 부하·rate 보호) |
| 2 | 키보드 단축키 | `Cmd+1~9` 전환 / `Cmd+N` 새 worktree / `Cmd+W` 세션만 닫기 / `Cmd+Shift+⌫` worktree 완전 삭제 (확인) |
| 3 | 세션 영속성 | 재시작 시 PTY 새로 fork. 스크롤백 사라짐. onboarding에서 안내 |
| 4 | 죽은 세션 UX | 사이드바 💤 + 터미널 영역 placeholder + "Restart Session" 버튼 |
| 5 | setup 명령 실패 처리 | PTY 출력만으로 충분. 별도 알림 X |
| 6 | setup 명령 scope | Repo의 `defaultSetupCommands` + Worktree의 `setupCommands` override |
| 7 | displayName 충돌 | 허용. repo 그룹으로 묶이니 시각 구분 충분 |
| 8 | base 디렉토리 | repo별 설정, 기본 `.claude/worktrees` |
| 9 | App Sandbox | 끔 (개인용). 배포 시 다시 검토 |
| 10 | 에러 처리 | 사용자 액션 직후 실패=모달 / 백그라운드 실패=사이드바 ⚠️ + 클릭 상세 |
| 11 | 테스트 | WorktreeService·WorkspaceStore unit test. git CLI는 임시 repo로 통합. PTY·SwiftUI는 수동 |
| 12 | 로깅 | `os.Logger` 기본 + 디버그 빌드는 `~/Library/Logs/Parallel/parallel.log` |

---

## 10. Persistence Format

`~/Library/Application Support/Parallel/workspace.json`

```json
{
  "version": 1,
  "repos": [
    {
      "id": "uuid-1",
      "root": "~/dev/my-flutter-app",
      "displayName": "my-flutter-app",
      "worktreeBaseDir": ".claude/worktrees",
      "defaultSetupCommands": ["fvm flutter pub get"]
    }
  ],
  "worktrees": [
    {
      "id": "uuid-2",
      "repoId": "uuid-1",
      "path": "/Users/.../my-flutter-app/.claude/worktrees/feat-ISSUE-3625",
      "branch": "feat/ISSUE-3625",
      "displayName": "ISSUE-3625",
      "createdAt": "2026-05-20T09:00:00Z",
      "lastUsedAt": "2026-05-27T10:00:00Z",
      "setupCommands": ["fvm flutter pub get"]
    }
  ],
  "lastSelectedWorktreeId": "uuid-2"
}
```

- `version` 필드로 향후 마이그레이션 대응
- 손상된 파일 발견 시 `workspace.json.corrupted-<timestamp>`로 이동 후 새로 시작 + 사용자 알림

---

## 11. Effort Estimate

사이드 프로젝트(저녁·주말), Swift 경험 있음 기준.

| 페이즈 | 내용 | 시간 |
|---|---|---|
| 0 | Spike: SwiftTerm + posix PTY fork 검증 | 2-4h |
| 1 | 핵심 골격 (NavigationSplitView, Sidebar, TerminalPane) | 12-16h |
| 2 | WorktreeService (git CLI wrapper) + WorkspaceStore | 6-8h |
| 3 | NewWorktreeSheet + AddRepoSheet + setup 자동 입력 | 6-8h |
| 4 | StatusWatcher + 사이드바 배지 | 4-6h |
| 5 | 키보드 단축키 + 영속성 + 죽은 세션 UX + 에러 다이얼로그 | 6-10h |
| **합계** | | **36-52h ≈ 3-4주** |

가장 큰 리스크: 페이즈 0. SwiftTerm 통합이 예상보다 더 걸리면 +1주. 그래서 spike를 먼저.

---

## 12. Open Questions / v2 Ideas

다음은 MVP 범위 밖이지만 기록.

- **세션 detach/reattach** — `tmux`처럼 PTY 출력을 백그라운드 프로세스에 영속화 (현재는 앱 재시작 시 손실)
- **추가 환경변수 주입** — repo별 env dict
- **공증·자동 업데이트** — Apple Developer 계정으로 공증, Sparkle로 자동 업데이트
- **다른 사용자에게 배포** — 사내 동료에게 배포할 경우 entitlement·sandboxing 재검토
- **명령 history / 자주 쓰는 명령 단축키** — repo별 quick command panel
- **PR 워크플로 연동** — `gh pr create` 같은 거 단축버튼 (CLI 의존)
- **터미널 search·복사 UX 폴리시**

---

## 13. Out of Scope (재확인)

- AI agent 상태 파싱·통합
- Git 호스팅 API
- 코드 diff viewer
- 멀티 PTY 분할
- 모바일·웹·Windows·Linux

이상.

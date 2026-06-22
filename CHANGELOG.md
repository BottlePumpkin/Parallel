# Changelog

All notable changes to Parallel are documented here.
## [Unreleased]

### Bug Fixes

- **release:** Annotated tag + atomic rollback + not-behind preflight ([`65ba87e`](https://github.com/BottlePumpkin/Parallel/commit/65ba87e355fe23c2e4ec68f25a7566214e8ab54a))
- **views:** Auto-focus terminal on worktree/tab switch (#10) ([`e5a107c`](https://github.com/BottlePumpkin/Parallel/commit/e5a107c4547ccca294afb6c264108223c6caf568))

### Features

- **views:** In-app `git init` for non-git folders in Add Repository ([`35fb333`](https://github.com/BottlePumpkin/Parallel/commit/35fb33386e70e96c7fefab4501288d3685d49d4f))
## [v0.3.0](https://github.com/BottlePumpkin/Parallel/compare/v0.2.0...v0.3.0) (2026-06-19)

### Bug Fixes

- **services:** Guard redundant active-tab writes; cover orderedWorktrees edges ([`76a34b2`](https://github.com/BottlePumpkin/Parallel/commit/76a34b212a01b77ececb67a5130ba207373238da))

### Features

- **views:** Wire terminal/worktree keyboard shortcuts into menus ([`38c000c`](https://github.com/BottlePumpkin/Parallel/commit/38c000c7db67d72cf646ae40754d066063564b22))
- **services:** Tab switch/clear/find actions on SessionManager ([`36c8da2`](https://github.com/BottlePumpkin/Parallel/commit/36c8da273dabd85561b5b991ed59727ace8a477f))
- **services:** Tab-cycle index math + sidebar-ordered worktrees ([`4c05c13`](https://github.com/BottlePumpkin/Parallel/commit/4c05c138292a98465437d4cda3df026f03fb5231))
## [v0.2.0](https://github.com/BottlePumpkin/Parallel/compare/v0.1.6...v0.2.0) (2026-06-18)

### Bug Fixes

- **views:** Hide ManualCheckSheet OK button during .checking ([`11a924a`](https://github.com/BottlePumpkin/Parallel/commit/11a924a6bc761435d37b5589837578c9689799d0))

### Features

- **views:** Wire UpdateChecker + sheets into ContentView and ParallelApp ([`d307429`](https://github.com/BottlePumpkin/Parallel/commit/d30742903afdce188ca0bbd0ab6a41aa9a313a14))
- **views:** Parallel menu — Check for Updates + Report Issue ([`2e9560e`](https://github.com/BottlePumpkin/Parallel/commit/2e9560eda3ecaf83cf857c1928b1e833600ddc72))
- **views:** ReportIssueSheet — title + body + Open in Browser ([`222dd3e`](https://github.com/BottlePumpkin/Parallel/commit/222dd3e468c0fb838fc1c582a4b503e6675e25fd))
## [v0.1.6](https://github.com/BottlePumpkin/Parallel/compare/v0.1.5...v0.1.6) (2026-06-18)

### Bug Fixes

- **services:** Bound StatusWatcher git polling with OperationQueue to stop thread explosion ([`2aeeb6d`](https://github.com/BottlePumpkin/Parallel/commit/2aeeb6d79dda191ce0d4fed6c0c3a8682deabe1f))
- **views:** Cancel Copy/Copied reset task on sheet dismiss ([`ee7fd55`](https://github.com/BottlePumpkin/Parallel/commit/ee7fd555311c879816f6847ec74808e672e03e9d))

### Features

- **views:** UpdateAvailableSheet — release notes + Skip/Later/Open ([`dfbf617`](https://github.com/BottlePumpkin/Parallel/commit/dfbf617d6d8b07809404398d4cec862e235eb9b2))
## [v0.1.5](https://github.com/BottlePumpkin/Parallel/compare/v0.1.4...v0.1.5) (2026-06-17)

### Bug Fixes

- **services:** Publish readSource before resume to avoid early lost-pause race ([`ce4d592`](https://github.com/BottlePumpkin/Parallel/commit/ce4d592c1f8c66cc2a3080075b706bfe60b23ab3))
- **services:** Make PTY backpressure thread-safe (apply pause/resume under coalescer lock) ([`ce03c1a`](https://github.com/BottlePumpkin/Parallel/commit/ce03c1a6d30d520e3c9a99c35925832840bd7bb0))
- **services:** Apply PTY read backpressure from coalescer watermarks ([`7aabfd8`](https://github.com/BottlePumpkin/Parallel/commit/7aabfd853447cbca8da1c3c25c8b1de80cde021a))
- **services:** Cap per-hop terminal feed so a burst can't freeze a frame ([`dc4c2b1`](https://github.com/BottlePumpkin/Parallel/commit/dc4c2b17b8e8c331493aedcc1e460fac7defe7c8))
- **services:** Coalesce PTY output to one main-thread feed per cycle ([`02f2561`](https://github.com/BottlePumpkin/Parallel/commit/02f25618fd0e8baa857162155b51b57ebfe1d737))
- **util:** SemanticVersion rejects empty parts + Hashable honors padding ([`c018662`](https://github.com/BottlePumpkin/Parallel/commit/c018662fb4b108a1ba479450bd5a4f94291c6c03))

### Features

- **services:** PTY pauseReading/resumeReading with balanced suspend ([`d384799`](https://github.com/BottlePumpkin/Parallel/commit/d38479906547fc55b49eab4e5efc6e059bb17379))
- **services:** Coalescer high/low-watermark backpressure signals ([`1922391`](https://github.com/BottlePumpkin/Parallel/commit/192239156b404251f5a480585c7f5b58416bc476))
- **services:** UpdateChecker — GitHub Releases polling with cache + skip ([`48863cd`](https://github.com/BottlePumpkin/Parallel/commit/48863cd02b762b4a6bd209ea1768784597fcc75c))
- **util:** UserDefaults keys for update-check cache + skip state ([`ca763ec`](https://github.com/BottlePumpkin/Parallel/commit/ca763ec8865d5324084a59afec731731db4077de))
- **util:** IssueReporter — prefilled GitHub new-issue URL + NSWorkspace open ([`3fc76e9`](https://github.com/BottlePumpkin/Parallel/commit/3fc76e9810ac7f91009328e2974b497bc8540b4e))
- **util:** AppVersion signature builder for issue templates ([`22ecfa4`](https://github.com/BottlePumpkin/Parallel/commit/22ecfa40f9595d01661fdddeb746d0bc3721991f))
- **util:** SemanticVersion comparable tag parser ([`7e495d7`](https://github.com/BottlePumpkin/Parallel/commit/7e495d7003aa09989020da4a2792a1cd1102b904))
## [v0.1.4](https://github.com/BottlePumpkin/Parallel/compare/v0.1.3...v0.1.4) (2026-06-15)

### Bug Fixes

- **views:** Bump SwiftTerm scrollback to 10000 so worktree/tab switches stop truncating history ([`e6b307f`](https://github.com/BottlePumpkin/Parallel/commit/e6b307f50314cab07670d82eb19878ad5d9c6292))
## [v0.1.3](https://github.com/BottlePumpkin/Parallel/compare/v0.1.2...v0.1.3) (2026-06-12)

### Bug Fixes

- **brand:** Mask icon source PNG so the checkerboard background isn't baked in ([`3e9f30b`](https://github.com/BottlePumpkin/Parallel/commit/3e9f30bd4adea311c691b7defb4b1206779b515f))
## [v0.1.2](https://github.com/BottlePumpkin/Parallel/compare/v0.1.1...v0.1.2) (2026-06-12)

### Bug Fixes

- **views:** Re-sync terminal frame + layout when a hidden tab becomes visible ([`6f3da95`](https://github.com/BottlePumpkin/Parallel/commit/6f3da95950c1b7d8222d8c0da5176145068ca4ff))

### Features

- **brand:** Add app icon ([`e01eafe`](https://github.com/BottlePumpkin/Parallel/commit/e01eafe91849d4d089c5e04f4fa94a9f3d6e331e))
## [v0.1.1](https://github.com/BottlePumpkin/Parallel/compare/v0.1.0...v0.1.1) (2026-06-12)

### Bug Fixes

- **build:** Ad-hoc codesign + ditto-based zip ([`f7fc6da`](https://github.com/BottlePumpkin/Parallel/commit/f7fc6dadf46aacb20225f1cfad4d8b7881eb3985))
## v0.1.0 (2026-06-11)

### Bug Fixes

- **views:** Hide inactive terminal NSViews so they don't steal mouse drags ([`e413ea5`](https://github.com/BottlePumpkin/Parallel/commit/e413ea54cee35e8c396b9df34c034548dbba6224))
- Guard notifications when running outside a .app bundle ([`1ba7592`](https://github.com/BottlePumpkin/Parallel/commit/1ba7592050ede685f251272ac040d1cf457a6f06))
- **views:** Move ensureSession out of TerminalPaneView.body to break observation loop ([`eb1cb4a`](https://github.com/BottlePumpkin/Parallel/commit/eb1cb4ae3e0d4d80b787618bbca1a22ef1dc2882))
- **views:** Keep SwiftTerm views permanently mounted to preserve scroll state ([`05f9e9a`](https://github.com/BottlePumpkin/Parallel/commit/05f9e9abbc73598846296e76d37a628eb44c329a))
- Address code-review findings + first-click new worktree sheet bug ([`af045c8`](https://github.com/BottlePumpkin/Parallel/commit/af045c81a66f0a9ad067330e263d71046bbbd47d))
- **store:** Dedupe repos by root path on load + merge import into existing repo ([`4efcb1b`](https://github.com/BottlePumpkin/Parallel/commit/4efcb1bb4295dbc8a5714b2f3539bb1ad4191fdf))
- **views:** Use Nerd Font v3 family name (MesloLGS Nerd Font Mono) ([`3e71ed0`](https://github.com/BottlePumpkin/Parallel/commit/3e71ed081751006da27e676477cabd50da640d89))
- **pty:** Guard against SwiftTerm's initial 0×0 layout (cols=-1, rows=0) ([`5aada37`](https://github.com/BottlePumpkin/Parallel/commit/5aada3704f0b54b819e7213a4b0ade9723ca9951))
- **services:** PTY fd lifetime, login shell, terminate pid-recycling safety ([`c682f6e`](https://github.com/BottlePumpkin/Parallel/commit/c682f6e5cae407e206c26aceaf0a9f62d0c8e855))
- **services:** WorktreeService.parseList robustness + bare/edge case tests ([`607f779`](https://github.com/BottlePumpkin/Parallel/commit/607f7792b653d398fb989d2de974715452e0180e))
- **services:** GitCLI drain pipes concurrently + UTF-8 fallback, drop unused timeout ([`32d856e`](https://github.com/BottlePumpkin/Parallel/commit/32d856ec77d7b0c0cb7b8b423e3eaacab8f0e535))
- **persistence:** Use whole-second Date precision to eliminate round-trip flakiness ([`68c7a36`](https://github.com/BottlePumpkin/Parallel/commit/68c7a366065bec41872f77aa5b2c4cea859e13c5))

### Features

- **views:** Drag-reorder repository groups in the sidebar ([`3e64bc2`](https://github.com/BottlePumpkin/Parallel/commit/3e64bc297df866310573858d0624749cce918a5d))
- Toolbar coffee-cup toggle that prevents display/system sleep ([`1deb549`](https://github.com/BottlePumpkin/Parallel/commit/1deb549347a9c26032f47cee4ea3e67be01ee690))
- Persist tab strip (count + labels) across app restarts ([`d87e92e`](https://github.com/BottlePumpkin/Parallel/commit/d87e92e64bbcb4e21d3584e12be43fcffc36c51d))
- Guard non-git folders and let users remove repositories ([`9dcec72`](https://github.com/BottlePumpkin/Parallel/commit/9dcec7215ea78e362e67a375025cd8f438e0ce7d))
- **views:** Rename terminal tabs via tab context menu ([`4cdee15`](https://github.com/BottlePumpkin/Parallel/commit/4cdee15534423f097599386049f6293898341dcf))
- **views:** Treat repo root as an importable worktree ([`48cd30f`](https://github.com/BottlePumpkin/Parallel/commit/48cd30f9aed79c94b60d20f441c1e6cd51d18783))
- Post macOS notification when a shell session exits ([`89822ed`](https://github.com/BottlePumpkin/Parallel/commit/89822ed9ed4cfbc553d01eea191d88455b8848e3))
- **views:** "Open in" submenu — Finder, Cursor, VS Code, Android Studio, IntelliJ, Xcode ([`5318d67`](https://github.com/BottlePumpkin/Parallel/commit/5318d6720ac67b1399d91c37429fc2039393191d))
- **views:** Search filter in ImportWorktreesSheet ([`0ea1d44`](https://github.com/BottlePumpkin/Parallel/commit/0ea1d44d5fa68e243cdbe31790c6264637aad7d1))
- Multiple terminal tabs per worktree ([`60ec6f3`](https://github.com/BottlePumpkin/Parallel/commit/60ec6f36039f63970aafd06d9a46ffa8209081c4))
- **util:** Mirror stderr/stdout to ~/Library/Logs/Parallel/parallel-<ts>.log ([`2ba215e`](https://github.com/BottlePumpkin/Parallel/commit/2ba215e3abeb008824ba670896de08a6007c8b7f))
- **views:** Drag-reorder worktrees within a repo section ([`ef967bb`](https://github.com/BottlePumpkin/Parallel/commit/ef967bb5292676592987e150a0d5861d253c98df))
- Recent section at top of Base dropdown + cap remotes display ([`fdb5857`](https://github.com/BottlePumpkin/Parallel/commit/fdb5857bd4af1d5d5ecdeacfb5ca327311b6d64f))
- List remote-tracking branches in NewWorktreeSheet base dropdown ([`c543963`](https://github.com/BottlePumpkin/Parallel/commit/c543963cd0873aedebb38d267839e36d7141f1e4))
- **views:** Add "Remove from Parallel" context menu item ([`af0b192`](https://github.com/BottlePumpkin/Parallel/commit/af0b192eea74ddb2668595dfc452fb4c0c9169a1))
- Optional branch deletion when removing a worktree ([`95af92c`](https://github.com/BottlePumpkin/Parallel/commit/95af92cd52b1a21f719d35c3ee12ea036d3525fa))
- **views:** Tooltip on changed-files badge explaining what the number means ([`d60d17d`](https://github.com/BottlePumpkin/Parallel/commit/d60d17da64905db1e850eb2bf106270eb1770615))
- **views:** Show git branch as secondary line under displayName when they differ ([`39b0058`](https://github.com/BottlePumpkin/Parallel/commit/39b0058ca83bd190d0916bc823b6fc727f713d2d))
- **views:** Rename worktree via right-click → "Rename…" ([`88dc785`](https://github.com/BottlePumpkin/Parallel/commit/88dc7853ec6cb7d0d96a8d430c71ea2af92b3b4b))
- Pick base branch from a dropdown of existing branches ([`f4e248f`](https://github.com/BottlePumpkin/Parallel/commit/f4e248f477f293488757f13606d86db8cb47dab5))
- **views:** + menu on repo header — New Worktree or Import Existing ([`4becc5c`](https://github.com/BottlePumpkin/Parallel/commit/4becc5ce250c723868497b05941901028bc4ea31))
- **views:** + button on sidebar repo header opens NewWorktreeSheet with repo prefilled ([`b906f01`](https://github.com/BottlePumpkin/Parallel/commit/b906f0180eb9d98924d1da7b443a44c821020961))
- **views:** Sidebar right-click → Delete + Cmd+⌫ shortcut + activate menu bar ([`1421bbd`](https://github.com/BottlePumpkin/Parallel/commit/1421bbdff98efddaee8730b88c788fa90ccbbbaf))
- **util:** AppLogger via os.Logger + service error logging ([`54250ca`](https://github.com/BottlePumpkin/Parallel/commit/54250cad6e5f70538f2ff65623f562eaf61f62ee))
- **views:** Keyboard shortcuts + delete worktree flow with confirmation ([`a539cf8`](https://github.com/BottlePumpkin/Parallel/commit/a539cf8f1cdd719ad4a4c76395f24b1efe287928))
- **views:** Dead session placeholder with Restart button ([`20401c6`](https://github.com/BottlePumpkin/Parallel/commit/20401c6e2773d88c40b4d3dfcb277b0e73b0c786))
- **views:** Worktree row badges (state dot, change count, error) ([`25d4ae3`](https://github.com/BottlePumpkin/Parallel/commit/25d4ae3054e82a4a6640839365e9400ebdb6be1d))
- **services:** StatusWatcher 5s polling with concurrency cap 4 ([`64459a8`](https://github.com/BottlePumpkin/Parallel/commit/64459a8d2e254a784ab8b33943e9e780bb5a709f))
- **views:** Terminal font fallback chain — Nerd Fonts → D2Coding → Menlo ([`e42de6e`](https://github.com/BottlePumpkin/Parallel/commit/e42de6e1a881a0d9e657b4a62c0fd94d2f3ab977))
- **views:** NewWorktreeSheet with path preview + setup prefill ([`d6eb30d`](https://github.com/BottlePumpkin/Parallel/commit/d6eb30d6ede35ee16a27506f73b96a76fb279ee0))
- **views:** AddRepoSheet with worktree discovery and import ([`96ac114`](https://github.com/BottlePumpkin/Parallel/commit/96ac11444b45a4a74692711fe4b956ae771e307a))
- **views:** TerminalPaneView hosting SwiftTerm via SessionManager ([`ccc2850`](https://github.com/BottlePumpkin/Parallel/commit/ccc285097e55969cc8afe7530c02b61379364cc0))
- **views:** SidebarView with repo grouping and worktree rows ([`22de02f`](https://github.com/BottlePumpkin/Parallel/commit/22de02fd83a357105160fa3266c4038a4e7e2430))
- **views:** NavigationSplitView skeleton with environment injection ([`a6e9aa6`](https://github.com/BottlePumpkin/Parallel/commit/a6e9aa68595237c69a78911d5e9d9b7902cae92e))
- **services:** SessionManager bridging PTY and SwiftTerm ([`3b267da`](https://github.com/BottlePumpkin/Parallel/commit/3b267da297a3fcbc5d5281d637348a8ea966dd3b))
- **services:** PTY (posix forkpty) wrapper with smoke test ([`a6602b5`](https://github.com/BottlePumpkin/Parallel/commit/a6602b5021fd87394d7df3ef2dc426c944e09aee))
- **services:** WorktreeService.remove + status ([`21ce8ce`](https://github.com/BottlePumpkin/Parallel/commit/21ce8ce84daa4c06039b139c8f8cba1d84e8be96))
- **services:** WorktreeService.add ([`87eda5c`](https://github.com/BottlePumpkin/Parallel/commit/87eda5c70cb593d8ff486bb6405133b577b91d22))
- **services:** WorktreeService.list with porcelain parser ([`af0312d`](https://github.com/BottlePumpkin/Parallel/commit/af0312d671765d50be4b07ca1426c9e45b2a0f36))
- **services:** GitCLI Process wrapper with stdout/stderr capture ([`810b2df`](https://github.com/BottlePumpkin/Parallel/commit/810b2df3a115d16c354047f5b2e83a8e1d2e5b64))
- **persistence:** WorkspaceStore with corruption quarantine ([`d542aed`](https://github.com/BottlePumpkin/Parallel/commit/d542aedc156c4729e8cb144633d3a96e2cbcbe86))
- **models:** Repo/Worktree/WorktreeStatus/Session ([`a5a6050`](https://github.com/BottlePumpkin/Parallel/commit/a5a6050a9c65083f6bd3e2e2f39b0c2202eaa02d))
- **util:** PathSanitizer with TDD ([`5216349`](https://github.com/BottlePumpkin/Parallel/commit/5216349e05755b0d27697a9abc67cce36ab902f2))


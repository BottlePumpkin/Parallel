import SwiftUI

private struct SheetRepoId: Identifiable { let id: UUID }

/// Trigger object for the NewWorktreeSheet. A fresh `id` per invocation
/// forces `.sheet(item:)` to rebuild the view, so `initialRepoId` is
/// always read at click time — not from a stale @State capture.
private struct NewWorktreeTrigger: Identifiable {
    let id = UUID()
    let initialRepoId: UUID?
}

struct ContentView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(SessionManager.self) private var sessionManager
    @Environment(CaffeinateManager.self) private var caffeinate
    @Environment(UpdateChecker.self) private var updateChecker
    @State private var selectedWorktreeId: UUID?
    @State private var showAddRepo = false
    @State private var newWorktreeTrigger: NewWorktreeTrigger?
    @State private var importWorktreesRepoId: UUID?
    @State private var pendingDeleteId: UUID?
    @State private var renameTargetId: UUID?
    @State private var renameText: String = ""
    @State private var deleteErrorMessage: String?
    @State private var pendingRemoveRepoId: UUID?
    @State private var manualCheckSheet: ManualCheckState?
    @State private var showReportIssueSheet = false

    enum ManualCheckState: Identifiable {
        case checking
        case upToDate(SemanticVersion)
        case failed(String)
        var id: String {
            switch self {
            case .checking: return "checking"
            case .upToDate(let v): return "upToDate-\(v.description)"
            case .failed(let m): return "failed-\(m)"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedWorktreeId, actions: sidebarActions)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            TerminalPaneView(worktreeId: selectedWorktreeId)
        }
        .toolbar { toolbarContent }
        .modifier(SheetsModifier(
            showAddRepo: $showAddRepo,
            newWorktreeTrigger: $newWorktreeTrigger,
            importWorktreesRepoId: $importWorktreesRepoId,
            pendingDeleteId: $pendingDeleteId,
            store: store,
            onConfirmDelete: confirmDelete,
            manualCheckSheet: $manualCheckSheet,
            showReportIssueSheet: $showReportIssueSheet,
            updateChecker: updateChecker
        ))
        .modifier(AlertsModifier(
            renameTargetId: $renameTargetId,
            renameText: $renameText,
            deleteErrorMessage: $deleteErrorMessage,
            pendingRemoveRepoId: $pendingRemoveRepoId,
            sessionManager: sessionManager,
            onConfirmRemoveRepo: confirmRemoveRepo,
            store: store,
            onConfirmRename: confirmRename
        ))
        .focusedValue(\.contentActions, focusedActions)
        .task(id: "update-startup-check") {
            await updateChecker.checkIfStale()
        }
        .onAppear {
            if selectedWorktreeId == nil {
                selectedWorktreeId = store.lastSelectedWorktreeId
            }
        }
        .onChange(of: selectedWorktreeId) { _, new in
            store.lastSelectedWorktreeId = new
            try? store.save()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button { showAddRepo = true } label: {
                Label("Add Repository", systemImage: "folder.badge.plus")
            }
        }
        ToolbarItem {
            Button {
                newWorktreeTrigger = NewWorktreeTrigger(initialRepoId: nil)
            } label: {
                Label("New Worktree", systemImage: "plus.square.on.square")
            }
            .disabled(store.repos.isEmpty)
        }
        ToolbarItem {
            Button {
                caffeinate.toggle()
            } label: {
                Label(
                    caffeinate.isOn ? "Keep awake (ON)" : "Keep awake",
                    systemImage: caffeinate.isOn ? "cup.and.saucer.fill" : "cup.and.saucer"
                )
            }
            .foregroundStyle(caffeinate.isOn ? Color.accentColor : .primary)
            .help(caffeinate.isOn
                  ? "Sleep prevention ON — click to disable"
                  : "Prevent the display and system from sleeping while you work")
        }
    }

    private var sidebarActions: SidebarActions {
        SidebarActions(
            delete: { id in pendingDeleteId = id },
            untrack: { id in
                sessionManager.terminate(worktreeId: id)
                store.removeWorktree(id: id)
            },
            addWorktree: { repoId in
                newWorktreeTrigger = NewWorktreeTrigger(initialRepoId: repoId)
            },
            importWorktrees: { repoId in
                importWorktreesRepoId = repoId
            },
            rename: { id in
                renameText = store.worktree(id: id)?.displayName ?? ""
                renameTargetId = id
            },
            removeRepo: { id in pendingRemoveRepoId = id }
        )
    }

    private var focusedActions: ContentActions {
        ContentActions(
            newWorktree: { newWorktreeTrigger = NewWorktreeTrigger(initialRepoId: nil) },
            addRepo:     { showAddRepo = true },
            selectWorktreeIndex: { idx in
                let ordered = store.orderedWorktrees
                if idx < ordered.count {
                    selectedWorktreeId = ordered[idx].id
                }
            },
            selectTabIndex: { idx in
                if let id = selectedWorktreeId {
                    sessionManager.activateTab(in: id, at: idx)
                }
            },
            nextTab: {
                if let id = selectedWorktreeId {
                    sessionManager.activateAdjacentTab(in: id, forward: true)
                }
            },
            previousTab: {
                if let id = selectedWorktreeId {
                    sessionManager.activateAdjacentTab(in: id, forward: false)
                }
            },
            newTab: {
                if let id = selectedWorktreeId, let wt = store.worktree(id: id) {
                    _ = sessionManager.startSession(for: wt, setupCommands: wt.setupCommands)
                }
            },
            clearTerminal: {
                if let id = selectedWorktreeId {
                    sessionManager.clearActiveTerminal(in: id)
                }
            },
            findInTerminal: {
                if let id = selectedWorktreeId {
                    sessionManager.showFind(in: id)
                }
            },
            closeCurrentSession: {
                if let id = selectedWorktreeId {
                    sessionManager.terminate(worktreeId: id)
                }
            },
            deleteCurrentWorktree: {
                pendingDeleteId = selectedWorktreeId
            },
            checkForUpdates: { Task { await runManualCheck() } },
            reportIssue: { showReportIssueSheet = true }
        )
    }

    private func confirmRename() {
        defer { renameTargetId = nil }
        guard let id = renameTargetId else { return }
        store.rename(worktreeId: id, to: renameText)
    }

    private func confirmRemoveRepo() {
        defer { pendingRemoveRepoId = nil }
        guard let id = pendingRemoveRepoId else { return }
        // Terminate every PTY belonging to a worktree of this repo, then
        // remove the repo + its worktrees from the store. No git actions.
        for wt in store.worktrees where wt.repoId == id {
            sessionManager.terminate(worktreeId: wt.id)
        }
        store.removeRepo(id: id)
    }

    private func confirmDelete(alsoDeleteBranch: Bool) {
        defer { pendingDeleteId = nil }
        guard let id = pendingDeleteId, let wt = store.worktree(id: id),
              let repo = store.repos.first(where: { $0.id == wt.repoId }) else {
            return
        }
        sessionManager.terminate(worktreeId: id)
        let svc = WorktreeService()
        do {
            try svc.remove(repoRoot: repo.root, path: wt.path, force: false)
        } catch {
            do {
                try svc.remove(repoRoot: repo.root, path: wt.path, force: true)
            } catch let forceError {
                // Both attempts failed. Surface to the user and KEEP the
                // worktree entry — silently dropping it would lose the user's
                // reference to a worktree directory that's still on disk.
                AppLogger.worktree.error("delete failed: \(forceError.localizedDescription, privacy: .public)")
                deleteErrorMessage = "Couldn't remove worktree: \(forceError.localizedDescription)"
                return
            }
        }
        if alsoDeleteBranch {
            do {
                try svc.deleteBranch(repoRoot: repo.root, branch: wt.branch)
            } catch {
                AppLogger.worktree.error("branch delete failed: \(error.localizedDescription, privacy: .public)")
                // Worktree is already gone; partial success is acceptable here.
            }
        }
        store.removeWorktree(id: id)
    }

    private func runManualCheck() async {
        manualCheckSheet = .checking
        await updateChecker.check(force: true)
        switch updateChecker.lastCheckResult {
        case .available:
            manualCheckSheet = nil
            // updateChecker.updateAvailable is set; the sheet binding picks it up.
        case .upToDate(let current):
            manualCheckSheet = .upToDate(current)
        case .failed(let error):
            manualCheckSheet = .failed(error.localizedDescription)
        case .none:
            manualCheckSheet = .failed("No result.")
        }
    }
}

// MARK: - Modifiers (extracted to keep ContentView.body type-checkable)

private struct SheetsModifier: ViewModifier {
    @Binding var showAddRepo: Bool
    @Binding var newWorktreeTrigger: NewWorktreeTrigger?
    @Binding var importWorktreesRepoId: UUID?
    @Binding var pendingDeleteId: UUID?
    let store: WorkspaceStore
    let onConfirmDelete: (Bool) -> Void
    @Binding var manualCheckSheet: ContentView.ManualCheckState?
    @Binding var showReportIssueSheet: Bool
    let updateChecker: UpdateChecker

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showAddRepo) { AddRepoSheet() }
            .sheet(item: $newWorktreeTrigger) { trigger in
                NewWorktreeSheet(initialRepoId: trigger.initialRepoId)
            }
            .sheet(item: Binding(
                get: { importWorktreesRepoId.map(SheetRepoId.init) },
                set: { importWorktreesRepoId = $0?.id }
            )) { wrapper in
                ImportWorktreesSheet(repoId: wrapper.id)
            }
            .sheet(item: Binding(
                get: { pendingDeleteId.flatMap { store.worktree(id: $0) } },
                set: { if $0 == nil { pendingDeleteId = nil } }
            )) { wt in
                DeleteWorktreeSheet(worktree: wt, onConfirm: onConfirmDelete)
            }
            .sheet(item: Binding(
                get: { updateChecker.updateAvailable.map(UpdateInfoBox.init) },
                set: { _ in updateChecker.updateAvailable = nil }
            )) { box in
                UpdateAvailableSheet(info: box.info)
            }
            .sheet(item: $manualCheckSheet) { state in
                ManualCheckSheet(state: state)
            }
            .sheet(isPresented: $showReportIssueSheet) {
                ReportIssueSheet()
            }
    }
}

private struct AlertsModifier: ViewModifier {
    @Binding var renameTargetId: UUID?
    @Binding var renameText: String
    @Binding var deleteErrorMessage: String?
    @Binding var pendingRemoveRepoId: UUID?
    let sessionManager: SessionManager
    let onConfirmRemoveRepo: () -> Void
    let store: WorkspaceStore
    let onConfirmRename: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Rename worktree", isPresented: Binding(
                get: { renameTargetId != nil },
                set: { if !$0 { renameTargetId = nil } }
            )) {
                TextField("Display name", text: $renameText)
                Button("Save") { onConfirmRename() }
                    .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {}
            } message: {
                if let id = renameTargetId, let wt = store.worktree(id: id) {
                    Text("Branch: \(wt.branch)")
                }
            }
            .alert("Delete failed", isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(deleteErrorMessage ?? "")
            }
            .alert("Remove repository?", isPresented: Binding(
                get: { pendingRemoveRepoId != nil },
                set: { if !$0 { pendingRemoveRepoId = nil } }
            )) {
                Button("Remove", role: .destructive) { onConfirmRemoveRepo() }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let id = pendingRemoveRepoId, let repo = store.repos.first(where: { $0.id == id }) {
                    Text("’\(repo.displayName)’ and its tracked worktrees will be removed from Parallel. Nothing on disk or in git is changed.")
                }
            }
    }
}

private struct UpdateInfoBox: Identifiable {
    let info: UpdateInfo
    var id: String { info.latestTag }
}

private struct ManualCheckSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ContentView.ManualCheckState

    var body: some View {
        VStack(spacing: 14) {
            switch state {
            case .checking:
                ProgressView("Checking GitHub…")
            case .upToDate(let v):
                Text("You’re on the latest version (\(v.description)).")
            case .failed(let msg):
                Text("Couldn’t check for updates.").font(.headline)
                Text(msg).font(.caption).foregroundStyle(.secondary)
            }
            if !isChecking {
                HStack {
                    Spacer()
                    Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var isChecking: Bool {
        if case .checking = state { return true }
        return false
    }
}

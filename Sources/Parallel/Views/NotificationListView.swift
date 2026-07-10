import SwiftUI

/// Popover contents for the toolbar bell (issue #12). Newest first; a row tap
/// asks the store to navigate; "Clear all" empties history.
struct NotificationListView: View {
    @Environment(NotificationStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notifications").font(.headline)
                Spacer()
                Button("Clear all") { store.clearAll() }
                    .disabled(store.items.isEmpty)
            }
            .padding(10)
            Divider()
            if store.items.isEmpty {
                Text("No notifications")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.items) { note in
                            Button {
                                store.navigationTarget = NavigationTarget(
                                    worktreeId: note.worktreeId, sessionId: note.sessionId)
                            } label: {
                                row(note)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("notificationRow")
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 320)
    }

    private func row(_ note: AppNotification) -> some View {
        HStack(spacing: 8) {
            Image(systemName: note.kind == .needsAttention ? "bell.fill" : "moon.zzz.fill")
                .foregroundStyle(note.isRead ? Color.secondary : Color.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.worktreeName).font(.body)
                Text("\(note.tabLabel) · \(note.branch)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

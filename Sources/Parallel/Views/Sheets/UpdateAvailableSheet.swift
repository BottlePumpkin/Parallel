import SwiftUI
import AppKit

struct UpdateAvailableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UpdateChecker.self) private var checker
    @Environment(Updater.self) private var updater
    let info: UpdateInfo

    private let installCommand = "curl -fsSL https://raw.githubusercontent.com/BottlePumpkin/Parallel/master/scripts/install.sh | bash"

    @State private var copied = false

    private var target: UpdateInstallTarget {
        UpdateInstallTarget.resolve(bundleURL: Bundle.main.bundleURL)
    }

    private var canUpdateInApp: Bool {
        if info.assetURL == nil { return false }
        if case .replaceable = target { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Update available").font(.title2).bold()
            Text("Parallel \(info.latestVersion.description) is out — you're on \(AppVersion.current.description).")
                .font(.subheadline).foregroundStyle(.secondary)

            Divider()

            Text("Release notes").font(.headline)
            ScrollView {
                Text(info.releaseNotes.isEmpty ? "(no notes)" : info.releaseNotes)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 180, maxHeight: 280)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))

            progressOrFallback

            HStack {
                Button("Skip This Version") {
                    checker.skip(info.latestVersion)
                    dismiss()
                }
                .disabled(isBusy)
                Spacer()
                Button("Later") { dismiss() }
                    .disabled(isBusy)
                if canUpdateInApp {
                    Button("Update Now") {
                        if case .replaceable(let url) = target {
                            updater.update(from: info, target: url)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy)
                } else {
                    Button("Open Release Page") {
                        NSWorkspace.shared.open(info.releaseURL)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 540)
        .interactiveDismissDisabled(isBusy)
        .onDisappear {
            // Clear a lingering .failed so the sheet doesn't reopen on the next
            // check still showing a stale error. (Dismissal is blocked mid-update.)
            if case .failed = updater.phase { updater.cancel() }
        }
    }

    private var isBusy: Bool {
        switch updater.phase {
        case .idle, .failed: return false
        default: return true
        }
    }

    @ViewBuilder
    private var progressOrFallback: some View {
        switch updater.phase {
        case .downloading(let fraction):
            HStack {
                ProgressView(value: fraction).frame(maxWidth: .infinity)
                Button("Cancel") { updater.cancel() }
            }
        case .unpacking, .verifying, .installing, .relaunching:
            HStack { ProgressView(); Text(statusText).foregroundStyle(.secondary) }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message).font(.callout).foregroundStyle(.red)
                manualFallback
            }
        case .idle:
            if !canUpdateInApp {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fallbackReason).font(.callout).foregroundStyle(.secondary)
                    manualFallback
                }
            }
        }
    }

    private var statusText: String {
        switch updater.phase {
        case .unpacking: return "Unpacking…"
        case .verifying: return "Verifying…"
        case .installing: return "Installing…"
        case .relaunching: return "Relaunching…"
        default: return ""
        }
    }

    private var fallbackReason: String {
        if info.assetURL == nil { return "This release has no downloadable build — install manually:" }
        if case .unsupported(let reason) = target { return reason + " Install manually:" }
        return "Install manually:"
    }

    private var manualFallback: some View {
        HStack {
            Text(installCommand)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(installCommand, forType: .string)
                copied = true
            }
            Button("Open Release Page") { NSWorkspace.shared.open(info.releaseURL) }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled { copied = false }
        }
    }
}

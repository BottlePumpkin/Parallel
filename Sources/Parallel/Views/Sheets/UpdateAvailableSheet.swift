import SwiftUI
import AppKit

struct UpdateAvailableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UpdateChecker.self) private var checker
    let info: UpdateInfo

    private let installCommand = "curl -fsSL https://raw.githubusercontent.com/BottlePumpkin/Parallel/master/scripts/install.sh | bash"

    @State private var copied = false

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

            VStack(alignment: .leading, spacing: 4) {
                Text("Install command").font(.headline)
                HStack {
                    Text(installCommand)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(installCommand, forType: .string)
                        copied = true
                    }
                }
            }
            .task(id: copied) {
                guard copied else { return }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                if !Task.isCancelled {
                    copied = false
                }
            }

            HStack {
                Button("Skip This Version") {
                    checker.skip(info.latestVersion)
                    dismiss()
                }
                Spacer()
                Button("Later") { dismiss() }
                Button("Open Release Page") {
                    NSWorkspace.shared.open(info.releaseURL)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540)
    }
}

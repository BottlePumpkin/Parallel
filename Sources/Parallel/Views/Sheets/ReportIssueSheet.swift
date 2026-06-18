import SwiftUI

struct ReportIssueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText: String = ReportIssueSheet.bodyTemplate()
    @State private var errorMessage: String?

    static func bodyTemplate() -> String {
        """
        ## What happened?


        ## Steps to reproduce


        ---
        **Environment**
        \(AppVersion.environmentSignature)
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Report an issue").font(.title2).bold()
            Text("Submitting opens GitHub in your browser — you review and submit there. No data is sent from Parallel directly.")
                .font(.caption).foregroundStyle(.secondary)

            TextField("Title", text: $title)

            Text("Description").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $bodyText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Open in Browser") {
                    let ok = IssueReporter.openNewIssue(
                        title: title,
                        body: bodyText,
                        labels: ["user-report"]
                    )
                    if !ok {
                        errorMessage = "Couldn't open the browser — the URL has been copied to your clipboard."
                        return
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

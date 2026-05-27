import SwiftUI

struct SidebarView: View {
    @Binding var selection: UUID?

    var body: some View {
        List(selection: $selection) {
            Text("(empty — add a repository)")
                .foregroundStyle(.secondary)
        }
    }
}

import SwiftUI

/// Why the name sheet is shown: saving the planned loop as a new route, or renaming something.
enum NamePrompt: Identifiable {
    case save(suggested: String)
    case rename(current: String)
    case renameSaved(PlannedLoop)

    var id: String {
        switch self {
        case .save: "save"
        case .rename: "rename"
        case .renameSaved(let l): "rename-\(l.id)"
        }
    }

    var title: String {
        switch self {
        case .save: "Save route"
        case .rename, .renameSaved: "Rename route"
        }
    }

    var initialName: String {
        switch self {
        case .save(let s): s
        case .rename(let c): c
        case .renameSaved(let l): l.name
        }
    }

    var buttonTitle: String {
        if case .save = self { return "Save" }
        return "Rename"
    }
}

/// A small sheet with a single name field, used for saving and renaming routes.
struct NameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let prompt: NamePrompt
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Route name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .semibold))
                    .padding(14)
                    .background(Theme.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(commit)
                if case .save = prompt {
                    Text("The waypoints, route, elevation and routing settings are kept on this device.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(16)
            .background(Theme.panel)
            .navigationTitle(prompt.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(prompt.buttonTitle, action: commit).fontWeight(.semibold) }
            }
            .toolbarBackground(Theme.panel, for: .navigationBar)
        }
        .tint(Theme.accent)
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.hidden)
        .onAppear {
            name = prompt.initialName
            focused = true
        }
    }

    private func commit() {
        switch prompt {
        case .save: model.saveAsNew(named: name)
        case .rename: model.renameCurrent(to: name)
        case .renameSaved(let loop): model.rename(loop: loop, to: name)
        }
        dismiss()
    }
}

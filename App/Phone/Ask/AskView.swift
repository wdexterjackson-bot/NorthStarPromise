import NSPDesignSystem
import SwiftUI

/// docs/07 §4: "The scope selector is mandatory and always visible — the
/// query field is disabled until a scope is chosen." No retriever is wired
/// to any UI yet (`NSPIntelligence`'s mocks exist at the package level,
/// not connected here), so this screen enforces the scope-first rule
/// correctly while being honest that asking anything doesn't do anything
/// yet.
@MainActor
struct AskView: View {
    let environment: AppEnvironment

    private enum Scope: String, CaseIterable, Identifiable {
        case none = "Choose a scope"
        case thisWorkspace = "This workspace"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .none
    @State private var queryText = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: NSPSpacing.large) {
                VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                    Picker("Scope", selection: $scope) {
                        ForEach(Scope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        TextField("Ask about your meetings…", text: $queryText)
                            .textFieldStyle(.roundedBorder)
                            .disabled(scope == .none)
                        Button("Ask") {}
                            .buttonStyle(.borderedProminent)
                            .disabled(scope == .none || queryText.isEmpty)
                    }
                }
                .nspCard()

                Spacer()

                ContentUnavailableView(
                    "Ask isn't connected yet", systemImage: "bubble.left.and.text.bubble.right",
                    description: Text("Retrieval and answering aren't wired to this screen in this build."))

                Spacer()
            }
            .padding(NSPSpacing.large)
            .background(NSPColor.background)
            .navigationTitle("Ask")
        }
    }
}

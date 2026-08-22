import NSPDesignSystem
import SwiftUI

/// Step 1 — renames the self-`Person` (`AppEnvironment.bootstrap()`'s
/// placeholder "You") and the workspace. Saves on every field change
/// rather than waiting for "Continue," so navigating Back and forward
/// again never loses a half-typed answer.
struct WizardIdentityStep: View {
    let coordinator: GettingStartedCoordinator

    @State private var name = ""
    @State private var role = ""
    @State private var organization = ""
    @State private var workspaceName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            WizardPromptBubble(text: "What should I call you, and what's your role?")
            VStack(spacing: NSPSpacing.small) {
                TextField("Your name", text: $name).textFieldStyle(.roundedBorder)
                TextField("Role — e.g. Chief of Staff (optional)", text: $role).textFieldStyle(.roundedBorder)
                TextField("Organization — e.g. Acme Inc (optional)", text: $organization).textFieldStyle(.roundedBorder)
            }

            WizardPromptBubble(text: "What should I call this workspace — your name, your team, your company?")
            TextField("Workspace name", text: $workspaceName).textFieldStyle(.roundedBorder)
        }
        .task { await loadCurrentValues() }
        // Commits when the step is left (Back or Continue), not per
        // keystroke — the same "save at the natural pause point, not on
        // every character" shape a Settings toggle already uses, just
        // applied to text fields here since there's no toggle to hang the
        // save off of.
        .onDisappear { save() }
    }

    private func loadCurrentValues() async {
        let environment = coordinator.environment
        if let selfPersonID = environment.selfPersonID, let person = try? await environment.personRepository.find(selfPersonID) {
            name = person.name
            role = person.role ?? ""
            organization = person.organization ?? ""
        }
        if let workspaceID = environment.defaultPolicy?.workspaceID,
            let workspace = try? await environment.workspaceRepository.find(workspaceID)
        {
            workspaceName = workspace.name
        }
    }

    private func save() {
        Task {
            await coordinator.saveIdentity(name: name, role: role, organization: organization, workspaceName: workspaceName)
        }
    }
}

import SwiftUI

@main
struct NorthStarPhoneApp: App {
    @State private var environment: AppEnvironment?
    @State private var launchError: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let environment {
                    RootView(environment: environment)
                } else if let launchError {
                    ContentUnavailableView(
                        "Couldn't start", systemImage: "exclamationmark.triangle",
                        description: Text(launchError))
                } else {
                    ProgressView()
                }
            }
            .task {
                guard environment == nil else { return }
                do {
                    let newEnvironment = try AppEnvironment()
                    // `bootstrap()` (and, in DEBUG, fixture seeding) must
                    // finish before `RootView` mounts — every screen's
                    // `.task` runs exactly once per view identity, so a
                    // screen that raced ahead of `defaultPolicy`/
                    // `selfPersonID` existing would bail out early and
                    // never retry, permanently missing data that arrives a
                    // moment later.
                    try await newEnvironment.bootstrap()
                    #if DEBUG
                        await DebugFixtures.seedIfNeeded(environment: newEnvironment)
                    #endif
                    environment = newEnvironment
                    if let workspaceID = newEnvironment.defaultPolicy?.workspaceID {
                        Task { await newEnvironment.syncCoordinator.syncNow(workspaceID: workspaceID) }
                    }
                } catch {
                    launchError = "\(error)"
                }
            }
        }
        // Pulls whatever another device pushed while this one was in the
        // background — best-effort, same non-blocking shape as the
        // launch-time and post-Stop sync calls.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, let environment, let workspaceID = environment.defaultPolicy?.workspaceID else {
                return
            }
            Task { await environment.syncCoordinator.syncNow(workspaceID: workspaceID) }
        }
    }
}

import SwiftUI

@main
struct NorthStarPhoneApp: App {
    @State private var environment: AppEnvironment?
    @State private var launchError: String?

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
                } catch {
                    launchError = "\(error)"
                }
            }
        }
    }
}

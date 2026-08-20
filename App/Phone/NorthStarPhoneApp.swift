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
                    environment = newEnvironment
                    try await newEnvironment.bootstrap()
                    #if DEBUG
                        await DebugFixtures.seedIfNeeded(environment: newEnvironment)
                    #endif
                } catch {
                    launchError = "\(error)"
                }
            }
        }
    }
}

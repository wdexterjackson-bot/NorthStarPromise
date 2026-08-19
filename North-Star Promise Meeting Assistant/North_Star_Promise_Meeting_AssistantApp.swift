//
//  North_Star_Promise_Meeting_AssistantApp.swift
//  North-Star Promise Meeting Assistant
//
//  Created by Dexter Jackson on 8/19/26.
//

import SwiftUI
import SwiftData

@main
struct North_Star_Promise_Meeting_AssistantApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

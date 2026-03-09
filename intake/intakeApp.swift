// intakeApp.swift
// Application entry point.
// Initializes SwiftData persistence container.
// Handles splash screen transition and notification permission request.
import SwiftUI
import SwiftData

@main
struct intakeApp: App {
    @State private var showSplash = true

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([ScannedItem.self, HealthEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("SwiftData migration failed, wiping store: \(error)")
            let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
            for suffix in ["", "-shm", "-wal"] {
                let url = storeURL.deletingPathExtension().appendingPathExtension("store\(suffix)")
                try? FileManager.default.removeItem(at: url)
            }
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer even after wipe: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView {
                        withAnimation(.easeIn(duration: 0.3)) { showSplash = false }
                    }
                    .transition(.opacity)
                } else {
                    ContentView()
                        .transition(.opacity)
                        .onAppear {
                            NotificationManager.shared.requestPermission { _ in }
                        }
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}

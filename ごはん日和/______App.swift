//
//  ______App.swift
//  ごはん日和
//
//  Created by 木村風葉 on 2026/07/17.
//

import SwiftUI
import SwiftData

@main
struct ______App: App {
    @State private var errorCenter = AppErrorCenter()
    @State private var proAccess = ProAccessController()
    @State private var proPreferences = ProPreferences()
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            LocalUserProfile.self,
            Place.self,
            RestaurantRecord.self,
            RecordPhoto.self,
            RecordMenuItem.self,
            Tag.self,
            Collection.self,
            CollectionEntry.self,
            AppSettings.self,
        ])
        #if DEBUG
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        #else
        let isUITesting = false
        #endif
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppView()
                .environment(errorCenter)
                .environment(proAccess)
                .environment(proPreferences)
                .appErrorAlert(errorCenter)
                .task {
                    do {
                        try InitialReleasePrivacy.normalize(in: sharedModelContainer.mainContext)
                    } catch {
                        errorCenter.show(error, title: "プライバシー設定を更新できませんでした")
                    }
                }
                .task { await proAccess.prepare() }
                .task { await proAccess.observeTransactions() }
                #if DEBUG
                .task {
                    guard ProcessInfo.processInfo.arguments.contains("-seedReleasePreview") else { return }
                    try? ReleasePreviewSampleData.add(to: sharedModelContainer.mainContext)
                }
                #endif
        }
        .modelContainer(sharedModelContainer)
    }
}

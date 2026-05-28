//
//  DictationWithoutOpenMainAppApp.swift
//  DictationWithoutOpenMainApp
//
//  Created by Itsuki on 2026/05/26.
//

import SwiftUI
import AppIntents

@main
struct DictationWithoutOpenMainAppApp: App {

    private let activityManager: ActivityManager

    init() {
        let manager = ActivityManager()
        self.activityManager = manager
        ShortcutsProvider.updateAppShortcutParameters()
        AppDependencyManager.shared.add(dependency: manager)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(activityManager)
        }
    }
}

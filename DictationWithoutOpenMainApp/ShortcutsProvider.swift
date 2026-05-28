//
//  ShortcutsProvider.swift
//  DictationWithoutOpenMainApp
//
//  Created by Itsuki on 2026/05/26.
//

import AppIntents

struct ShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start dictation in  \(.applicationName)"
            ],
            shortTitle: "Record",
            systemImageName: "microphone"
        )
        AppShortcut(
            intent: StartRecordingForegroundIntent(),
            phrases: [
                "Start dictation in  \(.applicationName)"
            ],
            shortTitle: "Record(Foreground)",
            systemImageName: "microphone"
        )
        AppShortcut(
            intent: StopRecordingIntent(),
            phrases: [
                "Stop dictation in  \(.applicationName)"
            ],
            shortTitle: "Stop",
            systemImageName: "stop.fill"
        )
    }
}

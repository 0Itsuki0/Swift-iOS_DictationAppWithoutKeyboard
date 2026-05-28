//
//  BoostIntent.swift
//  BroadcastAPNDemo
//
//  Created by Itsuki on 2025/12/01.
//

import AppIntents

struct StopRecordingIntent: LiveActivityIntent {

    static let title: LocalizedStringResource = "Stop"
    @Dependency var activityManager: ActivityManager

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        let result = await activityManager.stopRecordingActivity()
        if let result {
            let string = String(result.characters)
            logInfo("result: \(string)")
            return .result(value: string)
        }
        return .result(value: nil)
    }
}

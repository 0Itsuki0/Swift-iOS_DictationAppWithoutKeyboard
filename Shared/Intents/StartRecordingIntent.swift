//
//  StartRecordingIntent.swift
//  DictationWithoutOpenMainApp
//
//  Created by Itsuki on 2026/05/27.
//

import AppIntents

// NOTE:
//
// (1) Need two separate intent here because
// - shortcuts cache the continueInForeground behavior
// ie: if it is first run with the needs of continueInForeground (activityManager.audioSessionActivated == false),
// the subsequent one will keep launch the container app even it is not necessary anymore
//
// (2) StartRecordingIntent perform return bool instead of OpensIntent to call StartRecordingForegroundIntent directly if activityManager.audioSessionActivated == false
// ie: .result(opensIntent: StartRecordingForegroundIntent())
// because
// - when building custom shortcut with provided shortcut,if we did it this way, it will always, again, try to open the main app
// Possible reason: caching the previous result
// (I don't think it is due to launching a new instance with a new activityManager because
// 1. the solution below works
// 2. audio session is indeed activated and we can start the mic (audio engine) perfectly fine

// App Intent to start recording from background
struct StartRecordingIntent: AudioRecordingIntent, LiveActivityIntent {

    static let title: LocalizedStringResource = "Record"
    static let supportedModes: IntentModes = [.background]

    @Dependency var activityManager: ActivityManager

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        if !activityManager.audioSessionActivated {
            return .result(value: false)
        }
        activityManager.startRecordingActivity()
        return .result(value: true)
    }
}

// App Intent to start recording from foreground. Required for activating audio session
struct StartRecordingForegroundIntent: AudioRecordingIntent, LiveActivityIntent
{
    static let title: LocalizedStringResource = "Record(Foreground)"
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    @Parameter
    var appBundleId: String?

    @Dependency var activityManager: ActivityManager

    // true: if app bundle id is not nil -> short cut open the app.
    // false: app bundle id  is nil or empty -> short cut open home
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        activityManager.startRecordingActivity()
        return .result(
            value: appBundleId != nil
                && appBundleId?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty == false
        )
    }
}

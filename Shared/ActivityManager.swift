//
//  ActivityManager.swift
//
//
//  Created by Itsuki on 2025/12/01.
//

import ActivityKit
import Speech
import SwiftUI

typealias DictationActivity = Activity<DictationAttributes>
typealias DictationContentState = DictationAttributes.ContentState
typealias DictationActivityContent = ActivityContent<DictationContentState>

extension DictationActivity {
    var dictationState: DictationState {
        return self.content.state.state
    }
}

@Observable
final class ActivityManager: @unchecked Sendable {

    private(set) var activeActivity: DictationActivity?

    @ObservationIgnored
    private var activityListUpdateTask: Task<Void, Error>?

    private let transcriber = AudioTranscriber()

    private(set) var transcription: AttributedString = AttributedString()

    private var simulatePaste: (() -> Void)?

    var audioSessionActivated: Bool {
        return self.transcriber.audioCapturer.audioSessionActivated
    }

    @ObservationIgnored
    private var singleActivityUpdateTask:
        (Task<Void, Error>, Task<Void, Error>)?

    init() {
        logInfo("ActivityManager init")
        self.loadActivity()
        self.observeActivityListUpdate()
    }

    deinit {
        self.activityListUpdateTask?.cancel()
        self.singleActivityUpdateTask?.0.cancel()
        self.singleActivityUpdateTask?.1.cancel()
    }

    private func loadActivity() {
        var all = DictationActivity.activities
        guard !all.isEmpty else {
            self.activeActivity = nil
            self.cancelObserveSingleActivityUpdateTask()
            return
        }
        let activeActivity = all.removeFirst()
        all.forEach({ activity in
            self.endActivity(activity, dismissalPolicy: .immediate)
        })

        if activeActivity.dictationState == .recording
            || activeActivity.dictationState == .finalizing
        {
            self.activeActivity = activeActivity
            self.observeActiveActivityUpdate()
        } else {
            self.activeActivity = nil
            self.cancelObserveSingleActivityUpdateTask()
        }

    }

    func startRecordingActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logError("ActivityAuthorizationInfo disabled")
            return
        }

        guard self.transcriber.isAvailable else {
            logError("transcriber not available")
            return
        }

        logInfo("startRecordingActivity")

        let attributes = DictationAttributes()
        self.transcription = AttributedString()
        self.simulatePaste = simulatePaste

        do {
            self.endCurrentActivity()
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(
                    state: .init(
                        state: .starting,
                        lastUpdated: Date(),
                        message: nil
                    ),
                    staleDate: nil
                ),
                pushType: nil
            )
            self.activeActivity = activity
            self.observeActiveActivityUpdate()

            self.transcriber.startRealTimeTranscription(
                onResult: { [weak self] result in
                    guard let self else {
                        return
                    }
                    logInfo(
                        "\(String(result.text.characters)): \(result.isFinal)"
                    )
                    if result.isFinal,
                        self.activeActivity?.dictationState == .recording
                            || self.activeActivity?.dictationState
                                == .finalizing
                    {
                        self.transcription.append(result.text)
                        logInfo("\(String(self.transcription.characters))")
                    }
                    if let activeActivity, activity.id == activeActivity.id {
                        // to update updateDate
                        self.updateActivity(
                            activeActivity,
                            state: .init(
                                state: .recording,
                                lastUpdated: Date(),
                                message: result.text
                            )
                        )
                    }
                },
                onError: { [weak self] error in
                    guard let self else {
                        return
                    }
                    logError(
                        "error in transcriber callback: \(error.localizedDescription)"
                    )
                    if let activeActivity {
                        // to update updateDate
                        self.updateActivity(
                            activeActivity,
                            state: .init(
                                state: .error,
                                lastUpdated: Date(),
                                message: AttributedString(
                                    error.localizedDescription
                                )
                            )
                        )
                    }
                },
                onStart: { [weak self] in
                    guard let self else {
                        return
                    }
                    logInfo("transcriber started")
                    if let activeActivity {
                        self.updateActivity(
                            activeActivity,
                            state: .init(
                                state: .recording,
                                lastUpdated: Date(),
                                message: nil
                            )
                        )
                    }
                }
            )

            logInfo("activity started")
        } catch (let error) {
            logError("Error in startActivity: \(error)")
        }
    }

    func stopRecordingActivity() async -> AttributedString? {
        guard let activeActivity else {
            return nil
        }
        do {
            self.updateActivity(
                activeActivity,
                state: .init(
                    state: .finalizing,
                    lastUpdated: Date(),
                    message: "Finalizing..."
                )
            )

            try await self.transcriber.finalizePreviousTranscribing()
            // a little wait to see if there is more transcript coming in

            try? await Task.sleep(for: .milliseconds(10))
            // ...saving pasteboard failed with error: Error Domain=PBErrorDomain Code=11 "The pasteboard name com.apple.UIKit.pboard.general is not valid." UserInfo={NSLocalizedDescription=The pasteboard name com.apple.UIKit.pboard.general is not valid.}
            // Due to app in background (regardless of background processing mode is enabled or not)
            // UIPasteboard.general.string = "\(self.transcription)"

            self.updateActivity(
                activeActivity,
                state: .init(
                    state: .idle,
                    lastUpdated: Date(),
                    message: "Finished: " + self.transcription
                )
            )
            let transcription = self.transcription
            self.transcription = .init()
            return transcription
        } catch (let error) {
            logError(
                "Error stopping transcription: \(error.localizedDescription)"
            )
            return nil
        }
    }

    private func updateActivity(
        _ activity: DictationActivity,
        state: DictationContentState
    ) {
        guard
            activity.activityState != .ended
                || activity.activityState != .dismissed
        else {
            return
        }

        Task {
            await activity.update(
                DictationActivityContent(
                    state: state,
                    staleDate: nil
                ),
                alertConfiguration: nil
            )
        }
    }

    func endCurrentActivity() {
        DictationActivity.activities.forEach {
            self.endActivity($0, dismissalPolicy: .immediate)
        }
        self.cancelObserveSingleActivityUpdateTask()
        self.activeActivity = nil
    }

    func endActivity(
        _ activity: DictationActivity,
        dismissalPolicy: ActivityUIDismissalPolicy
    ) {
        Task {
            // Always include an updated Activity.ContentState to ensure the Live Activity shows the latest and final content update after it ends
            await activity.end(
                activity.content,
                dismissalPolicy: dismissalPolicy
            )
        }
    }

    private func setActivity(_ activity: DictationActivity) {
        if self.activeActivity == nil, activity.activityState != .dismissed {
            self.activeActivity = activity
            return
        }
        guard activity.id == self.activeActivity?.id else {
            return
        }
        self.activeActivity = activity
    }

    private func observeActivityListUpdate() {
        self.activityListUpdateTask?.cancel()
        self.activityListUpdateTask = nil

        self.activityListUpdateTask = Task { [weak self] in
            for await activity in DictationActivity.activityUpdates {
                if self?.activeActivity == nil,
                    activity.activityState != .dismissed
                {
                    self?.activeActivity = activity
                    self?.observeActiveActivityUpdate()
                    return
                }

                guard self?.activeActivity?.id == activity.id else {
                    continue
                }
                if activity.activityState != .dismissed {
                    self?.activeActivity = activity
                } else {
                    self?.activeActivity = nil
                    self?.cancelObserveSingleActivityUpdateTask()
                }
            }
        }
    }

    private func cancelObserveSingleActivityUpdateTask() {
        self.singleActivityUpdateTask?.0.cancel()
        self.singleActivityUpdateTask?.1.cancel()
        self.singleActivityUpdateTask = nil
    }

    private func observeActiveActivityUpdate() {
        self.cancelObserveSingleActivityUpdateTask()

        guard let activity = activeActivity else {
            return
        }

        if activity.activityState == .dismissed {
            return
        }

        let stateTask: Task<Void, Error> = Task { [weak self, activity] in
            for await activityState in activity.activityStateUpdates {
                logInfo("activityStateUpdates: \(activityState)")
                self?.setActivity(activity)
            }
        }

        let contentTask: Task<Void, Error> = Task { [weak self, activity] in
            for await contentState in activity.contentUpdates {
                logInfo("contentState update: \(contentState)")
                self?.setActivity(activity)
            }
        }

        self.singleActivityUpdateTask = (stateTask, contentTask)
    }
}

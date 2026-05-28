//
//  AudioCapturer.swift
//  DictationWithoutOpenMainApp
//
//  Created by Itsuki on 2026/05/26.
//

import AVFAudio

nonisolated class AudioCapturer: @unchecked Sendable {
    private let audioQueue = DispatchQueue(
        label: "AudioCapturer",
        qos: .userInitiated
    )
    
    private(set) var audioSessionActivated = false

    private var audioEngine = AVAudioEngine()

    private let bufferSize: UInt32 = 1024

    private let audioSession: AVAudioSession = AVAudioSession.sharedInstance()
    
    init() {
        self.startObservingInterruption()
        self.startObservingRouteChange()
    }

    func startCapturing(
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
    ) throws {

        try audioQueue.sync {

            if Self.getRecordingPermission() != .granted {
                throw TranscriptionError.micPermissionDenied
            }

            try audioSession.setCategory(
                .record,
                mode: .default,
                options: []
            )

            if !self.audioSessionActivated {
                try self.audioSession.setActive(true, options: [])
                self.audioEngine = AVAudioEngine()
                self.audioSessionActivated = true
            }

            let inputNode = audioEngine.inputNode

            if !inputNode.isEnabled {
                // if input is not enabled, it usually mean the session get's deactivated
                self.audioSessionActivated = false
                throw TranscriptionError.micInputNotAvailable
            }

            let format = inputNode.outputFormat(forBus: 0)

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(
                onBus: 0,
                bufferSize: self.bufferSize,
                format: format
            ) { (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
                onBuffer(buffer)
            }
            try audioEngine.start()
        }
    }


    // MARK: - Stop Capture
    func stopCapturing(fullTearDown: Bool = false) {
        audioQueue.sync {
            self._stopCapturing(fullTearDown: fullTearDown)
        }
    }

    private func _stopCapturing(fullTearDown: Bool) {
        self.audioEngine.inputNode.removeTap(onBus: 0)
        self.audioEngine.stop()
        if fullTearDown {
            self.audioEngine.reset()
            try? self.audioSession.setActive(false)
            self.audioSessionActivated = false
        }
    }
}

// MARK: - Static implementations
nonisolated extension AudioCapturer {
    public static func getRecordingPermission()
        -> AVAudioApplication.recordPermission
    {
        return AVAudioApplication.shared.recordPermission
    }

    @discardableResult
    public static func requestRecordPermission() async -> Bool {
        // not throwing here because this is intended to be called to prompt for permission instead of showing error
        return await AVAudioApplication.requestRecordPermission()
    }
}


// MARK: - Interruption Monitoring
nonisolated extension AudioCapturer {

    private func startObservingInterruption() {
        Task {
            for await _ in NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance()
            ) {
                self.stopCapturing(fullTearDown: true)
            }
        }
    }

    private func startObservingRouteChange() {
        Task {
            for await notification in NotificationCenter.default.notifications(
                named: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance()
            ) {

                guard let userInfo = notification.userInfo,
                    let reasonValue = userInfo[
                        AVAudioSessionRouteChangeReasonKey
                    ] as? UInt,
                    let reason = AVAudioSession.RouteChangeReason(
                        rawValue: reasonValue
                    )
                else {
                    return
                }
                guard
                    reason == .oldDeviceUnavailable
                        || reason == .noSuitableRouteForCategory
                        || reason == .routeConfigurationChange
                        || reason == .wakeFromSleep || reason == .unknown
                else {
                    return
                }
                self.stopCapturing(fullTearDown: true)
            }
        }
    }
}

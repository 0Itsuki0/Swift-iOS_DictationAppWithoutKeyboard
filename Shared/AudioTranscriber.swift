//
//  AudioTranscriber.swift
//  DictationWithoutOpenMainApp
//
//  Created by Itsuki on 2026/05/19.
//

@preconcurrency import Speech
import SwiftUI

enum TranscriptionError: LocalizedError {
    case micPermissionDenied
    case micInputNotAvailable
    case transcriberNotAvailable

    var errorDescription: String? {
        switch self {
        case .micInputNotAvailable:
            "Microphone input is not available."
        case .micPermissionDenied:
            "Microphone permission is denied."
        case .transcriberNotAvailable:
            "Transcriber is not available on the given device."
        }
    }
}

nonisolated extension Error {
    var isCancellationError: Bool {
        return self is CancellationError
    }
}
nonisolated extension Locale {
    static let enUS = Locale(identifier: "en-US")
}

// MARK: Main Implementation
// https://developer.apple.com/documentation/speech/speechtranscriber
@Observable
nonisolated class AudioTranscriber {

    private(set) var isAvailable: Bool = false
    private(set) var initialized: Bool = false

    let audioCapturer: AudioCapturer

    private var analyzer: SpeechAnalyzer?

    private var transcriber: SpeechTranscriber?

    // for audio engine to use when capturing input
    private var bestAvailableAudioFormat: AVAudioFormat? = nil

    // for real time transcribing
    nonisolated
        private var inputStream: AsyncStream<AnalyzerInput>
    nonisolated
        private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation

    // https://developer.apple.com/documentation/speech/speechtranscriber/preset
    private let preset: SpeechTranscriber.Preset =
        .timeIndexedProgressiveTranscription

    private var locale: Locale = .enUS

    private var audioConverter: AVAudioConverter?

    private var resultTask: Task<Void, Error>?

    private var isTranscribing = false

    private var speechConverter: AVAudioConverter?

    private var pendingBuffers: [AVAudioPCMBuffer] = [] {
        didSet {
            self.streamBufferIfNeeded()
        }
    }

    private var isYieldingBuffer = false
    private var converterSetupFailed = false

    private var onResult: ((SpeechTranscriber.Result) -> Void)?
    private var onError: ((Error) -> Void)?

    init() {
        defer {
            logInfo("transcriber init finished")
            initialized = true
        }
        self.isAvailable =
            AVAudioSession.sharedInstance().isInputAvailable
            && SpeechTranscriber.isAvailable

        (self.inputStream, self.inputContinuation) = AsyncStream<AnalyzerInput>
            .makeStream()

        self.audioCapturer = AudioCapturer()

        if !self.isAvailable {
            logError("transcriber not available")
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            let userPreference = Locale.preferredLocales.first ?? .enUS
            if let locale = await SpeechTranscriber.supportedLocale(
                equivalentTo: userPreference
            ) {
                self.locale = locale
            } else {
                logError("locale \(userPreference) not supported")
                return
            }
            let transcriber = SpeechTranscriber(
                locale: locale,
                preset: self.preset
            )
            self.transcriber = transcriber
            self.setupResultTask(transcriber: transcriber)

            // To delay or prevent unloading an analyzer’s resources by caching them for later use by a different analyzer instance
            // we can select a SpeechAnalyzer.Options.ModelRetention option and create the analyzer with an appropriate SpeechAnalyzer.Options object.
            // we can also add/remove module after analyzer creation using analyzer.setModules
            let analyzer = SpeechAnalyzer(
                modules: [transcriber],
                options: .init(
                    priority: .userInitiated,
                    modelRetention: .processLifetime
                )
            )
            self.analyzer = analyzer

            do {
                try await AssetInventory.reserve(locale: locale)
                self.bestAvailableAudioFormat =
                    await SpeechAnalyzer.bestAvailableAudioFormat(
                        compatibleWith: [
                            transcriber
                        ])

                try await analyzer.prepareToAnalyze(
                    in: self.bestAvailableAudioFormat,
                    withProgressReadyHandler: nil
                )

                let installed = (await SpeechTranscriber.installedLocales)
                    .contains(
                        locale
                    )

                if !installed {
                    if let installationRequest =
                        try await AssetInventory.assetInstallationRequest(
                            supporting: [
                                transcriber
                            ])
                    {
                        try await installationRequest.downloadAndInstall()
                    }
                }

                // set up finished after starting transcribing
                if self.isTranscribing {
                    logInfo("Start transcribing in init")
                    try await analyzer.start(inputSequence: inputStream)
                    self.streamBufferIfNeeded()
                }
            } catch (let error) {
                logError(
                    "Error setting up transcriber: \(error.localizedDescription)"
                )
            }
        }

    }

    deinit {
        self.resultTask?.cancel()
        self.audioCapturer.stopCapturing(fullTearDown: true)
        Task { [weak self] in
            await self?.finishAnalysisSession()
        }
    }

    // At the return of the finish(after:) method or any other ones that finish the analysis session,
    // the modules’ (SpeechTranscriber, and etc.) result streams will have ended and the modules will not accept further input from the input sequence.
    // The analyzer will not be able to resume analysis with a different input sequence and will not accept module changes; most methods will do nothing.
    private func finishAnalysisSession() async {
        self.inputContinuation.finish()
        // To end an analysis session, we must use one of the analyzer’s finish methods or parameters, or deallocate the analyzer.
        await self.analyzer?.cancelAndFinishNow()
    }

    // for real time transcription
    func startRealTimeTranscription(
        onResult: @escaping (SpeechTranscriber.Result) -> Void,
        onError: @escaping (Error) -> Void,
        onStart: @escaping () -> Void,
        retry: Int = 0
    ) {
        self.onResult = onResult
        self.onError = onError

        self.inputContinuation.finish()

        Task.detached(
            priority: .userInitiated,
            operation: { [weak self] in
                guard let self else {
                    return
                }
                do {
                    if let analyzer, self.initialized {
                        // a new inputStream is required after finishing the previous one
                        let (inputStream, inputContinuation) = AsyncStream<
                            AnalyzerInput
                        >
                        .makeStream()
                        self.inputStream = inputStream
                        self.inputContinuation = inputContinuation
                        try await analyzer.finalize(through: nil)
                        try await analyzer.start(inputSequence: inputStream)
                        logInfo("Start analyzer in function")
                    }
                    try self.audioCapturer
                        .startCapturing(
                            onBuffer: { buffer in
                                self.pendingBuffers.append(buffer)
                            }
                        )
                    logInfo("audioCapturer started")
                    self.isTranscribing = true
                    onStart()
                } catch (let error) {
                    // max 3 times
                    if retry > 3 {
                        onError(error)
                    } else {
                        logError(
                            "Error in startRealTimeTranscription: \(error.localizedDescription). Retrying..."
                        )
                        try? await Task.sleep(
                            for: .milliseconds(50 * pow(2, Double(retry)))
                        )
                        // for some reason, following error will occur some times on first start on the audio engine.
                        // - The operation couldn’t be completed. (com.apple.coreaudio.avfaudio error 2003329396)
                        // and if we try to call engine.start() again, everything will work fine.
                        // At the point of this error, session is already activated
                        self.startRealTimeTranscription(
                            onResult: onResult,
                            onError: onError,
                            onStart: onStart,
                            retry: retry + 1
                        )
                    }
                }
            }
        )
    }

    private func setupResultTask(
        transcriber: SpeechTranscriber
    ) {
        self.resultTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else {
                        return
                    }
                    onResult?(result)
                }
            } catch (let error) {
                if error.isCancellationError {
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                onError?(error)
                try? await self.finalizePreviousTranscribing()
            }
        }
    }

    private func streamBufferIfNeeded() {
        guard !pendingBuffers.isEmpty, isTranscribing, !self.isYieldingBuffer,
            self.initialized
        else {
            return
        }
        self.isYieldingBuffer = true
        while !self.pendingBuffers.isEmpty {
            let buffer = self.pendingBuffers.removeFirst()
            let processed = self.processBuffer(buffer)
            let input: AnalyzerInput = AnalyzerInput(
                buffer: processed
            )
            inputContinuation.yield(input)
            if self.pendingBuffers.isEmpty {
                break
            }
        }

        self.isYieldingBuffer = false
    }

    private func streamRemainingBuffers() async {
        // Wait until current sending finishes
        while self.isYieldingBuffer {
            try? await Task.sleep(for: .milliseconds(1))
            if !self.isYieldingBuffer {
                break
            }
        }

        // If anything still queued, flush it
        self.streamBufferIfNeeded()
    }

    // Important:
    // Use Finalize to ensure the previous sequence’s input is fully consumed
    // instead of finish(after:) method (or any other ones that finish the analysis session).
    //
    // Reason:
    // At the return of the finish(after:) method or any other ones that finish the analysis session,
    // the modules’ (SpeechTranscriber, and etc.) result streams will have ended and the modules will not accept further input from the input sequence.
    // The analyzer will not be able to resume analysis with a different input sequence and will not accept module changes; most methods will do nothing.
    // That is, we cannot reuse those SpeechModule or SpeechAnalyzer for any further transcribing tasks anymore!
    func finalizePreviousTranscribing() async throws {
        self.audioCapturer.stopCapturing()
        await self.streamRemainingBuffers()
        // When nil, finalizes up to and including the last audio the analyzer has taken from the input sequence, and
        try await self.analyzer?.finalize(through: nil)
        self.inputContinuation.finish()
        self.isTranscribing = false
        self.speechConverter = nil
        self.onResult = nil
        self.onError = nil
        self.isYieldingBuffer = false
        self.converterSetupFailed = false
    }

    private func trySetupConverter(
        inputFormat: AVAudioFormat,
        outputFormat: AVAudioFormat
    ) -> Bool {
        // Speech downsample converter: de-noised 48 kHz mono → 16 kHz
        guard
            let converter = AVAudioConverter(
                from: inputFormat,
                to: outputFormat
            )
        else {
            logError("fail to set up converter")
            self.converterSetupFailed = true
            return false
        }
        self.speechConverter = converter
        self.converterSetupFailed = false

        return true
    }

    private func processBuffer(
        _ pcmBuffer: AVAudioPCMBuffer
    ) -> AVAudioPCMBuffer {
        if self.speechConverter == nil, !self.converterSetupFailed,
            let format = self.bestAvailableAudioFormat
        {
            let _ = trySetupConverter(
                inputFormat: pcmBuffer.format,
                outputFormat: format
            )
        }
        guard
            let converter = self.speechConverter
        else {
            return pcmBuffer
        }

        let ratio =
            converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(
            (Double(pcmBuffer.frameLength) * ratio).rounded(.up) + 32
        )
        guard
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: converter.outputFormat,
                frameCapacity: outputCapacity
            )
        else {
            logError("fail to create output buffer")
            return pcmBuffer
        }

        final class FedFlag: @unchecked Sendable { var value = false }
        let fed = FedFlag()
        var convertError: NSError?
        let status = converter.convert(
            to: outputBuffer,
            error: &convertError,
            withInputFrom: { _, outStatus in
                if fed.value {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                fed.value = true
                outStatus.pointee = .haveData
                return pcmBuffer
            }
        )
        if status == .error {
            logError(
                "fail to convert: \(convertError, default: "unknown Error")"
            )
            return pcmBuffer
        }
        guard outputBuffer.frameLength > 0 else {
            logError("Invalid outputBuffer frame length ")
            return pcmBuffer
        }
        return outputBuffer
    }
}

//
//  AVAudio+Extensions.swift
//  SpeechAnalyzerDemo
//
//  Created by Itsuki on 2025/08/30.
//

import AVFAudio

nonisolated extension AVAudioInputNode {

    // When the engine renders to and from an audio device, the AVAudioSession category and the availability of hardware determines whether an app performs input (for example, input hardware isn’t available in tvOS).
    // Check the input node’s input format (specifically, the hardware format) for a nonzero sample rate and channel count to see if input is in an enabled state.
    var isEnabled: Bool {
        let inputFormat = self.inputFormat(forBus: 0)
        if inputFormat.sampleRate.isZero || inputFormat.sampleRate.isNaN {
            return false
        }
        if inputFormat.channelCount == 0 {
            return false
        }
        return true
    }
}

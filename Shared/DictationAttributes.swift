//
//  HeroAttributes.swift
//  BroadcastAPNDemo
//
//  Created by Itsuki on 2025/12/01.
//


import ActivityKit
import SwiftUI

nonisolated enum DictationState: String, Codable {
    case idle
    case starting
    case recording
    case finalizing
    case error
}

nonisolated
struct DictationAttributes: ActivityAttributes {

    // dynamic data
    public struct ContentState: Codable, Hashable {
        var state: DictationState
        var lastUpdated: Date
        var message: AttributedString?
    }
}

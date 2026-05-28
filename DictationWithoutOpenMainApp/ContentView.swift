//
//  ContentView.swift
//  DictationWithoutOpenMainApp
//
//  Created by Itsuki on 2026/05/26.
//

import AppIntents
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 36) {
            Text("Add shortcuts to start/stop dictation")
                .font(.headline)
            if let start = Bundle.main.url(
                forResource: "Start dictation",
                withExtension: "shortcut"
            ) {
                HStack {
                    Text("Start dictation")
                    ShareLink(
                        item: start,
                        label: {
                            Text("Add Shortcut")
                        }
                    )
                }
            }

            if let stop = Bundle.main.url(
                forResource: "Stop dictation",
                withExtension: "shortcut"
            ) {
                HStack {
                    Text("Stop dictation")
                    ShareLink(
                        item: stop,
                        label: {
                            Text("Add Shortcut")
                        }
                    )
                }
            }
        }
        .padding()
        .task {
            await AudioCapturer.requestRecordPermission()
        }
    }
}

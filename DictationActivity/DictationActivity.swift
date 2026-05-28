//
//  DictationActivity.swift
//  DictationActivity
//
//  Created by Itsuki on 2026/05/26.
//

import AppIntents
import SwiftUI
import WidgetKit

private struct LockScreenView: View {

    var dictationState: DictationState
    var isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isStale {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Outdated")
                    Spacer()

                }
                .foregroundStyle(.red)
                .frame(height: 16)
            }

            Text(dictationState.rawValue)
            .frame(height: 16)
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .foregroundStyle(.white.opacity(0.8))
        .activityBackgroundTint(.black.opacity(0.8))
    }
}

struct LiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationAttributes.self) { context in
            LockScreenView(
                dictationState: context.state.state,
                isStale: context.isStale
            )
        } dynamicIsland: { context in
            return createDynamicIsland(context: context)
        }
    }

    func createDynamicIsland(context: ActivityViewContext<DictationAttributes>)
        -> DynamicIsland
    {
        let contentState = context.state

        return DynamicIsland {

            DynamicIslandExpandedRegion(.bottom) {
                VStack(alignment: .leading) {
                    Text(contentState.state.rawValue)
                    messageView(contentState)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        } compactLeading: {
            messageView(contentState)
        } compactTrailing: {
            iconView(contentState)
        } minimal: {
            iconView(contentState)
        }

    }
    
    @ViewBuilder
    private func messageView(_ contentState: DictationContentState) -> some View {
        if let message = contentState.message {
            Text(message)
                .foregroundStyle(contentState.state == .error ? AnyShapeStyle(Color.red) : AnyShapeStyle(.foreground))
        }
    }
    
    @ViewBuilder
    private func iconView(_ contentState: DictationContentState) -> some View {
        switch contentState.state {
        case .error:
            Image(systemName: "exclamationmark.triangle")
        case .finalizing, .starting:
            ProgressView()
        case .recording:
            Image(systemName: "microphone")
                .symbolEffect(.pulse)
        case .idle:
            Image(systemName: "zzz")
        }
    }
}

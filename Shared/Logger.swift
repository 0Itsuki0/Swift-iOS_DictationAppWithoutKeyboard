//
//  Logger.swift
//  DictationWithoutOpenMainApp
//
//  Created by Itsuki on 2026/05/26.
//

import OSLog

nonisolated let logger = Logger(
    subsystem: "itsuki.enjoy.DictationWithoutOpenMainApp",
    category: "DictationWithoutOpenMainApp"
)

nonisolated func logInfo(_ message: String) {
    logger.log("\(message, privacy: .public)")

}

nonisolated func logError(_ message: String) {
    logger.error("\(message, privacy: .public)")
}

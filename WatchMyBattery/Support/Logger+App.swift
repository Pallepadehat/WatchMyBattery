import OSLog

extension Logger {
    nonisolated static let app = Logger(subsystem: "com.pallepadehat.WatchMyBattery", category: "app")
}

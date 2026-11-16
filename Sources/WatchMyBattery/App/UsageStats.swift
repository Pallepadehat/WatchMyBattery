import Foundation
import OSLog

/// Counts the Macs running WatchMyBattery, for the people who said yes, and only them.
///
/// Nothing is sent until it's turned on, in the welcome tour or in Settings › General. Then, once a day, it tells
/// WatchMyBattery's own small server (a Cloudflare Worker, in `Server/stats`) three things: a random ID made on this
/// Mac when sharing was turned on, the app's version and the macOS version. No name, no serial number, nothing about
/// the battery or your apps, and the server doesn't keep the IP address. Turning it off asks the server to delete that
/// ID and forgets it here, so turning it on again counts as a new Mac.
final class UsageStats {
    /// Where the pings go: `WMBUsageStatsURL` in Info.plist, made from `WMB_USAGE_STATS_HOST` in `Config/Local.xcconfig`.
    /// A build without one (any build but the maintainer's) sends nothing.
    static let endpoint: URL? = {
        guard let string = Bundle.main.object(forInfoDictionaryKey: "WMBUsageStatsURL") as? String,
            let url = URL(string: string), url.host?.isEmpty == false
        else { return nil }
        return url
    }()

    /// At most one ping in this long. An hour's slack, so a ping that went out a little late doesn't push the next a day on.
    private static let interval: TimeInterval = 23 * 60 * 60

    /// Debug builds don't count (`--send-usage-stats` makes one, to try it), and an isolated run is a copy of the real app.
    private static let isAllowed: Bool = {
        guard endpoint != nil, !LaunchOptions.isIsolated else { return false }
        #if DEBUG
            return CommandLine.arguments.contains("--send-usage-stats")
        #else
            return true
        #endif
    }()

    private weak var settings: AppSettings?
    private var timer: Timer?
    private var isSending = false
    /// No cookies, no cache: nothing kept between pings.
    private let session = URLSession(configuration: .ephemeral)

    func start(settings: AppSettings) {
        self.settings = settings
        guard Self.isAllowed else { return }
        // Checked every few hours; a ping goes out only once a day is up, and only while sharing is on.
        let timer = Timer(timeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sendIfDue() }
        }
        timer.tolerance = 60 * 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // A minute after launch, out of the way of starting up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.sendIfDue() }
    }

    /// Turns sharing on or off. On, it makes the random ID and sends the first ping; off, it forgets the ID and asks the
    /// server to delete it.
    func setSharing(_ on: Bool) {
        guard let settings, on != settings.sharesUsageStats else { return }
        settings.sharesUsageStats = on
        if on {
            if settings.usageStatsID == nil { settings.usageStatsID = UUID().uuidString.lowercased() }
            settings.usageStatsSentAt = nil
            sendIfDue()
        } else {
            let id = settings.usageStatsID
            settings.usageStatsID = nil
            settings.usageStatsSentAt = nil
            if let id { forget(id) }
        }
    }

    private func sendIfDue() {
        guard Self.isAllowed, let endpoint = Self.endpoint, let settings, settings.sharesUsageStats,
            let id = settings.usageStatsID, !isSending
        else { return }
        if let sentAt = settings.usageStatsSentAt, Date().timeIntervalSince(sentAt) < Self.interval { return }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let ping = Ping(id: id, version: Self.appVersion, macOS: "\(os.majorVersion).\(os.minorVersion)")
        var request = URLRequest(url: endpoint.appending(path: "v1/ping"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(ping)
        request.timeoutInterval = 30

        isSending = true
        Task {
            defer { isSending = false }
            do {
                let (_, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 204 else {
                    Logger.app.error("Usage stats: the server answered \((response as? HTTPURLResponse)?.statusCode ?? 0, privacy: .public)")
                    return
                }
                // Turned off (or on again, with a new ID) while it was on its way: that ping doesn't count for this one.
                guard settings.sharesUsageStats, settings.usageStatsID == id else { return }
                settings.usageStatsSentAt = Date()
            } catch {
                // Offline, say: it tries again at the next check.
                Logger.app.info("Usage stats: not sent (\(error.localizedDescription, privacy: .public))")
            }
        }
    }

    /// Asks the server to delete this ID. Once, best effort: if it doesn't get through, the ID simply stops being seen.
    private func forget(_ id: String) {
        guard Self.isAllowed, let endpoint = Self.endpoint else { return }
        var request = URLRequest(url: endpoint.appending(path: "v1/installs/\(id)"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30
        Task { _ = try? await session.data(for: request) }
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// Everything a ping says.
    private struct Ping: Encodable {
        let id: String
        let version: String
        let macOS: String
    }
}

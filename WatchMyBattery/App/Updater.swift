import AppKit
import Observation
import Sparkle

/// Keeps WatchMyBattery up to date with Sparkle.
///
/// Once a day it reads the appcast attached to the latest GitHub release (one
/// small download; nothing about you is sent). When there's a newer version,
/// it doesn't pop a window up out of nowhere: the panel shows a small note
/// instead, and one click installs it. Sparkle checks that the update is
/// signed with our EdDSA key and by the same developer, swaps it in and
/// relaunches.
///
/// "Check Now" in Settings asks Sparkle for the appcast only, without its
/// user interface, and shows the answer right in the row. Sparkle's own
/// "You're up to date" and error messages are app-modal alerts, and in an app
/// that lives in the menu bar they could end up behind the Settings window,
/// which then seemed frozen until the hidden alert was dismissed.
@Observable
final class Updater: NSObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    /// What the last check from Settings found.
    enum CheckState: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case failed(message: String)
    }

    /// A newer version that's ready to install, found by any check.
    private(set) var availableVersion: String?
    private(set) var lastCheck: Date?
    private(set) var canCheckForUpdates = false
    private(set) var checkState: CheckState = .idle

    var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.checksAutomatically) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    var downloadsAutomatically: Bool {
        get {
            access(keyPath: \.downloadsAutomatically)
            return controller.updater.automaticallyDownloadsUpdates
        }
        set {
            withMutation(keyPath: \.downloadsAutomatically) {
                controller.updater.automaticallyDownloadsUpdates = newValue
            }
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    @ObservationIgnored private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    @ObservationIgnored private var observation: NSKeyValueObservation?
    /// Clears "Up to date" after a while, so the row goes back to showing when it last checked.
    @ObservationIgnored private var resetTask: Task<Void, Never>?

    func start() {
        // Builds from Xcode stay as they are, rather than being swapped for the latest release.
        // `--start-updater` turns updates on in a debug build, for trying them out.
        #if DEBUG
            if CommandLine.arguments.contains("--start-updater") { controller.startUpdater() }
        #else
            controller.startUpdater()
        #endif
        lastCheck = controller.updater.lastUpdateCheckDate
        // Sparkle changes this on the main thread.
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    /// Looks for a new version without any windows; the answer lands in ``checkState``.
    func checkNow() {
        guard canCheckForUpdates, checkState != .checking else { return }
        resetTask?.cancel()
        checkState = .checking
        controller.updater.checkForUpdateInformation()
    }

    /// Shows Sparkle's update window for the version that was found, which downloads and installs it.
    func installUpdate() {
        NSApplication.shared.activate()
        controller.checkForUpdates(nil)
    }

    private func finishCheck(_ state: CheckState) {
        guard checkState == .checking else { return }
        checkState = state
        lastCheck = Date()
        guard state == .upToDate else { return }
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, self?.checkState == .upToDate else { return }
            self?.checkState = .idle
        }
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated {
            availableVersion = version
            finishCheck(.available(version: version))
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        // Sparkle reports "no update" as an error with a reason; only a real failure is worth showing.
        let reason = (error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? Int
        let isUpToDate = reason != nil || (error as NSError).code == Int(SUError.noUpdateError.rawValue)
        let message = error.localizedDescription
        MainActor.assumeIsolated { finishCheck(isUpToDate ? .upToDate : .failed(message: message)) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let nsError = error as NSError
        guard nsError.code != Int(SUError.noUpdateError.rawValue) else { return }
        let message = error.localizedDescription
        MainActor.assumeIsolated { finishCheck(.failed(message: message)) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        MainActor.assumeIsolated {
            if let date = updater.lastUpdateCheckDate { lastCheck = max(date, lastCheck ?? date) }
        }
    }

    // MARK: SPUStandardUserDriverDelegate

    /// Gentle reminders: the panel tells you, instead of a window.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        let version = update.displayVersionString
        MainActor.assumeIsolated { availableVersion = version }
        return false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        MainActor.assumeIsolated { availableVersion = version }
    }

    /// Any alert Sparkle still shows (while installing, say) comes to the front instead of hiding behind a window.
    nonisolated func standardUserDriverWillShowModalAlert() {
        MainActor.assumeIsolated { NSApplication.shared.activate() }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            availableVersion = nil
            if case .available = checkState { checkState = .idle }
        }
    }
}

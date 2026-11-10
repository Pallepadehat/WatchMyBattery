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
@Observable
final class Updater: NSObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    /// A newer version that's ready to install, found by the background check.
    private(set) var availableVersion: String?
    private(set) var lastCheck: Date?
    private(set) var canCheckForUpdates = false

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

    func start() {
        // Builds from Xcode stay as they are, rather than being swapped for the latest release.
        #if !DEBUG
            controller.startUpdater()
        #endif
        lastCheck = controller.updater.lastUpdateCheckDate
        // Sparkle changes this on the main thread.
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    /// Checks right now, showing Sparkle's window with the result (or installs
    /// the update that's already been found).
    func checkNow() {
        NSApplication.shared.activate()
        controller.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        MainActor.assumeIsolated { lastCheck = updater.lastUpdateCheckDate }
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

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { availableVersion = nil }
    }
}

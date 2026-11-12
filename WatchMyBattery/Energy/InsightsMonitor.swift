import AppKit
import BatteryKit
import Observation

/// Things worth acting on, at the right moment: a meeting the battery won't
/// last through, a Mac using more power than usual, and a new app among the
/// hungriest. Each shows in the panel, and as a notification if it's turned
/// on in Settings › Notifications.
///
/// It adds no sampling of its own. The meeting check runs when the battery
/// reading or the calendar changes, and once more when the next meeting comes
/// within the warning time. The other two run after each of the history's
/// samples (every five minutes, on battery only), and when the panel opens.
@Observable
final class InsightsMonitor {
    private(set) var meeting: MeetingWarning?
    private(set) var unusualDrain: UnusualDrain?
    private(set) var newApps: [BatteryHistory.AppEnergy] = []
    /// "More than usual" was dismissed in the panel, until the next charge.
    private(set) var isUnusualDrainDismissed = false

    let calendar = CalendarWatcher()

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var meetingTimer: Task<Void, Never>?
    @ObservationIgnored private var notifiedMeetings: Set<UpcomingEvent> = []
    @ObservationIgnored private var dismissedMeetings: Set<UpcomingEvent> = []
    /// "More than usual" is sent at most once a charge.
    @ObservationIgnored private var isUnusualDrainNotified = false
    @ObservationIgnored private var wasPluggedIn: Bool?

    /// Once a warning is showing, it stays until the battery would last this long past the meeting.
    private static let meetingMargin: TimeInterval = 10 * 60

    func start(model: AppModel) {
        self.model = model
        model.history.didRecordSample = { [weak self] in self?.checkHistory() }
        observe()
        checkHistory()
    }

    /// The panel opened: time has passed since the last sample, so have another look.
    func refresh() {
        // Access may have been allowed, or turned off, in System Settings since.
        calendar.refreshAccess()
        checkHistory()
        evaluateMeeting()
    }

    // MARK: - Dismissing, from the panel

    func dismissMeeting() {
        guard let meeting else { return }
        dismissedMeetings.insert(meeting.event)
        self.meeting = nil
    }

    func dismissUnusualDrain() {
        isUnusualDrainDismissed = true
    }

    /// Never shows this app as new again.
    func dismissNewApp(_ key: String) {
        model?.history.markDismissedAsNew(key)
        newApps.removeAll { $0.id == key }
    }

    // MARK: - Watching

    private func observe() {
        guard let model else { return }
        let (snapshot, warns) = withObservationTracking {
            // Read for the tracking: any of these changing means another look.
            _ = (model.settings.meetingWarningLead, calendar.events, calendar.access, model.settings.recordsHistory)
            return (model.battery.snapshot, model.settings.warnsBeforeMeetings)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }

        if snapshot.isPluggedIn, wasPluggedIn == false { didPlugIn() }
        wasPluggedIn = snapshot.isPluggedIn

        // Reads the calendar only once access is allowed, and never asks for it from here: that's the "Allow
        // Access…" button in Settings, so opening the app never brings up macOS's prompt.
        let reads = warns && calendar.access == .granted
        if reads, !calendar.isWatching {
            calendar.start()
        } else if !reads, calendar.isWatching {
            calendar.stop()
        }
        evaluateMeeting()
        if !model.settings.recordsHistory { checkHistory() }
    }

    /// Charging again: every insight starts over.
    private func didPlugIn() {
        notifiedMeetings = []
        dismissedMeetings = []
        isUnusualDrainNotified = false
        isUnusualDrainDismissed = false
        unusualDrain = nil
        model?.notifier.removeMeetingNotification()
    }

    // MARK: - Charge before a meeting

    private func evaluateMeeting() {
        meetingTimer?.cancel()
        meetingTimer = nil
        guard let model, model.settings.warnsBeforeMeetings, calendar.access == .granted else {
            if meeting != nil { meeting = nil }
            return
        }
        calendar.refreshIfStale()
        let snapshot = model.battery.snapshot
        let lead = TimeInterval(model.settings.meetingWarningLead * 60)
        let events = calendar.events.filter { !dismissedMeetings.contains($0) }
        var warning = MeetingCheck.warning(snapshot: snapshot, events: events, lead: lead)
        if warning == nil, let shown = meeting, events.contains(shown.event) {
            warning = MeetingCheck.warning(snapshot: snapshot, events: [shown.event], lead: lead, margin: Self.meetingMargin)
        }
        if warning != meeting { meeting = warning }

        if let warning, !notifiedMeetings.contains(warning.event) {
            notifiedMeetings.insert(warning.event)
            let offersLowPowerMode = model.lowPowerMode.isSupported && !snapshot.isLowPowerModeOn
            Task { await model.notifier.notifyMeeting(warning, offersLowPowerMode: offersLowPowerMode) }
        }

        // On battery, look again when the next meeting comes within the warning time, or the one shown ends.
        guard !snapshot.isPluggedIn else { return }
        let next = [MeetingCheck.nextCheck(events: events, lead: lead), meeting?.event.end].compactMap(\.self).min()
        guard let next else { return }
        meetingTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 1)), tolerance: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.evaluateMeeting()
        }
    }

    // MARK: - More than usual, and new apps

    private func checkHistory() {
        guard let model, model.settings.recordsHistory else {
            if unusualDrain != nil { unusualDrain = nil }
            if !newApps.isEmpty { newApps = [] }
            return
        }
        let snapshot = model.battery.snapshot
        let history = model.history.history
        let profile = model.history.profile
        let settings = model.settings

        let drain = snapshot.hasBattery && !snapshot.isPluggedIn ? UsualDrainCheck.check(history: history, profile: profile) : nil
        if drain != unusualDrain { unusualDrain = drain }
        // Once a charge, and not once it's been dismissed in the panel.
        if let drain, settings.notifiesAboutUnusualDrain, !isUnusualDrainNotified, !isUnusualDrainDismissed {
            isUnusualDrainNotified = true
            let running = drain.cause.flatMap(runningApp)
            Task { await model.notifier.notifyUnusualDrain(drain, cause: running) }
        }

        // Hidden apps aren't pointed out here either.
        let fresh = NewAppCheck.newApps(history: history, profile: profile).filter { !settings.isExcluded(bundleIdentifier: $0.app.bundleIdentifier) }
        let shown = fresh.filter { profile.apps[$0.id]?.dismissedAsNew == nil }
        if shown != newApps { newApps = shown }
        if settings.notifiesAboutNewApps {
            for app in fresh where profile.apps[app.id]?.notifiedAsNew == nil && profile.apps[app.id]?.dismissedAsNew == nil {
                model.history.markNotifiedAsNew(app.id)
                let running = runningApp(app.app)
                Task { await model.notifier.notifyNewApp(app.app, running: running) }
            }
        }
    }

    private func runningApp(_ app: BatteryHistory.AppIdentity) -> NSRunningApplication? {
        guard let bundleIdentifier = app.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first { !$0.isTerminated }
    }

    #if DEBUG
        /// Shows made-up insights, for previews.
        func preview(meeting: MeetingWarning?, unusualDrain: UnusualDrain?, newApps: [BatteryHistory.AppEnergy]) {
            self.meeting = meeting
            self.unusualDrain = unusualDrain
            self.newApps = newApps
        }
    #endif
}

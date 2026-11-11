import AppKit
import BatteryKit
import EventKit
import OSLog
import Observation

/// The next day's meetings from the Calendar app, for "charge before your meeting".
///
/// Only when the warning is turned on, and only after macOS has asked you for
/// access. It reads when events start and end, and whether you're going,
/// never titles, places or who's invited. Nothing is kept on disk or sent
/// anywhere. Events are read again when the calendar changes, or when what
/// was read is an hour old, rather than on a timer.
@Observable
final class CalendarWatcher {
    enum Access: Equatable {
        case notDetermined
        case granted
        /// Turned off in System Settings, or not allowed on this Mac.
        case denied
    }

    private(set) var access: Access = CalendarWatcher.currentAccess()
    /// Meetings that haven't ended, from a little before now to a day ahead.
    private(set) var events: [UpcomingEvent] = []

    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private var fetchedAt = Date.distantPast
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var starting: Task<Void, Never>?
    /// Goes up with every ``stop()``, so a start still waiting for the user's answer knows it's no longer wanted.
    @ObservationIgnored private var generation = 0

    private static let lookAhead: TimeInterval = 24 * 3600
    private static let refreshInterval: TimeInterval = 3600

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    var isWatching: Bool { store != nil }

    /// Starts reading the calendar, asking for access first if macOS hasn't yet. Settings and the insights can both
    /// ask at once (when the switch is turned on); the second waits for the first rather than asking again.
    func start() async {
        if let starting {
            await starting.value
            return
        }
        guard store == nil else {
            refreshIfStale()
            return
        }
        let task = Task { await begin() }
        starting = task
        await task.value
        starting = nil
    }

    private func begin() async {
        let wanted = generation
        let store = EKEventStore()
        if access == .notDetermined {
            Logger.app.info("Asking for calendar access")
            // macOS holds a background app's permission prompt until it comes forward, which a menu bar app may never
            // do on its own. From Settings it's already in front; from anywhere else, step forward so the prompt shows.
            NSApp.activate()
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            if !granted { Logger.app.notice("Calendar access wasn't allowed") }
        }
        access = Self.currentAccess()
        Logger.app.info("Calendar access: \(String(describing: self.access), privacy: .public)")
        // Turned off again while macOS was asking.
        guard access == .granted, generation == wanted else { return }
        self.store = store
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Stops reading it, and forgets what was read.
    func stop() {
        generation += 1
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        changeObserver = nil
        store = nil
        if !events.isEmpty { events = [] }
    }

    /// Checks whether access was changed in System Settings.
    func refreshAccess() {
        let current = Self.currentAccess()
        if current != access { access = current }
    }

    func refreshIfStale() {
        if Date().timeIntervalSince(fetchedAt) >= Self.refreshInterval { refresh() }
    }

    /// System Settings › Privacy & Security › Calendars.
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refresh() {
        guard let store else { return }
        let now = Date()
        fetchedAt = now
        // From a few hours back, to catch a meeting under way.
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-6 * 3600), end: now.addingTimeInterval(Self.lookAhead), calendars: nil)
        let found = store.events(matching: predicate)
            .filter(Self.isMeeting)
            .map { UpcomingEvent(start: $0.startDate, end: $0.endDate) }
            .filter { $0.end > now }
        let upcoming = Array(Set(found)).sorted { $0.start < $1.start }
        // A count only: never anything about the meetings themselves.
        Logger.app.info("Read the calendar: \(upcoming.count, privacy: .public) meetings in the next day")
        if upcoming != events { events = upcoming }
    }

    /// Something you'll be at: not all day, not cancelled or declined, and not marked as free time.
    private static func isMeeting(_ event: EKEvent) -> Bool {
        guard !event.isAllDay, event.status != .canceled, event.availability != .free else { return false }
        if let me = event.attendees?.first(where: \.isCurrentUser), me.participantStatus == .declined { return false }
        return true
    }
}

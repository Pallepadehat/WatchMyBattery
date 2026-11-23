import BatteryKit
import Foundation

/// Sends the weekly summary on Monday morning (or wherever the week starts), at 9:00, or as soon after as the Mac is
/// awake, once a week, when it's turned on in Settings › Notifications. Between weeks it sleeps: one timer, on a clock
/// that counts the Mac's sleep too, so it fires on waking if 9:00 went by.
final class WeeklySummaryScheduler {
    private weak var model: AppModel?
    private var timer: Task<Void, Never>?
    private var wasEnabled = false

    /// The hour of the week's first day it goes out.
    static let hour = 9

    func start(model: AppModel) {
        self.model = model
        wasEnabled = model.settings.notifiesWeeklySummary
        observe()
    }

    private func observe() {
        guard let model else { return }
        let enabled = withObservationTracking {
            _ = model.settings.recordsHistory
            return model.settings.notifiesWeeklySummary
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        // Turned on now: the first summary is next week's, not one for a week that may be long over.
        if enabled, !wasEnabled { model.settings.weeklySummarySentFor = Self.weekStart(of: Date()) }
        wasEnabled = enabled
        schedule()
    }

    private func schedule() {
        timer?.cancel()
        timer = nil
        guard let model, model.settings.notifiesWeeklySummary, model.settings.recordsHistory else { return }
        let now = Date()
        let calendar = Calendar.current
        guard let thisWeek = Self.weekStart(of: now), let due = calendar.date(byAdding: .hour, value: Self.hour, to: thisWeek) else { return }
        if now >= due, model.settings.weeklySummarySentFor != thisWeek {
            send(for: thisWeek)
        }
        // Next week's.
        guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeek),
            let next = calendar.date(byAdding: .hour, value: Self.hour, to: nextWeek)
        else { return }
        let wait = max(next.timeIntervalSince(now), 60)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(120))
            guard !Task.isCancelled else { return }
            self?.schedule()
        }
    }

    private func send(for week: Date) {
        guard let model else { return }
        model.settings.weeklySummarySentFor = week
        guard let summary = model.history.profile.lastWeekSummary(), !summary.isEmpty else { return }
        Task { await model.notifier.notifyWeeklySummary(summary) }
    }

    static func weekStart(of date: Date) -> Date? {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start
    }
}

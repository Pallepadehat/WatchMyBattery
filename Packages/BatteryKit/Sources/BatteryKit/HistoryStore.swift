import Foundation
import SwiftData

/// The history, kept on disk with SwiftData: the last day of level readings and energy samples (``BatteryHistory``),
/// and two weeks of hourly summaries (``UsageProfile``).
///
/// Reading happens in memory, on the value types, as before: the panel reads the history every time it draws, and
/// they answer in microseconds. The store only writes what changed, a row per level change or sample and the hour it
/// touched, instead of rewriting the whole history. Nothing is written until ``save()``, so the caller decides how
/// often the disk is touched.
@MainActor
public final class HistoryStore {
    public private(set) var history = BatteryHistory()
    public private(set) var profile = UsageProfile()

    private let context: ModelContext
    /// Kept on disk, rather than in memory (by choice, or because the disk couldn't be used).
    public let isOnDisk: Bool
    /// Every hour and app row, loaded once: there are a few hundred at most, and they're updated all the time.
    private var hourRows: [Date: StoredHour] = [:]
    private var appRows: [String: StoredApp] = [:]

    /// Opens the store at `url`, creating it if needed; `nil` keeps it in memory only (for previews, tests, and a
    /// made-up battery that mustn't reach the real history).
    public init(url: URL?, now: Date = Date()) throws {
        let configuration: ModelConfiguration
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: Self.schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)
        }
        let container = try ModelContainer(for: Self.schema, migrationPlan: HistoryMigrationPlan.self, configurations: configuration)
        context = ModelContext(container)
        isOnDisk = url != nil
        context.autosaveEnabled = false
        try load(now: now)
    }

    /// A store in memory, which can't fail to open.
    public static func inMemory() -> HistoryStore {
        // An in-memory SQLite store only fails when the schema itself is broken, which the tests would catch.
        // swift-format-ignore: NeverUseForceTry
        try! HistoryStore(url: nil)
    }

    /// Opens the store at `url`, starting it over if it can't be read (a damaged file, say), and falling back to
    /// memory if even that fails. `problem` hears about either.
    public static func open(at url: URL?, problem: (Error) -> Void = { _ in }) -> HistoryStore {
        do {
            return try HistoryStore(url: url)
        } catch {
            problem(error)
        }
        if let url {
            removeFiles(at: url)
            do {
                return try HistoryStore(url: url)
            } catch {
                problem(error)
            }
        }
        return inMemory()
    }

    /// Deletes the store's files: the database and SQLite's journal beside it.
    public static func removeFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    static let schema = Schema(versionedSchema: HistorySchemaV1.self)

    public var isEmpty: Bool { history.isEmpty && profile.isEmpty }

    /// There's something not yet written to disk.
    public var hasUnsavedChanges: Bool { context.hasChanges }

    // MARK: - Recording

    /// Records the battery's level, like ``BatteryHistory/record(_:at:)``.
    public func record(_ snapshot: BatterySnapshot, at date: Date = Date()) {
        let edges = Edges(history)
        history.record(snapshot, at: date)
        guard let point = history.levels.last, point != edges.lastLevel else { return }
        context.insert(StoredLevel(point))
        if history.unplugged != edges.unplugged { storeUnplugged(history.unplugged) }
        deleteTrimmed(since: edges, now: date)
        storeHours(profile.record(level: point))
        pruneProfileRows()
    }

    /// Records the energy apps used, like ``BatteryHistory/record(joules:seconds:systemWatts:at:)``.
    public func record(
        joules: [BatteryHistory.AppIdentity: Double], seconds: TimeInterval, systemWatts: Double?, at date: Date = Date()
    ) {
        let edges = Edges(history)
        history.record(joules: joules, seconds: seconds, systemWatts: systemWatts, at: date)
        guard history.samples.count > edges.sampleCount || history.samples.first?.date != edges.firstSample,
            let sample = history.samples.last(where: { $0.date == date })
        else { return }
        context.insert(StoredSample(sample))
        deleteTrimmed(since: edges, now: date)
        storeHours(profile.record(sample, apps: history.apps))
        for key in sample.joules.keys { storeApp(key) }
        pruneProfileRows()
    }

    /// The "new app" notification went out for an app.
    public func markNotifiedAsNew(_ key: String, at date: Date = Date()) {
        profile.markNotifiedAsNew(key, at: date)
        storeApp(key)
    }

    /// The "new app" line in the panel was dismissed.
    public func markDismissedAsNew(_ key: String, at date: Date = Date()) {
        profile.markDismissedAsNew(key, at: date)
        storeApp(key)
    }

    /// Forgets everything, on disk too once saved.
    public func removeAll() {
        history.removeAll()
        profile.removeAll()
        hourRows = [:]
        appRows = [:]
        for model in [StoredLevel.self, StoredSample.self, StoredHour.self, StoredApp.self, StoredMarker.self] as [any PersistentModel.Type] {
            try? context.delete(model: model)
        }
    }

    /// Writes what changed since the last save.
    public func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    /// Brings in a history kept the old way (`History.plist`, before 0.2.5), building its hourly summary as it goes.
    /// Only into an empty store, so it can never mix with newer readings. Returns whether it did.
    @discardableResult
    public func importLegacy(_ legacy: BatteryHistory) -> Bool {
        guard isEmpty, !legacy.isEmpty else { return false }
        // Replayed in date order, so the profile sees what it would have seen at the time.
        var levels = legacy.levels[...]
        for sample in legacy.samples {
            while let level = levels.first, level.date <= sample.date {
                profile.record(level: level)
                levels.removeFirst()
            }
            profile.record(sample, apps: legacy.apps)
        }
        for level in levels { profile.record(level: level) }
        history = legacy
        for level in legacy.levels { context.insert(StoredLevel(level)) }
        for sample in legacy.samples { context.insert(StoredSample(sample)) }
        storeUnplugged(legacy.unplugged)
        storeHours(Set(profile.hours.map(\.start)))
        for key in profile.apps.keys { storeApp(key) }
        return true
    }

    // MARK: - Rows

    private func load(now: Date) throws {
        let levels = try context.fetch(FetchDescriptor<StoredLevel>(sortBy: [SortDescriptor(\.date)]))
        let samples = try context.fetch(FetchDescriptor<StoredSample>(sortBy: [SortDescriptor(\.date)]))
        let hours = try context.fetch(FetchDescriptor<StoredHour>(sortBy: [SortDescriptor(\.start)]))
        let apps = try context.fetch(FetchDescriptor<StoredApp>())
        let unplugged = try context.fetch(FetchDescriptor<StoredMarker>()).first { $0.name == StoredMarker.unplugged }

        hourRows = Dictionary(hours.map { ($0.start, $0) }, uniquingKeysWith: { first, _ in first })
        appRows = Dictionary(apps.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let profileApps = Dictionary(apps.map { ($0.key, $0.app) }, uniquingKeysWith: { first, _ in first })
        history = BatteryHistory(
            levels: levels.map(\.point), samples: samples.map(\.sample), apps: profileApps.mapValues(\.identity), unplugged: unplugged?.point,
            now: now)
        profile = UsageProfile(hours: hours.map(\.hour), apps: profileApps, lastLevel: history.levels.last, now: now)

        // What the value types dropped as too old goes from the disk too.
        if let first = history.levels.first?.date {
            delete(StoredLevel.self, where: #Predicate { $0.date < first })
        }
        let cutoff = now.addingTimeInterval(-BatteryHistory.retention)
        delete(StoredSample.self, where: #Predicate { $0.date < cutoff })
        pruneProfileRows()
        try save()
    }

    /// The ends of the history before a change, to tell what recording added and what it trimmed.
    private struct Edges {
        let lastLevel: BatteryHistory.LevelPoint?
        let firstLevel: Date?
        let firstSample: Date?
        let sampleCount: Int
        let unplugged: BatteryHistory.LevelPoint?

        init(_ history: BatteryHistory) {
            lastLevel = history.levels.last
            firstLevel = history.levels.first?.date
            firstSample = history.samples.first?.date
            sampleCount = history.samples.count
            unplugged = history.unplugged
        }
    }

    /// Recording trims what's too old (levels and samples alike); the disk follows.
    private func deleteTrimmed(since edges: Edges, now: Date) {
        if history.levels.first?.date != edges.firstLevel, let first = history.levels.first?.date {
            delete(StoredLevel.self, where: #Predicate { $0.date < first })
        }
        if history.samples.first?.date != edges.firstSample, edges.firstSample != nil {
            let cutoff = history.samples.first?.date ?? now.addingTimeInterval(-BatteryHistory.retention)
            delete(StoredSample.self, where: #Predicate { $0.date < cutoff })
        }
    }

    private func storeHours(_ starts: Set<Date>) {
        for start in starts {
            guard let hour = profile.hour(at: start) else { continue }
            if let row = hourRows[start] {
                row.update(hour)
            } else {
                let row = StoredHour(hour)
                context.insert(row)
                hourRows[start] = row
            }
        }
    }

    private func storeApp(_ key: String) {
        guard let app = profile.apps[key] else { return }
        if let row = appRows[key] {
            row.update(app)
        } else {
            let row = StoredApp(key: key, app: app)
            context.insert(row)
            appRows[key] = row
        }
    }

    private func storeUnplugged(_ point: BatteryHistory.LevelPoint?) {
        let name = StoredMarker.unplugged
        let row = try? context.fetch(FetchDescriptor<StoredMarker>(predicate: #Predicate { $0.name == name })).first
        switch (row, point) {
        case (let row?, let point?): row.update(point)
        case (let row?, nil): context.delete(row)
        case (nil, let point?): context.insert(StoredMarker(name: name, point: point))
        case (nil, nil): break
        }
    }

    /// Removes the rows for hours and apps the profile has let go of.
    private func pruneProfileRows() {
        if hourRows.count > profile.hours.count {
            for (start, row) in hourRows where profile.hour(at: start) == nil {
                context.delete(row)
                hourRows[start] = nil
            }
        }
        if appRows.count > profile.apps.count {
            for (key, row) in appRows where profile.apps[key] == nil {
                context.delete(row)
                appRows[key] = nil
            }
        }
    }

    private func delete<Model: PersistentModel>(_ type: Model.Type, where predicate: Predicate<Model>) {
        guard let rows = try? context.fetch(FetchDescriptor(predicate: predicate)) else { return }
        for row in rows { context.delete(row) }
    }
}

// MARK: - The schema

typealias StoredLevel = HistorySchemaV1.StoredLevel
typealias StoredSample = HistorySchemaV1.StoredSample
typealias StoredHour = HistorySchemaV1.StoredHour
typealias StoredApp = HistorySchemaV1.StoredApp
typealias StoredMarker = HistorySchemaV1.StoredMarker

/// The first version of the store, from 0.2.5. A later version goes next to it, with a stage in
/// ``HistoryMigrationPlan`` to bring the old one along.
enum HistorySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [StoredLevel.self, StoredSample.self, StoredHour.self, StoredApp.self, StoredMarker.self]
    }

    /// A level reading from the last day.
    @Model final class StoredLevel {
        var date: Date
        var percentage: Int
        var isPluggedIn: Bool

        init(_ point: BatteryHistory.LevelPoint) {
            date = point.date
            percentage = point.percentage
            isPluggedIn = point.isPluggedIn
        }

        var point: BatteryHistory.LevelPoint { .init(date: date, percentage: percentage, isPluggedIn: isPluggedIn) }
    }

    /// An energy sample from the last day.
    @Model final class StoredSample {
        var date: Date
        var seconds: Double
        var joules: [String: Double]
        var systemWatts: Double?

        init(_ sample: BatteryHistory.EnergySample) {
            date = sample.date
            seconds = sample.seconds
            joules = sample.joules
            systemWatts = sample.systemWatts
        }

        var sample: BatteryHistory.EnergySample { .init(date: date, seconds: seconds, joules: joules, systemWatts: systemWatts) }
    }

    /// One hour of the last two weeks.
    @Model final class StoredHour {
        @Attribute(.unique) var start: Date
        var batterySeconds: Double
        var drained: Int
        var sampledSeconds: Double
        var systemJoules: Double
        var measuredSeconds: Double
        var appJoules: [String: Double]

        init(_ hour: UsageProfile.Hour) {
            start = hour.start
            batterySeconds = hour.batterySeconds
            drained = hour.drained
            sampledSeconds = hour.sampledSeconds
            systemJoules = hour.systemJoules
            measuredSeconds = hour.measuredSeconds
            appJoules = hour.appJoules
        }

        func update(_ hour: UsageProfile.Hour) {
            batterySeconds = hour.batterySeconds
            drained = hour.drained
            sampledSeconds = hour.sampledSeconds
            systemJoules = hour.systemJoules
            measuredSeconds = hour.measuredSeconds
            appJoules = hour.appJoules
        }

        var hour: UsageProfile.Hour {
            .init(
                start: start, batterySeconds: batterySeconds, drained: drained, sampledSeconds: sampledSeconds, systemJoules: systemJoules,
                measuredSeconds: measuredSeconds, appJoules: appJoules)
        }
    }

    /// An app seen in the last two weeks.
    @Model final class StoredApp {
        @Attribute(.unique) var key: String
        var name: String
        var bundleIdentifier: String?
        var firstSeen: Date
        var lastSeen: Date
        var notifiedAsNew: Date?
        var dismissedAsNew: Date?

        init(key: String, app: UsageProfile.App) {
            self.key = key
            name = app.identity.name
            bundleIdentifier = app.identity.bundleIdentifier
            firstSeen = app.firstSeen
            lastSeen = app.lastSeen
            notifiedAsNew = app.notifiedAsNew
            dismissedAsNew = app.dismissedAsNew
        }

        func update(_ app: UsageProfile.App) {
            name = app.identity.name
            bundleIdentifier = app.identity.bundleIdentifier
            firstSeen = app.firstSeen
            lastSeen = app.lastSeen
            notifiedAsNew = app.notifiedAsNew
            dismissedAsNew = app.dismissedAsNew
        }

        var app: UsageProfile.App {
            .init(
                identity: .init(name: name, bundleIdentifier: bundleIdentifier), firstSeen: firstSeen, lastSeen: lastSeen,
                notifiedAsNew: notifiedAsNew, dismissedAsNew: dismissedAsNew)
        }
    }

    /// A level reading kept for a reason of its own, however old: when the Mac was last unplugged.
    @Model final class StoredMarker {
        static let unplugged = "unplugged"

        @Attribute(.unique) var name: String
        var date: Date
        var percentage: Int
        var isPluggedIn: Bool

        init(name: String, point: BatteryHistory.LevelPoint) {
            self.name = name
            date = point.date
            percentage = point.percentage
            isPluggedIn = point.isPluggedIn
        }

        func update(_ point: BatteryHistory.LevelPoint) {
            date = point.date
            percentage = point.percentage
            isPluggedIn = point.isPluggedIn
        }

        var point: BatteryHistory.LevelPoint { .init(date: date, percentage: percentage, isPluggedIn: isPluggedIn) }
    }
}

enum HistoryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HistorySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

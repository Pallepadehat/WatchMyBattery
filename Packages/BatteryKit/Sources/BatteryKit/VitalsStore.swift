import Foundation
import SwiftData

/// ``BatteryVitals`` on disk, with SwiftData: a row per hour and per health day, each written only when it changes.
///
/// A file of its own, next to the history's, rather than more models in ``HistoryStore``: the history needs no
/// migration, and either can be started over without the other.
@MainActor
public final class VitalsStore {
    public private(set) var vitals: BatteryVitals

    private let context: ModelContext
    public let isOnDisk: Bool
    private var hourRows: [Date: StoredVitalsHour] = [:]
    private var healthRows: [Date: StoredHealthDay] = [:]

    private static let encoder = PropertyListEncoder()
    private static let decoder = PropertyListDecoder()

    /// Opens the store at `url`, creating it if needed; `nil` keeps it in memory only.
    public init(url: URL?, now: Date = Date(), retention: TimeInterval = UsageProfile.retention) throws {
        let configuration: ModelConfiguration
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: Self.schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)
        }
        let container = try ModelContainer(for: Self.schema, migrationPlan: VitalsMigrationPlan.self, configurations: configuration)
        context = ModelContext(container)
        context.autosaveEnabled = false
        isOnDisk = url != nil

        let hours = try context.fetch(FetchDescriptor<StoredVitalsHour>())
        let days = try context.fetch(FetchDescriptor<StoredHealthDay>())
        hourRows = Dictionary(hours.map { ($0.start, $0) }, uniquingKeysWith: { first, _ in first })
        healthRows = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        vitals = BatteryVitals(
            hours: hours.compactMap { try? Self.decoder.decode(BatteryVitals.Hour.self, from: $0.data) },
            health: days.map(\.healthDay), retention: retention, now: now)
        pruneHours()
        try save()
    }

    /// Opens the store at `url`, starting it over if it can't be read, and falling back to memory if even that fails.
    public static func open(at url: URL?, retention: TimeInterval = UsageProfile.retention, problem: (Error) -> Void = { _ in }) -> VitalsStore {
        do {
            return try VitalsStore(url: url, retention: retention)
        } catch {
            problem(error)
        }
        if let url {
            HistoryStore.removeFiles(at: url)
            do {
                return try VitalsStore(url: url, retention: retention)
            } catch {
                problem(error)
            }
        }
        // An in-memory SQLite store only fails when the schema itself is broken, which the tests would catch.
        // swift-format-ignore: NeverUseForceTry
        return try! VitalsStore(url: nil, retention: retention)
    }

    static let schema = Schema(versionedSchema: VitalsSchemaV1.self)

    public var hasUnsavedChanges: Bool { context.hasChanges }

    public func record(_ reading: VitalsReading, at date: Date = Date()) {
        let start = vitals.record(reading, at: date)
        if let hour = vitals.hour(at: start), let data = try? Self.encoder.encode(hour) {
            if let row = hourRows[start] {
                row.data = data
            } else {
                let row = StoredVitalsHour(start: start, data: data)
                context.insert(row)
                hourRows[start] = row
            }
        }
        pruneHours()
    }

    public func record(health: BatteryHealth, at date: Date = Date()) {
        guard let day = vitals.record(health: health, at: date), let entry = vitals.healthDay(at: day) else { return }
        if let row = healthRows[day] {
            row.update(entry)
        } else {
            let row = StoredHealthDay(entry)
            context.insert(row)
            healthRows[day] = row
        }
    }

    public func setRetention(_ retention: TimeInterval, now: Date = Date()) {
        guard retention != vitals.retention else { return }
        vitals.retention = retention
        vitals.trim(now: now)
        pruneHours()
    }

    /// Forgets everything, on disk too once saved.
    public func removeAll() {
        vitals.removeAll()
        hourRows = [:]
        healthRows = [:]
        context.rollback()
        try? context.delete(model: StoredVitalsHour.self)
        try? context.delete(model: StoredHealthDay.self)
    }

    public func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    private func pruneHours() {
        guard hourRows.count > vitals.hours.count else { return }
        for (start, row) in hourRows where vitals.hour(at: start) == nil {
            context.delete(row)
            hourRows[start] = nil
        }
    }
}

typealias StoredVitalsHour = VitalsSchemaV1.StoredVitalsHour
typealias StoredHealthDay = VitalsSchemaV1.StoredHealthDay

enum VitalsSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] { [StoredVitalsHour.self, StoredHealthDay.self] }

    /// An hour's readings, as a property list of ``BatteryVitals/Hour``: its summaries change shape more easily than
    /// columns would.
    @Model final class StoredVitalsHour {
        @Attribute(.unique) var start: Date
        var data: Data

        init(start: Date, data: Data) {
            self.start = start
            self.data = data
        }
    }

    @Model final class StoredHealthDay {
        @Attribute(.unique) var day: Date
        var maximumCapacity: Double?
        var cycleCount: Int?

        init(_ entry: BatteryVitals.HealthDay) {
            day = entry.day
            maximumCapacity = entry.maximumCapacity
            cycleCount = entry.cycleCount
        }

        func update(_ entry: BatteryVitals.HealthDay) {
            maximumCapacity = entry.maximumCapacity
            cycleCount = entry.cycleCount
        }

        var healthDay: BatteryVitals.HealthDay { .init(day: day, maximumCapacity: maximumCapacity, cycleCount: cycleCount) }
    }
}

enum VitalsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [VitalsSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

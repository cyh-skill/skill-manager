import Foundation

public struct CatalogStore: Sendable {
    private static let accessLock = NSRecursiveLock()

    public let paths: ManagerPaths

    public init(paths: ManagerPaths = ManagerPaths()) {
        self.paths = paths
    }

    public func ensureLayout() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.sources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.routerRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.bin, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.migrationBackups, withIntermediateDirectories: true)
    }

    public func load() throws -> SkillCatalog {
        Self.accessLock.lock()
        defer { Self.accessLock.unlock() }
        return try loadUnlocked()
    }

    public func save(_ catalog: SkillCatalog) throws {
        Self.accessLock.lock()
        defer { Self.accessLock.unlock() }
        try saveUnlocked(catalog)
    }

    @discardableResult
    func update<T>(_ operation: (inout SkillCatalog) throws -> T) throws -> T {
        Self.accessLock.lock()
        defer { Self.accessLock.unlock() }
        var catalog = try loadUnlocked()
        let result = try operation(&catalog)
        try saveUnlocked(catalog)
        return result
    }

    private func loadUnlocked() throws -> SkillCatalog {
        try ensureLayout()
        guard FileManager.default.fileExists(atPath: paths.catalog.path) else {
            return SkillCatalog()
        }
        let data = try Data(contentsOf: paths.catalog)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SkillCatalog.self, from: data)
    }

    private func saveUnlocked(_ catalog: SkillCatalog) throws {
        try ensureLayout()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(catalog)
        try data.write(to: paths.catalog, options: .atomic)
    }

    public func addingActivity(_ activity: ActivityEvent, to catalog: inout SkillCatalog) {
        catalog.activities.insert(activity, at: 0)
        if catalog.activities.count > 500 {
            catalog.activities.removeLast(catalog.activities.count - 500)
        }
    }
}

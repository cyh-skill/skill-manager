import Foundation

public struct CatalogStore: Sendable {
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
        try ensureLayout()
        guard FileManager.default.fileExists(atPath: paths.catalog.path) else {
            return SkillCatalog()
        }
        let data = try Data(contentsOf: paths.catalog)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SkillCatalog.self, from: data)
    }

    public func save(_ catalog: SkillCatalog) throws {
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

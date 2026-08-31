import Foundation

public struct ManagerPaths: Sendable {
    private let environment: [String: String]
    public let home: URL
    public let root: URL
    public let sources: URL
    public let routerRoot: URL
    public let routerSkill: URL
    public let catalog: URL
    public let bin: URL
    public let migrationBackups: URL

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
        let fileManager = FileManager.default
        let homePath = environment["HOME"] ?? fileManager.homeDirectoryForCurrentUser.path
        home = URL(fileURLWithPath: homePath, isDirectory: true)

        if let override = environment["SKILL_MANAGER_HOME"], !override.isEmpty {
            root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            root = home.appendingPathComponent(".skill-manager", isDirectory: true)
        }

        sources = root.appendingPathComponent("sources", isDirectory: true)
        routerRoot = root.appendingPathComponent("router", isDirectory: true)
        routerSkill = routerRoot.appendingPathComponent("skill-router", isDirectory: true)
        catalog = root.appendingPathComponent("catalog.json")
        bin = root.appendingPathComponent("bin", isDirectory: true)
        migrationBackups = root.appendingPathComponent("migration-backups", isDirectory: true)
    }

    public func skillsDirectory(for tool: ToolID) -> URL {
        switch tool {
        case .codex:
            if let override = environment["SKILL_MANAGER_CODEX_SKILLS_DIR"], !override.isEmpty {
                return URL(fileURLWithPath: override, isDirectory: true)
            }
            return home.appendingPathComponent(".agents/skills", isDirectory: true)
        case .claudeCode:
            if let override = environment["SKILL_MANAGER_CLAUDE_SKILLS_DIR"], !override.isEmpty {
                return URL(fileURLWithPath: override, isDirectory: true)
            }
            return home.appendingPathComponent(".claude/skills", isDirectory: true)
        }
    }

    public func legacySkillsDirectories(for tool: ToolID) -> [URL] {
        switch tool {
        case .codex:
            let legacy = home.appendingPathComponent(".codex/skills", isDirectory: true)
            return legacy.standardizedFileURL == skillsDirectory(for: .codex).standardizedFileURL ? [] : [legacy]
        case .claudeCode:
            return []
        }
    }

    public func sourceDirectory(owner: String, repository: String) -> URL {
        sources
            .appendingPathComponent(Self.safePathComponent(owner), isDirectory: true)
            .appendingPathComponent(Self.safePathComponent(repository), isDirectory: true)
    }

    public static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleaned = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return result.isEmpty ? "unknown" : result
    }
}

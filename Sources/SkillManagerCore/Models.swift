import Foundation

public enum ToolID: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case codex
    case claudeCode = "claude-code"

    public static let displayOrder: [ToolID] = [.codex, .claudeCode]

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        }
    }

    public var symbolName: String {
        switch self {
        case .codex: "terminal"
        case .claudeCode: "sparkles"
        }
    }
}

public enum InstallMode: String, Codable, Hashable, Sendable {
    case lazy
    case managedDirect = "managed-direct"

    public var displayName: String {
        switch self {
        case .lazy: "Lazy"
        case .managedDirect: CoreL10n.choose("托管直装", "Managed Install")
        }
    }
}

public enum DetectedSkillKind: String, Codable, Hashable, Sendable {
    case managedDirect = "managed-direct"
    case unmanagedDirect = "unmanaged-direct"
    case router
    case brokenLink = "broken-link"

    public var displayName: String {
        switch self {
        case .managedDirect: CoreL10n.choose("托管直装", "Managed Install")
        case .unmanagedDirect: CoreL10n.choose("未托管直装", "Unmanaged Install")
        case .router: "Skill Router"
        case .brokenLink: CoreL10n.choose("失效链接", "Broken Link")
        }
    }
}

public struct ManagedSkill: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String
    public var sourceURL: String
    public var repository: String
    public var repositoryPath: String
    public var localPath: String
    public var revision: String
    public var revisionDate: Date?
    public var mode: InstallMode
    public var targets: Set<ToolID>
    public var disabledAt: Date?
    public var installedAt: Date
    public var updatedAt: Date
    public var lastCheckedAt: Date?
    public var checkedRevision: String?
    public var checkedRevisionDate: Date?
    public var updateCheckError: String?

    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        sourceURL: String,
        repository: String,
        repositoryPath: String,
        localPath: String,
        revision: String,
        revisionDate: Date? = nil,
        mode: InstallMode = .lazy,
        targets: Set<ToolID> = [],
        disabledAt: Date? = nil,
        installedAt: Date = Date(),
        updatedAt: Date = Date(),
        lastCheckedAt: Date? = nil,
        checkedRevision: String? = nil,
        checkedRevisionDate: Date? = nil,
        updateCheckError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.sourceURL = sourceURL
        self.repository = repository
        self.repositoryPath = repositoryPath
        self.localPath = localPath
        self.revision = revision
        self.revisionDate = revisionDate
        self.mode = mode
        self.targets = targets
        self.disabledAt = disabledAt
        self.installedAt = installedAt
        self.updatedAt = updatedAt
        self.lastCheckedAt = lastCheckedAt
        self.checkedRevision = checkedRevision
        self.checkedRevisionDate = checkedRevisionDate
        self.updateCheckError = updateCheckError
    }

    public var identityKey: String {
        "\(repository.lowercased())#\(repositoryPath.lowercased())"
    }

    public var isDisabled: Bool { disabledAt != nil }
}

public struct DetectedSkill: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(tool.rawValue):\(entryPath)" }
    public var name: String
    public var description: String
    public var tool: ToolID
    public var entryPath: String
    public var resolvedPath: String
    public var kind: DetectedSkillKind
    public var managedSkillID: UUID?

    public init(
        name: String,
        description: String,
        tool: ToolID,
        entryPath: String,
        resolvedPath: String,
        kind: DetectedSkillKind,
        managedSkillID: UUID? = nil
    ) {
        self.name = name
        self.description = description
        self.tool = tool
        self.entryPath = entryPath
        self.resolvedPath = resolvedPath
        self.kind = kind
        self.managedSkillID = managedSkillID
    }
}

public enum ActivityKind: String, Codable, Hashable, Sendable {
    case imported
    case linked
    case unlinked
    case updated
    case router
    case warning
}

public struct ActivityEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var kind: ActivityKind
    public var title: String
    public var detail: String

    public init(id: UUID = UUID(), date: Date = Date(), kind: ActivityKind, title: String, detail: String) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

public struct RouterState: Codable, Hashable, Sendable {
    public var installedTargets: Set<ToolID>
    public var updatedAt: Date

    public init(installedTargets: Set<ToolID> = [], updatedAt: Date = Date()) {
        self.installedTargets = installedTargets
        self.updatedAt = updatedAt
    }
}

public struct SkillCatalog: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var skills: [ManagedSkill]
    public var router: RouterState
    public var activities: [ActivityEvent]
    public var onboardingCompletedAt: Date?

    public init(
        schemaVersion: Int = 1,
        skills: [ManagedSkill] = [],
        router: RouterState = RouterState(),
        activities: [ActivityEvent] = [],
        onboardingCompletedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.skills = skills
        self.router = router
        self.activities = activities
        self.onboardingCompletedAt = onboardingCompletedAt
    }
}

public enum MigrationChoice: String, CaseIterable, Codable, Hashable, Sendable {
    case managedDirect = "managed-direct"
    case lazy

    public var displayName: String {
        switch self {
        case .managedDirect: CoreL10n.choose("进入主 Skill", "Managed Install")
        case .lazy: CoreL10n.choose("进入 Router", "Router")
        }
    }
}

public struct MigrationInstallation: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(tool.rawValue):\(entryPath)" }
    public var tool: ToolID
    public var entryPath: String

    public init(tool: ToolID, entryPath: String) {
        self.tool = tool
        self.entryPath = entryPath
    }
}

public struct MigrationCandidate: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var resolvedPath: String
    public var installations: [MigrationInstallation]
    public var detectedRepository: String?
    public var detectedRepositoryPath: String?
    public var hasLocalChanges: Bool

    public init(
        id: String,
        name: String,
        description: String,
        resolvedPath: String,
        installations: [MigrationInstallation],
        detectedRepository: String?,
        detectedRepositoryPath: String?,
        hasLocalChanges: Bool
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.resolvedPath = resolvedPath
        self.installations = installations
        self.detectedRepository = detectedRepository
        self.detectedRepositoryPath = detectedRepositoryPath
        self.hasLocalChanges = hasLocalChanges
    }
}

public struct MigrationSelection: Codable, Hashable, Sendable {
    public var candidate: MigrationCandidate
    public var choice: MigrationChoice
    public var repository: String

    public init(candidate: MigrationCandidate, choice: MigrationChoice, repository: String) {
        self.candidate = candidate
        self.choice = choice
        self.repository = repository
    }
}

public struct MigrationResult: Codable, Hashable, Sendable {
    public var managedDirect: Int
    public var lazy: Int
    public var backupRoot: String?

    public init(managedDirect: Int = 0, lazy: Int = 0, backupRoot: String? = nil) {
        self.managedDirect = managedDirect
        self.lazy = lazy
        self.backupRoot = backupRoot
    }
}

public struct SkillCandidate: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(repository)#\(repositoryPath)" }
    public var name: String
    public var description: String
    public var repository: String
    public var repositoryPath: String
    public var sourceURL: String
    public var localPath: String
    public var revision: String
    public var revisionDate: Date?

    public init(
        name: String,
        description: String,
        repository: String,
        repositoryPath: String,
        sourceURL: String,
        localPath: String,
        revision: String,
        revisionDate: Date? = nil
    ) {
        self.name = name
        self.description = description
        self.repository = repository
        self.repositoryPath = repositoryPath
        self.sourceURL = sourceURL
        self.localPath = localPath
        self.revision = revision
        self.revisionDate = revisionDate
    }
}

public enum SkillDiscoverySource: String, Codable, Hashable, Sendable {
    case skillsSh = "skills.sh"
    case github = "GitHub"

    public var displayName: String { rawValue }
}

public struct DiscoveredSkill: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var repository: String
    public var repositoryPath: String?
    public var sourceURL: String
    public var discoverySource: SkillDiscoverySource
    public var installs: Int?

    public init(
        id: String,
        name: String,
        description: String = "",
        repository: String,
        repositoryPath: String? = nil,
        sourceURL: String,
        discoverySource: SkillDiscoverySource,
        installs: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.repository = repository
        self.repositoryPath = repositoryPath
        self.sourceURL = sourceURL
        self.discoverySource = discoverySource
        self.installs = installs
    }

    public var githubURL: String {
        guard let location = try? GitHubLocation.parse(repository) else { return sourceURL }
        guard let repositoryPath, !repositoryPath.isEmpty else { return location.webURL }
        return "\(location.webURL)/tree/HEAD/\(repositoryPath)"
    }
}

public struct SkillDiscoveryOutcome: Hashable, Sendable {
    public var results: [DiscoveredSkill]
    public var errorMessage: String?

    public init(results: [DiscoveredSkill] = [], errorMessage: String? = nil) {
        self.results = results
        self.errorMessage = errorMessage
    }
}

public struct GitHubRevision: Hashable, Sendable {
    public var revision: String
    public var date: Date?

    public init(revision: String, date: Date? = nil) {
        self.revision = revision
        self.date = date
    }
}

public struct RepositoryUpdateCheck: Hashable, Sendable {
    public var repository: String
    public var latestRevision: String?
    public var latestRevisionDate: Date?
    public var hasUpdate: Bool
    public var errorMessage: String?
    public var checkedAt: Date

    public init(
        repository: String,
        latestRevision: String? = nil,
        latestRevisionDate: Date? = nil,
        hasUpdate: Bool = false,
        errorMessage: String? = nil,
        checkedAt: Date = Date()
    ) {
        self.repository = repository
        self.latestRevision = latestRevision
        self.latestRevisionDate = latestRevisionDate
        self.hasUpdate = hasUpdate
        self.errorMessage = errorMessage
        self.checkedAt = checkedAt
    }
}

public struct RouterSearchResult: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String
    public var repository: String
    public var sourceURL: String
    public var skillPath: String
    public var score: Int

    public init(skill: ManagedSkill, score: Int) {
        id = skill.id
        name = skill.name
        description = skill.description
        repository = skill.repository
        sourceURL = skill.sourceURL
        skillPath = URL(fileURLWithPath: skill.localPath).appendingPathComponent("SKILL.md").path
        self.score = score
    }
}

public enum ManagedStateIssueKind: String, Codable, Hashable, Sendable {
    case missingExpectedLink = "missing-expected-link"
    case conflictingEntry = "conflicting-entry"
    case unexpectedManagedLink = "unexpected-managed-link"
    case missingSource = "missing-source"
}

public struct ManagedStateIssue: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(tool.rawValue):\(destinationPath):\(kind.rawValue)" }
    public var managedSkillID: UUID?
    public var name: String
    public var tool: ToolID
    public var destinationPath: String
    public var kind: ManagedStateIssueKind

    public init(
        managedSkillID: UUID?,
        name: String,
        tool: ToolID,
        destinationPath: String,
        kind: ManagedStateIssueKind
    ) {
        self.managedSkillID = managedSkillID
        self.name = name
        self.tool = tool
        self.destinationPath = destinationPath
        self.kind = kind
    }
}

public struct ManagedStateSyncResult: Codable, Hashable, Sendable {
    public var createdLinks: Int
    public var repairedLinks: Int
    public var removedLinks: Int
    public var unchangedLinks: Int

    public init(
        createdLinks: Int = 0,
        repairedLinks: Int = 0,
        removedLinks: Int = 0,
        unchangedLinks: Int = 0
    ) {
        self.createdLinks = createdLinks
        self.repairedLinks = repairedLinks
        self.removedLinks = removedLinks
        self.unchangedLinks = unchangedLinks
    }

    public var changedLinks: Int { createdLinks + repairedLinks + removedLinks }
}

public struct WorkspaceSnapshot: Sendable {
    public var catalog: SkillCatalog
    public var detectedSkills: [DetectedSkill]
    public var managedStateIssues: [ManagedStateIssue]

    public init(
        catalog: SkillCatalog,
        detectedSkills: [DetectedSkill],
        managedStateIssues: [ManagedStateIssue] = []
    ) {
        self.catalog = catalog
        self.detectedSkills = detectedSkills
        self.managedStateIssues = managedStateIssues
    }
}

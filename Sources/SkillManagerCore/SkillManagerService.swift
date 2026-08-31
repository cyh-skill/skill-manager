import Foundation

public enum SkillManagerServiceError: LocalizedError {
    case skillNotFound
    case invalidRouter(String)
    case conflict(String)
    case unsafeRemoval(String)
    case helperUnavailable

    public var errorDescription: String? {
        switch self {
        case .skillNotFound:
            CoreL10n.choose("找不到对应的托管 Skill。", "The managed Skill could not be found.")
        case .invalidRouter(let detail):
            CoreL10n.choose("Router 内容无效：\(detail)", "Invalid Router content: \(detail)")
        case .conflict(let path):
            CoreL10n.choose("目标位置已有其他内容，未覆盖：\(path)", "The destination contains other content and was not overwritten: \(path)")
        case .unsafeRemoval(let path):
            CoreL10n.choose("目标不是由 Skill Manager 创建的链接，拒绝移除：\(path)", "Removal refused because the target is not a Skill Manager link or validated unmanaged entry: \(path)")
        case .helperUnavailable:
            CoreL10n.choose(
                "找不到 skill-manager-cli，无法启用 Router。请先构建完整应用包。",
                "skill-manager-cli could not be found, so Router cannot be enabled. Build the complete app bundle first."
            )
        }
    }
}

public struct SkillManagerService: Sendable {
    public let paths: ManagerPaths
    public let store: CatalogStore
    public let github: GitHubService
    private let trashItem: @Sendable (URL) throws -> URL?

    public init(
        paths: ManagerPaths = ManagerPaths(),
        trashItem: (@Sendable (URL) throws -> URL?)? = nil
    ) {
        self.paths = paths
        store = CatalogStore(paths: paths)
        github = GitHubService(paths: paths)
        self.trashItem = trashItem ?? { url in
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            return resultingURL as URL?
        }
    }

    public func bootstrap(defaultRouterContent: String) throws {
        try store.ensureLayout()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.routerSkill, withIntermediateDirectories: true)
        let skillFile = paths.routerSkill.appendingPathComponent("SKILL.md")
        if !fileManager.fileExists(atPath: skillFile.path) {
            try validateRouter(defaultRouterContent)
            try Data(defaultRouterContent.utf8).write(to: skillFile, options: .atomic)
        }
        if !fileManager.fileExists(atPath: paths.catalog.path) {
            try store.save(SkillCatalog())
        }
    }

    public func snapshot() throws -> WorkspaceSnapshot {
        var catalog = try store.load()
        if backfillRevisionDates(in: &catalog) {
            try store.save(catalog)
        }
        return WorkspaceSnapshot(catalog: catalog, detectedSkills: scanToolDirectories(catalog: catalog))
    }

    public func migrationCandidates() throws -> [MigrationCandidate] {
        let snapshot = try snapshot()
        var unmanaged = snapshot.detectedSkills.filter { $0.kind == .unmanagedDirect }
        let catalog = snapshot.catalog
        for tool in ToolID.allCases {
            for legacyDirectory in paths.legacySkillsDirectories(for: tool) {
                unmanaged.append(contentsOf: scanDirectory(tool: tool, directory: legacyDirectory, catalog: catalog).filter { $0.kind == .unmanagedDirect })
            }
        }
        let grouped = Dictionary(grouping: unmanaged, by: { $0.resolvedPath })
        return grouped.map { resolvedPath, entries in
            let first = entries[0]
            let git = inspectGitSource(at: URL(fileURLWithPath: resolvedPath, isDirectory: true))
            return MigrationCandidate(
                id: resolvedPath,
                name: first.name,
                description: first.description,
                resolvedPath: resolvedPath,
                installations: entries.map { MigrationInstallation(tool: $0.tool, entryPath: $0.entryPath) },
                detectedRepository: git.repository,
                detectedRepositoryPath: git.repositoryPath,
                hasLocalChanges: git.hasLocalChanges
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func applyMigration(
        _ selections: [MigrationSelection],
        helperSource: URL?,
        force: Bool = false
    ) throws -> MigrationResult {
        for selection in selections {
            guard !selection.repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GitHubServiceError.invalidRepository(CoreL10n.choose(
                    "\(selection.candidate.name) 尚未指定 GitHub 仓库",
                    "No GitHub repository was specified for \(selection.candidate.name)"
                ))
            }
            _ = try GitHubLocation.parse(selection.repository)
        }

        var catalog = try store.load()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let batchBackupRoot = paths.migrationBackups.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        var result = MigrationResult()
        var routerTargets = Set<ToolID>()
        var movedItems: [(backup: URL, original: URL)] = []
        var createdLinks: [URL] = []

        do {
            if selections.contains(where: { $0.choice == .lazy }) {
                try installHelperIfNeeded(from: helperSource)
            }

            for selection in selections {
                let githubCandidates = try github.cloneOrUpdate(selection.repository)
                let githubCandidate = try matchGitHubCandidate(selection.candidate, candidates: githubCandidates)
                let skill = registerCandidate(githubCandidate, catalog: &catalog)
                let source = URL(fileURLWithPath: skill.localPath, isDirectory: true).standardizedFileURL

                for installation in selection.candidate.installations {
                    let original = URL(fileURLWithPath: installation.entryPath, isDirectory: true)
                    let backup = batchBackupRoot
                        .appendingPathComponent(installation.tool.rawValue, isDirectory: true)
                        .appendingPathComponent(original.lastPathComponent, isDirectory: true)
                    if fileExistsIncludingSymlink(original) {
                        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                        if fileExistsIncludingSymlink(backup) {
                            guard force else { throw SkillManagerServiceError.conflict(backup.path) }
                            try moveExistingItemToTrash(backup)
                        }
                        try FileManager.default.moveItem(at: original, to: backup)
                        movedItems.append((backup, original))
                    }
                }

                if selection.choice == .managedDirect {
                    for installation in selection.candidate.installations {
                        let destination = paths.skillsDirectory(for: installation.tool)
                            .appendingPathComponent(skill.name, isDirectory: true)
                        try createManagedLink(source: source, destination: destination, force: force)
                        createdLinks.append(destination)
                        if let index = catalog.skills.firstIndex(where: { $0.id == skill.id }) {
                            catalog.skills[index].targets.insert(installation.tool)
                            catalog.skills[index].mode = .managedDirect
                        }
                    }
                    result.managedDirect += 1
                } else {
                    if let index = catalog.skills.firstIndex(where: { $0.id == skill.id }) {
                        catalog.skills[index].targets.removeAll()
                        catalog.skills[index].mode = .lazy
                    }
                    routerTargets.formUnion(selection.candidate.installations.map(\.tool))
                    result.lazy += 1
                }
            }

            if !routerTargets.isEmpty {
                for tool in routerTargets {
                    let destination = paths.skillsDirectory(for: tool).appendingPathComponent("skill-router", isDirectory: true)
                    let existedBefore = fileExistsIncludingSymlink(destination)
                    try createManagedLink(source: paths.routerSkill, destination: destination, force: force)
                    if !existedBefore {
                        createdLinks.append(destination)
                    }
                    catalog.router.installedTargets.insert(tool)
                }
                catalog.router.updatedAt = Date()
            }

            catalog.onboardingCompletedAt = Date()
            result.backupRoot = selections.isEmpty ? nil : batchBackupRoot.path
            store.addingActivity(
                ActivityEvent(
                    kind: .imported,
                    title: CoreL10n.choose("完成初始化迁移", "Initial migration complete"),
                    detail: CoreL10n.choose(
                        "主 Skill \(result.managedDirect) · Router \(result.lazy)",
                        "Managed \(result.managedDirect) · Router \(result.lazy)"
                    )
                ),
                to: &catalog
            )
            try store.save(catalog)
            return result
        } catch {
            for link in createdLinks.reversed() where (try? link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                try? FileManager.default.removeItem(at: link)
            }
            for item in movedItems.reversed() {
                try? FileManager.default.createDirectory(at: item.original.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !fileExistsIncludingSymlink(item.original) {
                    try? FileManager.default.moveItem(at: item.backup, to: item.original)
                }
            }
            throw error
        }
    }

    public func importRepository(_ repository: String) throws -> [ManagedSkill] {
        let candidates = try github.cloneOrUpdate(repository)
        var catalog = try store.load()
        var imported: [ManagedSkill] = []

        for candidate in candidates {
            if let index = catalog.skills.firstIndex(where: {
                $0.repository.caseInsensitiveCompare(candidate.repository) == .orderedSame
                    && $0.repositoryPath.caseInsensitiveCompare(candidate.repositoryPath) == .orderedSame
            }) {
                catalog.skills[index].name = candidate.name
                catalog.skills[index].description = candidate.description
                catalog.skills[index].sourceURL = candidate.sourceURL
                catalog.skills[index].localPath = candidate.localPath
                catalog.skills[index].revision = candidate.revision
                catalog.skills[index].revisionDate = candidate.revisionDate
                catalog.skills[index].updatedAt = Date()
                catalog.skills[index].lastCheckedAt = Date()
                catalog.skills[index].checkedRevision = candidate.revision
                catalog.skills[index].checkedRevisionDate = candidate.revisionDate
                catalog.skills[index].updateCheckError = nil
                imported.append(catalog.skills[index])
            } else {
                var uniqueName = candidate.name
                let duplicateName = catalog.skills.contains { $0.name.caseInsensitiveCompare(uniqueName) == .orderedSame }
                if duplicateName {
                    uniqueName = uniqueManagedName(base: candidate.name, repository: candidate.repository, catalog: catalog)
                }
                let skill = ManagedSkill(
                    name: uniqueName,
                    description: candidate.description,
                    sourceURL: candidate.sourceURL,
                    repository: candidate.repository,
                    repositoryPath: candidate.repositoryPath,
                    localPath: candidate.localPath,
                    revision: candidate.revision,
                    revisionDate: candidate.revisionDate,
                    lastCheckedAt: Date(),
                    checkedRevision: candidate.revision,
                    checkedRevisionDate: candidate.revisionDate
                )
                catalog.skills.append(skill)
                imported.append(skill)
            }
        }
        store.addingActivity(
            ActivityEvent(
                kind: .imported,
                title: CoreL10n.choose(
                    "从 GitHub 导入 \(imported.count) 个 Skill",
                    "Imported \(imported.count) Skills from GitHub"
                ),
                detail: candidates.first?.repository ?? repository
            ),
            to: &catalog
        )
        catalog.skills.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try store.save(catalog)
        return imported
    }

    public func importSkill(
        repository: String,
        repositoryPath: String?,
        skillName: String
    ) throws -> ManagedSkill {
        let candidates = try github.cloneOrUpdate(repository)
        let candidate = try resolveDiscoveredCandidate(
            candidates,
            repositoryPath: repositoryPath,
            skillName: skillName
        )
        var catalog = try store.load()
        let skill = registerCandidate(candidate, catalog: &catalog)
        store.addingActivity(
            ActivityEvent(
                kind: .imported,
                title: CoreL10n.choose("从 GitHub 导入 \(skill.name)", "Imported \(skill.name) from GitHub"),
                detail: "\(candidate.repository) · \(candidate.repositoryPath.isEmpty ? "/" : candidate.repositoryPath)"
            ),
            to: &catalog
        )
        catalog.skills.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try store.save(catalog)
        return skill
    }

    public func updateRepository(for skillID: UUID) throws {
        var catalog = try store.load()
        guard let selected = catalog.skills.first(where: { $0.id == skillID }) else {
            throw SkillManagerServiceError.skillNotFound
        }
        let candidates = try github.updateRepository(selected.repository)
        let candidatesByPath = Dictionary(uniqueKeysWithValues: candidates.map { ($0.repositoryPath.lowercased(), $0) })
        var updatedCount = 0
        for index in catalog.skills.indices where catalog.skills[index].repository.caseInsensitiveCompare(selected.repository) == .orderedSame {
            guard let candidate = candidatesByPath[catalog.skills[index].repositoryPath.lowercased()] else { continue }
            catalog.skills[index].description = candidate.description
            catalog.skills[index].sourceURL = candidate.sourceURL
            catalog.skills[index].localPath = candidate.localPath
            catalog.skills[index].revision = candidate.revision
            catalog.skills[index].revisionDate = candidate.revisionDate
            catalog.skills[index].updatedAt = Date()
            catalog.skills[index].lastCheckedAt = Date()
            catalog.skills[index].checkedRevision = candidate.revision
            catalog.skills[index].checkedRevisionDate = candidate.revisionDate
            catalog.skills[index].updateCheckError = nil
            updatedCount += 1
        }
        store.addingActivity(
            ActivityEvent(
                kind: .updated,
                title: CoreL10n.choose("更新 GitHub 仓库", "Updated GitHub Repository"),
                detail: CoreL10n.choose(
                    "\(selected.repository) · \(updatedCount) 个 Skill",
                    "\(selected.repository) · \(updatedCount) Skills"
                )
            ),
            to: &catalog
        )
        try store.save(catalog)
    }

    public func checkForRepositoryUpdates() throws -> [RepositoryUpdateCheck] {
        var catalog = try store.load()
        let repositories = Dictionary(grouping: catalog.skills, by: { $0.repository.lowercased() })
            .values
            .compactMap(\.first)
            .map(\.repository)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var checks: [RepositoryUpdateCheck] = []

        for repository in repositories {
            let checkedAt = Date()
            let repositorySkills = catalog.skills.filter {
                $0.repository.caseInsensitiveCompare(repository) == .orderedSame
            }
            do {
                let latestVersion = try github.latestVersion(repository)
                checks.append(
                    RepositoryUpdateCheck(
                        repository: repository,
                        latestRevision: latestVersion.revision,
                        latestRevisionDate: latestVersion.date,
                        hasUpdate: repositorySkills.contains { $0.revision != latestVersion.revision },
                        checkedAt: checkedAt
                    )
                )
                for index in catalog.skills.indices where catalog.skills[index].repository.caseInsensitiveCompare(repository) == .orderedSame {
                    catalog.skills[index].lastCheckedAt = checkedAt
                    catalog.skills[index].checkedRevision = latestVersion.revision
                    catalog.skills[index].checkedRevisionDate = latestVersion.date
                    catalog.skills[index].updateCheckError = nil
                }
            } catch {
                let message = error.localizedDescription
                checks.append(
                    RepositoryUpdateCheck(
                        repository: repository,
                        errorMessage: message,
                        checkedAt: checkedAt
                    )
                )
                for index in catalog.skills.indices where catalog.skills[index].repository.caseInsensitiveCompare(repository) == .orderedSame {
                    catalog.skills[index].lastCheckedAt = checkedAt
                    catalog.skills[index].updateCheckError = message
                }
            }
        }

        try store.save(catalog)
        return checks
    }

    public func setSkill(
        _ skillID: UUID,
        installedOn tool: ToolID,
        enabled: Bool,
        force: Bool = false
    ) throws {
        var catalog = try store.load()
        guard let index = catalog.skills.firstIndex(where: { $0.id == skillID }) else {
            throw SkillManagerServiceError.skillNotFound
        }
        let skill = catalog.skills[index]
        let source = URL(fileURLWithPath: skill.localPath, isDirectory: true).standardizedFileURL
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent("SKILL.md").path) else {
            throw SkillManagerServiceError.skillNotFound
        }
        let destination = paths.skillsDirectory(for: tool).appendingPathComponent(skill.name, isDirectory: true)

        if enabled {
            try createManagedLink(source: source, destination: destination, force: force)
            catalog.skills[index].targets.insert(tool)
            catalog.skills[index].mode = .managedDirect
            store.addingActivity(
                ActivityEvent(
                    kind: .linked,
                    title: CoreL10n.choose("托管直装 \(skill.name)", "Managed install: \(skill.name)"),
                    detail: "\(tool.displayName) · \(destination.path)"
                ),
                to: &catalog
            )
        } else {
            try removeManagedLink(destination: destination, expectedSource: source, force: force)
            catalog.skills[index].targets.remove(tool)
            if catalog.skills[index].targets.isEmpty {
                catalog.skills[index].mode = .lazy
            }
            store.addingActivity(
                ActivityEvent(
                    kind: .unlinked,
                    title: CoreL10n.choose("转为 Lazy：\(skill.name)", "Moved to Lazy: \(skill.name)"),
                    detail: tool.displayName
                ),
                to: &catalog
            )
        }
        catalog.skills[index].updatedAt = Date()
        try store.save(catalog)
    }

    public func removeFromManager(_ skillID: UUID, force: Bool = false) throws {
        var catalog = try store.load()
        guard let skill = catalog.skills.first(where: { $0.id == skillID }) else {
            throw SkillManagerServiceError.skillNotFound
        }
        let source = URL(fileURLWithPath: skill.localPath, isDirectory: true).standardizedFileURL
        for tool in skill.targets {
            let destination = paths.skillsDirectory(for: tool).appendingPathComponent(skill.name, isDirectory: true)
            try removeManagedLink(destination: destination, expectedSource: source, force: force)
        }
        catalog.skills.removeAll { $0.id == skillID }
        store.addingActivity(
            ActivityEvent(
                kind: .unlinked,
                title: CoreL10n.choose("移出 Skill Manager：\(skill.name)", "Removed from Skill Manager: \(skill.name)"),
                detail: CoreL10n.choose("GitHub 工作副本保留在磁盘", "The GitHub checkout remains on disk")
            ),
            to: &catalog
        )
        try store.save(catalog)
    }

    public func routerContent() throws -> String {
        try String(contentsOf: paths.routerSkill.appendingPathComponent("SKILL.md"), encoding: .utf8)
    }

    @discardableResult
    public func trashUnmanagedSkill(_ entry: DetectedSkill) throws -> String {
        guard entry.kind == .unmanagedDirect else {
            throw SkillManagerServiceError.unsafeRemoval(entry.entryPath)
        }
        let entryURL = URL(fileURLWithPath: entry.entryPath, isDirectory: true).standardizedFileURL
        let allowedParents = ([paths.skillsDirectory(for: entry.tool)] + paths.legacySkillsDirectories(for: entry.tool))
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        let entryParent = entryURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        guard allowedParents.contains(entryParent) else {
            throw SkillManagerServiceError.unsafeRemoval(entry.entryPath)
        }

        let catalog = try store.load()
        let isCurrentUnmanagedEntry = (
            scanDirectory(tool: entry.tool, directory: entryURL.deletingLastPathComponent(), catalog: catalog)
                .first { $0.id == entry.id && $0.kind == .unmanagedDirect }
        ) != nil
        guard isCurrentUnmanagedEntry, fileExistsIncludingSymlink(entryURL) else {
            throw SkillManagerServiceError.unsafeRemoval(entry.entryPath)
        }

        let resultingURL = try trashItem(entryURL)
        var updatedCatalog = catalog
        store.addingActivity(
            ActivityEvent(
                kind: .unlinked,
                title: CoreL10n.choose("移到废纸篓：\(entry.name)", "Moved to Trash: \(entry.name)"),
                detail: entry.entryPath
            ),
            to: &updatedCatalog
        )
        try store.save(updatedCatalog)
        return resultingURL?.path ?? entry.entryPath
    }

    public func saveRouterContent(_ content: String) throws {
        try validateRouter(content)
        try Data(content.utf8).write(to: paths.routerSkill.appendingPathComponent("SKILL.md"), options: .atomic)
        var catalog = try store.load()
        catalog.router.updatedAt = Date()
        store.addingActivity(
            ActivityEvent(
                kind: .router,
                title: CoreL10n.choose("保存 Skill Router", "Saved Skill Router"),
                detail: CoreL10n.choose("用户自定义内容已更新", "Custom content was updated")
            ),
            to: &catalog
        )
        try store.save(catalog)
    }

    public func setRouter(
        installedOn tool: ToolID,
        enabled: Bool,
        helperSource: URL?,
        force: Bool = false
    ) throws {
        var catalog = try store.load()
        let destination = paths.skillsDirectory(for: tool).appendingPathComponent("skill-router", isDirectory: true)
        if enabled {
            try installHelperIfNeeded(from: helperSource)
            try createManagedLink(source: paths.routerSkill, destination: destination, force: force)
            catalog.router.installedTargets.insert(tool)
            store.addingActivity(
                ActivityEvent(kind: .router, title: CoreL10n.choose("启用 Skill Router", "Enabled Skill Router"), detail: tool.displayName),
                to: &catalog
            )
        } else {
            try removeManagedLink(destination: destination, expectedSource: paths.routerSkill, force: force)
            catalog.router.installedTargets.remove(tool)
            store.addingActivity(
                ActivityEvent(kind: .router, title: CoreL10n.choose("停用 Skill Router", "Disabled Skill Router"), detail: tool.displayName),
                to: &catalog
            )
        }
        catalog.router.updatedAt = Date()
        try store.save(catalog)
    }

    public func installHelperIfNeeded(from source: URL?) throws {
        let destination = paths.bin.appendingPathComponent("skill-manager-cli")
        if let source, FileManager.default.isExecutableFile(atPath: source.path) {
            try store.ensureLayout()
            let temporary = paths.bin.appendingPathComponent(".skill-manager-cli-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: source, to: temporary)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            return
        }
        guard FileManager.default.isExecutableFile(atPath: destination.path) else {
            throw SkillManagerServiceError.helperUnavailable
        }
    }

    private func scanToolDirectories(catalog: SkillCatalog) -> [DetectedSkill] {
        var output: [DetectedSkill] = []
        for tool in ToolID.allCases {
            output.append(contentsOf: scanDirectory(tool: tool, directory: paths.skillsDirectory(for: tool), catalog: catalog))
        }
        return output
    }

    private func scanDirectory(tool: ToolID, directory: URL, catalog: SkillCatalog) -> [DetectedSkill] {
        let fileManager = FileManager.default
        let managedByPath = Dictionary(uniqueKeysWithValues: catalog.skills.map {
            (URL(fileURLWithPath: $0.localPath).resolvingSymlinksInPath().standardizedFileURL.path, $0)
        })
        let routerPath = paths.routerSkill.resolvingSymlinksInPath().standardizedFileURL.path
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }).compactMap { entry in
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true || values?.isSymbolicLink == true else { return nil }
            let resolved = entry.resolvingSymlinksInPath().standardizedFileURL
            let skillFile = resolved.appendingPathComponent("SKILL.md")
            let exists = fileManager.fileExists(atPath: skillFile.path)
            let document = exists ? try? SkillDocumentParser.parse(fileURL: skillFile) : nil
            let kind: DetectedSkillKind
            let managedID: UUID?
            if !exists && values?.isSymbolicLink == true {
                kind = .brokenLink
                managedID = nil
            } else if resolved.path == routerPath {
                kind = .router
                managedID = nil
            } else if let managed = managedByPath[resolved.path] {
                kind = .managedDirect
                managedID = managed.id
            } else {
                kind = .unmanagedDirect
                managedID = nil
            }
            return DetectedSkill(
                name: document?.name ?? entry.lastPathComponent,
                description: document?.description ?? "",
                tool: tool,
                entryPath: entry.path,
                resolvedPath: resolved.path,
                kind: kind,
                managedSkillID: managedID
            )
        }
    }

    private func createManagedLink(source: URL, destination: URL, force: Bool) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileExistsIncludingSymlink(destination) {
            let resolved = destination.resolvingSymlinksInPath().standardizedFileURL
            if resolved.path == source.resolvingSymlinksInPath().standardizedFileURL.path {
                return
            }
            guard force else { throw SkillManagerServiceError.conflict(destination.path) }
            try moveExistingItemToTrash(destination)
        }
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
    }

    private func removeManagedLink(destination: URL, expectedSource: URL, force: Bool) throws {
        let fileManager = FileManager.default
        guard (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else {
            if !fileManager.fileExists(atPath: destination.path) { return }
            guard force else { throw SkillManagerServiceError.unsafeRemoval(destination.path) }
            try moveExistingItemToTrash(destination)
            return
        }
        let resolved = destination.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path == expectedSource.resolvingSymlinksInPath().standardizedFileURL.path else {
            guard force else { throw SkillManagerServiceError.unsafeRemoval(destination.path) }
            try moveExistingItemToTrash(destination)
            return
        }
        try fileManager.removeItem(at: destination)
    }

    private func moveExistingItemToTrash(_ url: URL) throws {
        guard fileExistsIncludingSymlink(url) else { return }
        _ = try trashItem(url)
        guard !fileExistsIncludingSymlink(url) else {
            throw SkillManagerServiceError.conflict(url.path)
        }
    }

    private func validateRouter(_ content: String) throws {
        do {
            let document = try SkillDocumentParser.parse(content: content, fallbackName: "skill-router")
            guard document.name == "skill-router" else {
                throw SkillManagerServiceError.invalidRouter(CoreL10n.choose(
                    "name 必须保持为 skill-router",
                    "name must remain skill-router"
                ))
            }
        } catch let error as SkillManagerServiceError {
            throw error
        } catch {
            throw SkillManagerServiceError.invalidRouter(error.localizedDescription)
        }
    }

    private func uniqueManagedName(base: String, repository: String, catalog: SkillCatalog) -> String {
        let owner = repository.split(separator: "/").first.map(String.init) ?? "github"
        let candidate = SkillDocumentParser.normalizedName("\(owner)-\(base)")
        if !catalog.skills.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) {
            return candidate
        }
        var suffix = 2
        while catalog.skills.contains(where: { $0.name.caseInsensitiveCompare("\(candidate)-\(suffix)") == .orderedSame }) {
            suffix += 1
        }
        return "\(candidate)-\(suffix)"
    }

    private func inspectGitSource(at skillRoot: URL) -> (repository: String?, repositoryPath: String?, hasLocalChanges: Bool) {
        let git = URL(fileURLWithPath: "/usr/bin/git")
        guard let rootResult = try? ProcessRunner.run(
            executable: git,
            arguments: ["rev-parse", "--show-toplevel"],
            workingDirectory: skillRoot,
            allowFailure: true
        ), rootResult.exitCode == 0 else {
            return (nil, nil, false)
        }
        let repositoryRoot = rootResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repositoryRoot.isEmpty else { return (nil, nil, false) }
        let repositoryRootURL = URL(fileURLWithPath: repositoryRoot, isDirectory: true)
        let remoteResult = try? ProcessRunner.run(
            executable: git,
            arguments: ["remote", "get-url", "origin"],
            workingDirectory: repositoryRootURL,
            allowFailure: true
        )
        let remote = remoteResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let location = try? GitHubLocation.parse(remote)
        let rootComponents = repositoryRootURL.standardizedFileURL.pathComponents
        let skillComponents = skillRoot.standardizedFileURL.pathComponents
        let relativePath = skillComponents.dropFirst(rootComponents.count).joined(separator: "/")
        let status = try? ProcessRunner.run(
            executable: git,
            arguments: ["status", "--porcelain", "--", relativePath.isEmpty ? "." : relativePath],
            workingDirectory: repositoryRootURL,
            allowFailure: true
        )
        let dirty = !(status?.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return (location?.fullName, relativePath, dirty)
    }

    private func matchGitHubCandidate(_ local: MigrationCandidate, candidates: [SkillCandidate]) throws -> SkillCandidate {
        if let path = local.detectedRepositoryPath,
           let match = candidates.first(where: { $0.repositoryPath.caseInsensitiveCompare(path) == .orderedSame }) {
            return match
        }
        let nameMatches = candidates.filter { $0.name.caseInsensitiveCompare(local.name) == .orderedSame }
        if nameMatches.count == 1, let match = nameMatches.first {
            return match
        }
        if candidates.count == 1, let match = candidates.first {
            return match
        }
        throw GitHubServiceError.invalidRepository(CoreL10n.choose(
            "\(local.name) 在仓库中没有唯一匹配的 SKILL.md",
            "No unique SKILL.md match for \(local.name) was found in the repository"
        ))
    }

    private func registerCandidate(_ candidate: SkillCandidate, catalog: inout SkillCatalog) -> ManagedSkill {
        if let index = catalog.skills.firstIndex(where: {
            $0.repository.caseInsensitiveCompare(candidate.repository) == .orderedSame
                && $0.repositoryPath.caseInsensitiveCompare(candidate.repositoryPath) == .orderedSame
        }) {
            catalog.skills[index].description = candidate.description
            catalog.skills[index].sourceURL = candidate.sourceURL
            catalog.skills[index].localPath = candidate.localPath
            catalog.skills[index].revision = candidate.revision
            catalog.skills[index].revisionDate = candidate.revisionDate
            catalog.skills[index].updatedAt = Date()
            catalog.skills[index].lastCheckedAt = Date()
            catalog.skills[index].checkedRevision = candidate.revision
            catalog.skills[index].checkedRevisionDate = candidate.revisionDate
            catalog.skills[index].updateCheckError = nil
            return catalog.skills[index]
        }
        var name = candidate.name
        if catalog.skills.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            name = uniqueManagedName(base: candidate.name, repository: candidate.repository, catalog: catalog)
        }
        let skill = ManagedSkill(
            name: name,
            description: candidate.description,
            sourceURL: candidate.sourceURL,
            repository: candidate.repository,
            repositoryPath: candidate.repositoryPath,
            localPath: candidate.localPath,
            revision: candidate.revision,
            revisionDate: candidate.revisionDate,
            lastCheckedAt: Date(),
            checkedRevision: candidate.revision,
            checkedRevisionDate: candidate.revisionDate
        )
        catalog.skills.append(skill)
        return skill
    }

    private func resolveDiscoveredCandidate(
        _ candidates: [SkillCandidate],
        repositoryPath: String?,
        skillName: String
    ) throws -> SkillCandidate {
        let requestedPath = repositoryPath?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let requestedPath, !requestedPath.isEmpty,
           let exact = candidates.first(where: {
               $0.repositoryPath.caseInsensitiveCompare(requestedPath) == .orderedSame
           }) {
            return exact
        }

        let requestedName = skillName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameMatches = candidates.filter {
            $0.name.caseInsensitiveCompare(requestedName) == .orderedSame
                || ($0.repositoryPath as NSString).lastPathComponent.caseInsensitiveCompare(requestedName) == .orderedSame
        }
        if nameMatches.count == 1, let match = nameMatches.first {
            return match
        }
        if candidates.count == 1, let only = candidates.first {
            return only
        }

        let detail = repositoryPath.flatMap { $0.isEmpty ? nil : $0 } ?? skillName
        throw GitHubServiceError.invalidRepository(CoreL10n.choose(
            "仓库中无法唯一定位搜索结果：\(detail)",
            "The search result could not be uniquely located in the repository: \(detail)"
        ))
    }

    private func backfillRevisionDates(in catalog: inout SkillCatalog) -> Bool {
        var changed = false
        var datesByRevision: [String: Date] = [:]
        for index in catalog.skills.indices where catalog.skills[index].revisionDate == nil {
            let skill = catalog.skills[index]
            let key = "\(skill.repository.lowercased())#\(skill.revision)"
            let date = datesByRevision[key] ?? github.revisionDate(skill.revision, repository: skill.repository)
            guard let date else { continue }
            datesByRevision[key] = date
            catalog.skills[index].revisionDate = date
            changed = true
        }
        return changed
    }

    private func fileExistsIncludingSymlink(_ url: URL) -> Bool {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        return (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}

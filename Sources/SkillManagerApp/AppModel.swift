import AppKit
import Foundation
import Observation
import SkillManagerCore

enum NavigationItem: String, CaseIterable, Identifiable {
    case overview
    case library
    case tools
    case router
    case activity
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: L10n.string("概览")
        case .library: L10n.string("全部 Skills")
        case .tools: L10n.string("CLI 管理")
        case .router: "Skill Router"
        case .activity: L10n.string("操作记录")
        case .settings: L10n.string("设置")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .library: "books.vertical"
        case .tools: "terminal"
        case .router: "point.3.connected.trianglepath.dotted"
        case .activity: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

struct AppNotice: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var forceAction: (@MainActor () -> Void)? = nil
}

struct MigrationDraft: Identifiable, Hashable {
    var id: String { candidate.id }
    var candidate: MigrationCandidate
    var choice: MigrationChoice
    var repository: String

    init(candidate: MigrationCandidate) {
        self.candidate = candidate
        choice = .lazy
        repository = candidate.detectedRepository ?? ""
    }
}

@MainActor
@Observable
final class AppModel {
    let paths: ManagerPaths
    let service: SkillManagerService
    let discoveryService: SkillDiscoveryService

    var selection: NavigationItem? = .overview
    var snapshot = WorkspaceSnapshot(catalog: SkillCatalog(), detectedSkills: [])
    var routerContent = ""
    var defaultRouterContent = ""
    var migrationCandidates: [MigrationCandidate] = []
    var githubAuthenticated = false
    var githubStatus = ""
    var repositoryUpdateChecks: [String: RepositoryUpdateCheck] = [:]
    var discoveryQuery = ""
    var skillsShResults: [DiscoveredSkill] = []
    var githubResults: [DiscoveredSkill] = []
    var skillsShSearchError: String?
    var githubSearchError: String?
    var isSearchingSkills = false
    var updatingRepositoryKey: String?
    var isCheckingForUpdates = false
    var isBusy = false
    var busyMessage = ""
    var showOnboarding = false
    var notice: AppNotice?

    init(paths: ManagerPaths = ManagerPaths()) {
        self.paths = paths
        service = SkillManagerService(paths: paths)
        discoveryService = SkillDiscoveryService(paths: paths)
        defaultRouterContent = Self.loadBundledRouter()
        githubStatus = L10n.string("正在检查 GitHub CLI…")
        Task { await initialize() }
    }

    var managedSkills: [ManagedSkill] { snapshot.catalog.skills }
    var lazySkills: [ManagedSkill] { managedSkills.filter { $0.mode == .lazy } }
    var directSkills: [ManagedSkill] { managedSkills.filter { $0.mode == .managedDirect } }
    var unmanagedSkills: [DetectedSkill] { snapshot.detectedSkills.filter { $0.kind == .unmanagedDirect } }
    var unmanagedSkillCount: Int { Set(unmanagedSkills.map(\.resolvedPath)).count }
    var hasBackgroundGitOperation: Bool { updatingRepositoryKey != nil || isCheckingForUpdates }

    func refresh() {
        Task { await reloadWorkspace() }
    }

    func importRepository(_ repository: String, mode: InstallMode) {
        Task {
            await performAllowingForce(localized("正在克隆并扫描 GitHub 仓库…")) { [self] force in
                let imported = try await Task.detached { [service] in
                    let skills = try service.importRepository(repository)
                    if mode == .managedDirect {
                        for skill in skills {
                            for tool in ToolID.allCases {
                                try service.setSkill(skill.id, installedOn: tool, enabled: true, force: force)
                            }
                        }
                    }
                    return skills
                }.value
                await reloadWorkspace(showBusy: false)
                notice = AppNotice(
                    title: localized(mode == .lazy ? "已导入为 Lazy Skill" : "已完成托管直装"),
                    message: mode == .lazy
                        ? localized("从 %@ 导入了 %lld 个有效 Skill。", repository, Int64(imported.count))
                        : localized("从 %@ 导入了 %lld 个有效 Skill，并已统一安装到 Codex 与 Claude Code。", repository, Int64(imported.count))
                )
                selection = .library
            }
        }
    }

    func prepareSkillSearch(_ query: String) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else {
            clearSkillSearch()
            return
        }
        discoveryQuery = normalized
        isSearchingSkills = true
        skillsShResults = []
        githubResults = []
        skillsShSearchError = nil
        githubSearchError = nil
    }

    func searchSkills(_ query: String) async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else {
            clearSkillSearch()
            return
        }
        if discoveryQuery != normalized {
            prepareSkillSearch(normalized)
        }

        let githubTask = Task.detached { [discoveryService] in
            discoveryService.searchGitHub(normalized)
        }
        async let skillsShTask = discoveryService.searchSkillsSh(normalized)
        let skillsSh = await skillsShTask
        let github = await githubTask.value

        guard discoveryQuery == normalized else { return }
        skillsShResults = skillsSh.results
        githubResults = github.results
        skillsShSearchError = skillsSh.errorMessage
        githubSearchError = github.errorMessage
        isSearchingSkills = false
    }

    func clearSkillSearch() {
        discoveryQuery = ""
        skillsShResults = []
        githubResults = []
        skillsShSearchError = nil
        githubSearchError = nil
        isSearchingSkills = false
    }

    func importDiscoveredSkill(_ result: DiscoveredSkill, mode: InstallMode) {
        Task {
            await performAllowingForce(localized("正在通过 GitHub 克隆并安装 %@…", result.name)) { [self] force in
                let imported = try await Task.detached { [service] in
                    let skill = try service.importSkill(
                        repository: result.repository,
                        repositoryPath: result.repositoryPath,
                        skillName: result.name
                    )
                    if mode == .managedDirect {
                        for tool in ToolID.allCases {
                            try service.setSkill(skill.id, installedOn: tool, enabled: true, force: force)
                        }
                    }
                    return skill
                }.value
                await reloadWorkspace(showBusy: false)
                notice = AppNotice(
                    title: localized(mode == .lazy ? "已导入为 Lazy Skill" : "已完成托管直装"),
                    message: localized("%@ 已从 GitHub 仓库 %@ 安装。", imported.name, result.repository)
                )
                selection = .library
            }
        }
    }

    func updateRepository(for skill: ManagedSkill) {
        let key = skill.repository.lowercased()
        guard !hasBackgroundGitOperation else { return }
        updatingRepositoryKey = key
        Task {
            defer { updatingRepositoryKey = nil }
            do {
                try await Task.detached { [service] in
                    try service.updateRepository(for: skill.id)
                }.value
                await reloadWorkspace(showBusy: false)
                let updatedSkill = snapshot.catalog.skills.first {
                    $0.repository.caseInsensitiveCompare(skill.repository) == .orderedSame
                }
                repositoryUpdateChecks[skill.repository.lowercased()] = RepositoryUpdateCheck(
                    repository: skill.repository,
                    latestRevision: updatedSkill?.revision,
                    latestRevisionDate: updatedSkill?.revisionDate,
                    hasUpdate: false
                )
            } catch {
                repositoryUpdateChecks[key] = RepositoryUpdateCheck(
                    repository: skill.repository,
                    errorMessage: error.localizedDescription
                )
                notice = AppNotice(title: localized("后台更新失败"), message: error.localizedDescription)
            }
        }
    }

    func checkForUpdates() {
        guard !hasBackgroundGitOperation else { return }
        isCheckingForUpdates = true
        Task {
            defer { isCheckingForUpdates = false }
            do {
                let checks = try await Task.detached { [service] in
                    try service.checkForRepositoryUpdates()
                }.value
                repositoryUpdateChecks = Dictionary(uniqueKeysWithValues: checks.map {
                    ($0.repository.lowercased(), $0)
                })
                await reloadWorkspace(showBusy: false)
            } catch {
                notice = AppNotice(title: localized("更新检测失败"), message: error.localizedDescription)
            }
        }
    }

    func updateCheck(for skill: ManagedSkill) -> RepositoryUpdateCheck? {
        if let current = repositoryUpdateChecks[skill.repository.lowercased()] {
            return current
        }
        guard let checkedAt = skill.lastCheckedAt else { return nil }
        if let errorMessage = skill.updateCheckError {
            return RepositoryUpdateCheck(
                repository: skill.repository,
                errorMessage: errorMessage,
                checkedAt: checkedAt
            )
        }
        guard let checkedRevision = skill.checkedRevision else { return nil }
        return RepositoryUpdateCheck(
            repository: skill.repository,
            latestRevision: checkedRevision,
            latestRevisionDate: skill.checkedRevisionDate,
            hasUpdate: skill.revision != checkedRevision,
            checkedAt: checkedAt
        )
    }

    func isUpdating(_ skill: ManagedSkill) -> Bool {
        updatingRepositoryKey == skill.repository.lowercased()
    }

    func setSkill(_ skill: ManagedSkill, tool: ToolID, enabled: Bool) {
        Task {
            await performAllowingForce(localized(enabled ? "正在托管直装…" : "正在移回 Lazy 冷库…")) { [self] force in
                try await Task.detached { [service] in
                    try service.setSkill(skill.id, installedOn: tool, enabled: enabled, force: force)
                }.value
                await reloadWorkspace(showBusy: false)
            }
        }
    }

    func removeFromManager(_ skill: ManagedSkill) {
        Task {
            await performAllowingForce(localized("正在移出 Skill Manager…")) { [self] force in
                try await Task.detached { [service] in
                    try service.removeFromManager(skill.id, force: force)
                }.value
                await reloadWorkspace(showBusy: false)
            }
        }
    }

    func trashUnmanagedSkill(_ entry: DetectedSkill) {
        Task {
            await perform(localized("正在将 %@ 移到废纸篓…", entry.name)) {
                _ = try await Task.detached { [service] in
                    try service.trashUnmanagedSkill(entry)
                }.value
                await reloadWorkspace(showBusy: false)
                notice = AppNotice(
                    title: localized("已移到废纸篓"),
                    message: localized("%@ 已从 %@ 移到废纸篓，可在废纸篓恢复。", entry.name, entry.tool.displayName)
                )
            }
        }
    }

    func saveRouter() {
        Task {
            await perform(localized("正在保存 Router…")) {
                let content = routerContent
                try await Task.detached { [service] in
                    try service.saveRouterContent(content)
                }.value
                await reloadWorkspace(showBusy: false)
                notice = AppNotice(
                    title: localized("Router 已保存"),
                    message: localized("Codex 和 Claude Code 的托管链接会立即读取新内容。")
                )
            }
        }
    }

    func resetRouter() {
        routerContent = defaultRouterContent
    }

    func setRouter(tool: ToolID, enabled: Bool) {
        Task {
            await performAllowingForce(localized(enabled ? "正在启用 Router…" : "正在停用 Router…")) { [self] force in
                let helper = helperExecutable()
                try await Task.detached { [service] in
                    try service.setRouter(installedOn: tool, enabled: enabled, helperSource: helper, force: force)
                }.value
                await reloadWorkspace(showBusy: false)
            }
        }
    }

    func runMigration(_ drafts: [MigrationDraft]) {
        let selections = drafts.map {
            MigrationSelection(candidate: $0.candidate, choice: $0.choice, repository: $0.repository)
        }
        Task {
            await performAllowingForce(localized("正在初始化并建立可恢复备份…")) { [self] force in
                let helper = helperExecutable()
                let result = try await Task.detached { [service] in
                    try service.applyMigration(selections, helperSource: helper, force: force)
                }.value
                showOnboarding = false
                await reloadWorkspace(showBusy: false)
                var detail = localized("托管直装 %lld 个，Lazy %lld 个。", Int64(result.managedDirect), Int64(result.lazy))
                if let backupRoot = result.backupRoot {
                    detail += localized("\n原目录备份：%@", backupRoot)
                }
                notice = AppNotice(title: localized("初始化迁移完成"), message: detail)
            }
        }
    }

    func reopenMigration() {
        Task {
            await perform(localized("正在重新扫描现有 Skill…")) {
                let candidates = try await Task.detached { [service] in
                    try service.migrationCandidates()
                }.value
                migrationCandidates = candidates
                if candidates.isEmpty {
                    notice = AppNotice(
                        title: localized("没有待迁移 Skill"),
                        message: localized("Codex 和 Claude Code 目录中没有发现未托管的直装 Skill。")
                    )
                } else {
                    showOnboarding = true
                }
            }
        }
    }

    func dismissOnboarding() {
        showOnboarding = false
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openDirectory(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    func openURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private func initialize() async {
        await perform(localized("正在初始化 Skill Manager…")) {
            let bundledRouter = defaultRouterContent
            let initial = try await Task.detached { [service] in
                try service.bootstrap(defaultRouterContent: bundledRouter)
                let status = service.github.authenticationStatus()
                let snapshot = try service.snapshot()
                let router = try service.routerContent()
                let migration = try service.migrationCandidates()
                return (status, snapshot, router, migration)
            }.value
            githubAuthenticated = initial.0.authenticated
            githubStatus = initial.0.detail
            snapshot = initial.1
            routerContent = initial.2
            migrationCandidates = initial.3
            showOnboarding = snapshot.catalog.onboardingCompletedAt == nil && !migrationCandidates.isEmpty
        }
        let needsPersistedUpdateState = snapshot.catalog.skills.contains {
            $0.checkedRevision == nil && $0.updateCheckError == nil
        }
        if githubAuthenticated && needsPersistedUpdateState {
            checkForUpdates()
        }
    }

    private func reloadWorkspace(showBusy: Bool = true) async {
        if showBusy {
            isBusy = true
            busyMessage = localized("正在刷新本地状态…")
        }
        do {
            let updated = try await Task.detached { [service] in try service.snapshot() }.value
            snapshot = updated
            routerContent = (try? service.routerContent()) ?? routerContent
        } catch {
            notice = AppNotice(title: localized("刷新失败"), message: error.localizedDescription)
        }
        if showBusy {
            isBusy = false
            busyMessage = ""
        }
    }

    private func perform(_ message: String, operation: @MainActor () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        busyMessage = message
        defer {
            isBusy = false
            busyMessage = ""
        }
        do {
            try await operation()
        } catch {
            notice = AppNotice(title: localized("操作未完成"), message: error.localizedDescription)
        }
    }

    private func performAllowingForce(
        _ message: String,
        operation: @escaping @MainActor (Bool) async throws -> Void
    ) async {
        await performForceAttempt(message, force: false, operation: operation)
    }

    private func performForceAttempt(
        _ message: String,
        force: Bool,
        operation: @escaping @MainActor (Bool) async throws -> Void
    ) async {
        guard !isBusy else { return }
        isBusy = true
        busyMessage = message
        defer {
            isBusy = false
            busyMessage = ""
        }
        do {
            try await operation(force)
        } catch {
            guard !force, let path = forceablePath(from: error) else {
                notice = AppNotice(title: localized("操作未完成"), message: error.localizedDescription)
                return
            }
            notice = AppNotice(
                title: localized("确认强制处理？"),
                message: localized(
                    "目标位置已有其他内容。强制处理会将该位置现有内容移到 macOS 废纸篓，然后继续操作：\n%@",
                    path
                ),
                forceAction: { [weak self] in
                    guard let self else { return }
                    Task {
                        await self.performForceAttempt(message, force: true, operation: operation)
                    }
                }
            )
        }
    }

    private func forceablePath(from error: Error) -> String? {
        guard let serviceError = error as? SkillManagerServiceError else { return nil }
        switch serviceError {
        case .conflict(let path), .unsafeRemoval(let path): return path
        default: return nil
        }
    }

    private func helperExecutable() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("skill-manager-cli"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("skill-manager-cli")
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func loadBundledRouter() -> String {
        let candidates = [Bundle.main.resourceURL, Bundle.module.resourceURL]
            .compactMap { $0?.appendingPathComponent("skill-router/SKILL.md") }
        for url in candidates {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        return """
        ---
        name: skill-router
        description: Find and load Lazy Skills from Skill Manager when the current task needs an unavailable capability.
        ---

        Run `~/.skill-manager/bin/skill-manager-cli search "<query>" --json`, choose a result, then run `show` and read its `skillPath`. Do not install it into an agent directory. Inspect bundled scripts and ask for confirmation before first execution.
        """
    }

}

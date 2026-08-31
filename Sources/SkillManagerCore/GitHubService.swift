import Foundation

public struct GitHubLocation: Hashable, Sendable {
    public var owner: String
    public var repository: String

    public var fullName: String { "\(owner)/\(repository)" }
    public var webURL: String { "https://github.com/\(fullName)" }

    public init(owner: String, repository: String) {
        self.owner = owner
        self.repository = repository
    }

    public static func parse(_ input: String) throws -> GitHubLocation {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("git@github.com:") {
            value = String(value.dropFirst("git@github.com:".count))
        } else if let url = URL(string: value), let host = url.host {
            guard host.lowercased() == "github.com" || host.lowercased() == "www.github.com" else {
                throw GitHubServiceError.githubOnly
            }
            value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if value.hasSuffix(".git") {
            value.removeLast(4)
        }
        let parts = value.split(separator: "/").map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw GitHubServiceError.invalidRepository(input)
        }
        return GitHubLocation(owner: parts[0], repository: parts[1])
    }
}

public enum GitHubServiceError: LocalizedError {
    case ghNotInstalled
    case ghNotAuthenticated(String)
    case githubOnly
    case invalidRepository(String)
    case noSkillsFound(String)
    case missingDefaultBranch(String)
    case missingRevision(String)

    public var errorDescription: String? {
        switch self {
        case .ghNotInstalled:
            CoreL10n.choose(
                "未找到 GitHub CLI（gh）。请先安装并运行 gh auth login。",
                "GitHub CLI (gh) was not found. Install it and run gh auth login first."
            )
        case .ghNotAuthenticated(let detail):
            detail.isEmpty
                ? CoreL10n.choose("GitHub CLI 尚未登录，请先运行 gh auth login。", "GitHub CLI is not authenticated. Run gh auth login first.")
                : detail
        case .githubOnly:
            CoreL10n.choose("当前版本只接受 github.com 仓库。", "Only github.com repositories are supported.")
        case .invalidRepository(let value):
            CoreL10n.choose("无法识别 GitHub 仓库：\(value)", "Could not identify the GitHub repository: \(value)")
        case .noSkillsFound(let repository):
            CoreL10n.choose("\(repository) 中没有找到有效的 SKILL.md。", "No valid SKILL.md was found in \(repository).")
        case .missingDefaultBranch(let repository):
            CoreL10n.choose("无法确定 \(repository) 的默认分支。", "Could not determine the default branch for \(repository).")
        case .missingRevision(let repository):
            CoreL10n.choose("GitHub 没有返回 \(repository) 的最新版本。", "GitHub did not return the latest revision for \(repository).")
        }
    }
}

public struct GitHubService: Sendable {
    public let paths: ManagerPaths

    public init(paths: ManagerPaths = ManagerPaths()) {
        self.paths = paths
    }

    public func ghExecutable() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["GH_PATH"],
            environment["PATH"]?.split(separator: ":").map { "\($0)/gh" }.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            paths.home.appendingPathComponent(".local/bin/gh").path
        ].compactMap { $0 }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw GitHubServiceError.ghNotInstalled
        }
        return URL(fileURLWithPath: path)
    }

    public func authenticationStatus() -> (authenticated: Bool, detail: String) {
        do {
            let result = try ProcessRunner.run(
                executable: ghExecutable(),
                arguments: ["auth", "status", "--hostname", "github.com"],
                allowFailure: true
            )
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            return (result.exitCode == 0, detail.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (false, error.localizedDescription)
        }
    }

    public func requireAuthentication() throws {
        let status = authenticationStatus()
        guard status.authenticated else {
            throw GitHubServiceError.ghNotAuthenticated(status.detail)
        }
    }

    public func cloneOrUpdate(_ repositoryInput: String) throws -> [SkillCandidate] {
        try requireAuthentication()
        let location = try GitHubLocation.parse(repositoryInput)
        let checkout = paths.sourceDirectory(owner: location.owner, repository: location.repository)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: checkout.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: checkout.appendingPathComponent(".git").path) {
            try updateCheckout(checkout, repository: location.fullName)
        } else if fileManager.fileExists(atPath: checkout.path) {
            throw GitHubServiceError.invalidRepository(CoreL10n.choose(
                "目标目录不是 Git 仓库：\(checkout.path)",
                "The destination is not a Git repository: \(checkout.path)"
            ))
        } else {
            _ = try ProcessRunner.run(
                executable: ghExecutable(),
                arguments: ["repo", "clone", location.fullName, checkout.path, "--", "--depth=1"]
            )
        }
        return try discoverSkills(in: checkout, location: location)
    }

    public func updateRepository(_ repository: String) throws -> [SkillCandidate] {
        try requireAuthentication()
        let location = try GitHubLocation.parse(repository)
        let checkout = paths.sourceDirectory(owner: location.owner, repository: location.repository)
        guard FileManager.default.fileExists(atPath: checkout.appendingPathComponent(".git").path) else {
            return try cloneOrUpdate(repository)
        }
        try updateCheckout(checkout, repository: location.fullName)
        return try discoverSkills(in: checkout, location: location)
    }

    public func latestRevision(_ repository: String) throws -> String {
        try latestVersion(repository).revision
    }

    public func latestVersion(_ repository: String) throws -> GitHubRevision {
        try requireAuthentication()
        let location = try GitHubLocation.parse(repository)
        let result = try ProcessRunner.run(
            executable: ghExecutable(),
            arguments: ["api", "repos/\(location.fullName)/commits/HEAD", "--jq", "[.sha, .commit.committer.date] | @tsv"]
        )
        let values = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        let revision = values.first ?? ""
        guard !revision.isEmpty else {
            throw GitHubServiceError.missingRevision(location.fullName)
        }
        let date = values.count > 1 ? ISO8601DateFormatter().date(from: values[1]) : nil
        return GitHubRevision(revision: revision, date: date)
    }

    public func revisionDate(_ revision: String, repository: String) -> Date? {
        guard let location = try? GitHubLocation.parse(repository) else { return nil }
        let checkout = paths.sourceDirectory(owner: location.owner, repository: location.repository)
        let result = try? ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["show", "-s", "--format=%cI", revision],
            workingDirectory: checkout,
            allowFailure: true
        )
        guard result?.exitCode == 0 else { return nil }
        let value = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ISO8601DateFormatter().date(from: value)
    }

    private func updateCheckout(_ checkout: URL, repository: String) throws {
        let git = URL(fileURLWithPath: "/usr/bin/git")
        let branchResult = try ProcessRunner.run(
            executable: ghExecutable(),
            arguments: ["api", "repos/\(repository)", "--jq", ".default_branch"]
        )
        let branch = branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            throw GitHubServiceError.missingDefaultBranch(repository)
        }
        let remoteReference = "refs/remotes/origin/\(branch)"
        _ = try ProcessRunner.run(
            executable: git,
            arguments: ["fetch", "--prune", "origin", "+refs/heads/\(branch):\(remoteReference)"],
            workingDirectory: checkout
        )
        _ = try ProcessRunner.run(
            executable: git,
            arguments: ["checkout", "--force", "-B", branch, remoteReference],
            workingDirectory: checkout
        )
        _ = try ProcessRunner.run(
            executable: git,
            arguments: ["reset", "--hard", remoteReference],
            workingDirectory: checkout
        )
        _ = try ProcessRunner.run(
            executable: git,
            arguments: ["branch", "--set-upstream-to=origin/\(branch)", branch],
            workingDirectory: checkout
        )
    }

    private func discoverSkills(in checkout: URL, location: GitHubLocation) throws -> [SkillCandidate] {
        let git = URL(fileURLWithPath: "/usr/bin/git")
        let revisionResult = try ProcessRunner.run(executable: git, arguments: ["rev-parse", "HEAD"], workingDirectory: checkout)
        let revision = revisionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let revisionDate = self.revisionDate(revision, repository: location.fullName)
        let rootPath = checkout.standardizedFileURL.path
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: checkout,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            throw GitHubServiceError.noSkillsFound(location.fullName)
        }

        var candidates: [SkillCandidate] = []
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == ".git" || fileURL.lastPathComponent == ".build" || fileURL.lastPathComponent == "node_modules" {
                enumerator.skipDescendants()
                continue
            }
            guard fileURL.lastPathComponent == "SKILL.md" else { continue }
            let resolved = fileURL.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path == rootPath || resolved.path.hasPrefix(rootPath + "/") else { continue }
            guard let document = try? SkillDocumentParser.parse(fileURL: resolved) else { continue }
            let skillRoot = resolved.deletingLastPathComponent()
            let relativePath = relativePath(from: checkout, to: skillRoot)
            candidates.append(
                SkillCandidate(
                    name: document.name,
                    description: document.description,
                    repository: location.fullName,
                    repositoryPath: relativePath,
                    sourceURL: sourceURL(location: location, revision: revision, relativePath: relativePath),
                    localPath: skillRoot.path,
                    revision: revision,
                    revisionDate: revisionDate
                )
            )
            enumerator.skipDescendants()
        }
        guard !candidates.isEmpty else {
            throw GitHubServiceError.noSkillsFound(location.fullName)
        }
        return candidates.sorted {
            if $0.name == $1.name { return $0.repositoryPath < $1.repositoryPath }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func relativePath(from root: URL, to child: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents
        return childComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private func sourceURL(location: GitHubLocation, revision: String, relativePath: String) -> String {
        guard !relativePath.isEmpty else { return location.webURL }
        return "\(location.webURL)/tree/\(revision)/\(relativePath)"
    }

}

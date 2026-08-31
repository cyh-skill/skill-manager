import Foundation
import Darwin
import XCTest
@testable import SkillManagerCore

final class SkillDocumentParserTests: XCTestCase {
    func testParsesOpenAgentSkillFrontmatter() throws {
        let content = """
        ---
        name: Code_Review
        description: >
          Review a pull request and
          report actionable findings.
        ---

        # Review
        """
        let document = try SkillDocumentParser.parse(content: content, fallbackName: "fallback")
        XCTAssertEqual(document.name, "code-review")
        XCTAssertEqual(document.description, "Review a pull request and report actionable findings.")
    }

    func testRejectsMissingFrontmatter() {
        XCTAssertThrowsError(try SkillDocumentParser.parse(content: "# Skill", fallbackName: "sample"))
    }
}

final class GitHubLocationTests: XCTestCase {
    func testParsesHTTPSAndSSHLocations() throws {
        XCTAssertEqual(try GitHubLocation.parse("https://github.com/openai/skills.git").fullName, "openai/skills")
        XCTAssertEqual(try GitHubLocation.parse("git@github.com:anthropics/skills.git").fullName, "anthropics/skills")
        XCTAssertEqual(try GitHubLocation.parse("owner/repository").fullName, "owner/repository")
    }

    func testRejectsNonGitHubHost() {
        XCTAssertThrowsError(try GitHubLocation.parse("https://gitlab.com/owner/repository"))
    }

    func testReadsLatestRevisionThroughAuthenticatedGitHubCLI() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("github-service-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let fakeGH = sandbox.appendingPathComponent("gh")
        let script = """
        #!/bin/sh
        if [ "$1" = "auth" ]; then
          exit 0
        fi
        if [ "$1" = "api" ] && [ "$2" = "repos/owner/repository/commits/HEAD" ]; then
          printf 'def456\t2026-08-31T05:48:25Z\n'
          exit 0
        fi
        exit 23
        """
        try script.write(to: fakeGH, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGH.path)

        let previousGHPath = ProcessInfo.processInfo.environment["GH_PATH"]
        setenv("GH_PATH", fakeGH.path, 1)
        defer {
            if let previousGHPath { setenv("GH_PATH", previousGHPath, 1) } else { unsetenv("GH_PATH") }
        }

        let paths = ManagerPaths(environment: ["HOME": sandbox.path])
        let version = try GitHubService(paths: paths).latestVersion("owner/repository")
        XCTAssertEqual(version.revision, "def456")
        XCTAssertNotNil(version.date)
    }

    func testUpdateForceResetsDeletedFeatureBranchToRemoteDefault() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("github-force-reset-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let git = URL(fileURLWithPath: "/usr/bin/git")
        let upstream = sandbox.appendingPathComponent("upstream", isDirectory: true)
        let remote = sandbox.appendingPathComponent("remote.git", isDirectory: true)
        try FileManager.default.createDirectory(at: upstream, withIntermediateDirectories: true)
        _ = try ProcessRunner.run(executable: git, arguments: ["init", "-b", "main"], workingDirectory: upstream)
        _ = try ProcessRunner.run(executable: git, arguments: ["config", "user.email", "tests@example.com"], workingDirectory: upstream)
        _ = try ProcessRunner.run(executable: git, arguments: ["config", "user.name", "Skill Manager Tests"], workingDirectory: upstream)
        try FileManager.default.createDirectory(at: upstream.appendingPathComponent("skills/sample"), withIntermediateDirectories: true)
        let skillFile = upstream.appendingPathComponent("skills/sample/SKILL.md")
        try "---\nname: sample\ndescription: Initial\n---\n".write(to: skillFile, atomically: true, encoding: .utf8)
        _ = try ProcessRunner.run(executable: git, arguments: ["add", "."], workingDirectory: upstream)
        _ = try ProcessRunner.run(executable: git, arguments: ["commit", "-m", "initial"], workingDirectory: upstream)
        _ = try ProcessRunner.run(executable: git, arguments: ["clone", "--bare", upstream.path, remote.path])

        let paths = ManagerPaths(environment: [
            "HOME": sandbox.path,
            "SKILL_MANAGER_HOME": sandbox.appendingPathComponent("manager").path
        ])
        let checkout = paths.sourceDirectory(owner: "owner", repository: "repository")
        try FileManager.default.createDirectory(at: checkout.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try ProcessRunner.run(executable: git, arguments: ["clone", remote.path, checkout.path])
        _ = try ProcessRunner.run(executable: git, arguments: ["checkout", "-b", "feat/extension-lifecycle"], workingDirectory: checkout)
        try "---\nname: sample\ndescription: Dirty local copy\n---\n".write(
            to: checkout.appendingPathComponent("skills/sample/SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        try "---\nname: sample\ndescription: Updated upstream\n---\n".write(to: skillFile, atomically: true, encoding: .utf8)
        _ = try ProcessRunner.run(executable: git, arguments: ["add", "."], workingDirectory: upstream)
        _ = try ProcessRunner.run(executable: git, arguments: ["commit", "-m", "update"], workingDirectory: upstream)
        _ = try ProcessRunner.run(executable: git, arguments: ["push", remote.path, "main"], workingDirectory: upstream)

        let fakeGH = sandbox.appendingPathComponent("gh")
        let script = """
        #!/bin/sh
        if [ "$1" = "auth" ]; then
          exit 0
        fi
        if [ "$1" = "api" ] && [ "$2" = "repos/owner/repository" ]; then
          printf 'main\n'
          exit 0
        fi
        exit 23
        """
        try script.write(to: fakeGH, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGH.path)

        let previousGHPath = ProcessInfo.processInfo.environment["GH_PATH"]
        setenv("GH_PATH", fakeGH.path, 1)
        defer {
            if let previousGHPath { setenv("GH_PATH", previousGHPath, 1) } else { unsetenv("GH_PATH") }
        }

        let candidates = try GitHubService(paths: paths).updateRepository("owner/repository")
        let branch = try ProcessRunner.run(executable: git, arguments: ["branch", "--show-current"], workingDirectory: checkout)
        let head = try ProcessRunner.run(executable: git, arguments: ["rev-parse", "HEAD"], workingDirectory: checkout)
        let remoteHead = try ProcessRunner.run(executable: git, arguments: ["rev-parse", "refs/remotes/origin/main"], workingDirectory: checkout)

        XCTAssertEqual(branch.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "main")
        XCTAssertEqual(head.stdout, remoteHead.stdout)
        XCTAssertEqual(candidates.first?.description, "Updated upstream")
        XCTAssertTrue(try ProcessRunner.run(executable: git, arguments: ["status", "--porcelain"], workingDirectory: checkout).stdout.isEmpty)
    }
}

final class SkillDiscoveryServiceTests: XCTestCase {
    func testDecodesSkillsShResultsAndKeepsGitHubSourcesOnly() throws {
        let data = Data(
            """
            {
              "skills": [
                {
                  "id": "anthropics/skills/pdf",
                  "skillId": "pdf",
                  "name": "pdf",
                  "installs": 187667,
                  "source": "anthropics/skills"
                },
                {
                  "id": "example.com/private",
                  "skillId": "private",
                  "name": "private",
                  "installs": 2,
                  "source": "example.com"
                }
              ]
            }
            """.utf8
        )

        let results = try SkillDiscoveryService.decodeSkillsSh(data)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].repository, "anthropics/skills")
        XCTAssertEqual(results[0].installs, 187667)
        XCTAssertEqual(results[0].discoverySource, .skillsSh)
    }

    func testDecodesGitHubCodeSearchWithExactSkillPath() throws {
        let data = Data(
            """
            [
              {
                "path": "skills/productivity/pdf/SKILL.md",
                "repository": { "nameWithOwner": "example/skills" },
                "url": "https://github.com/example/skills/blob/abc/skills/productivity/pdf/SKILL.md"
              }
            ]
            """.utf8
        )

        let results = try SkillDiscoveryService.decodeGitHub(data)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "pdf")
        XCTAssertEqual(results[0].repository, "example/skills")
        XCTAssertEqual(results[0].repositoryPath, "skills/productivity/pdf")
        XCTAssertEqual(results[0].discoverySource, .github)
    }
}

final class RouterSearchTests: XCTestCase {
    func testSearchOnlyReturnsLazySkillsInRelevanceOrder() {
        let catalog = SkillCatalog(skills: [
            ManagedSkill(
                name: "pdf-tools",
                description: "Create and inspect PDF documents",
                sourceURL: "https://github.com/example/skills/tree/main/pdf-tools",
                repository: "example/skills",
                repositoryPath: "pdf-tools",
                localPath: "/tmp/pdf-tools",
                revision: "abc"
            ),
            ManagedSkill(
                name: "document-tools",
                description: "Edit office documents and sometimes inspect PDF files",
                sourceURL: "https://github.com/example/skills/tree/main/document-tools",
                repository: "example/skills",
                repositoryPath: "document-tools",
                localPath: "/tmp/document-tools",
                revision: "abc"
            ),
            ManagedSkill(
                name: "pdf-direct",
                description: "Direct PDF workflow",
                sourceURL: "https://github.com/example/skills/tree/main/pdf-direct",
                repository: "example/skills",
                repositoryPath: "pdf-direct",
                localPath: "/tmp/pdf-direct",
                revision: "abc",
                mode: .managedDirect,
                targets: [.codex]
            )
        ])

        let results = RouterSearch.search(query: "pdf", catalog: catalog)
        XCTAssertEqual(results.map(\.name), ["pdf-tools", "document-tools"])
        XCTAssertFalse(results.contains { $0.name == "pdf-direct" })
    }
}

final class SkillManagerServiceTests: XCTestCase {
    private var sandbox: URL!
    private var paths: ManagerPaths!
    private var service: SkillManagerService!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("skill-manager-tests-\(UUID().uuidString)", isDirectory: true)
        let home = sandbox.appendingPathComponent("home", isDirectory: true)
        let manager = sandbox.appendingPathComponent("manager", isDirectory: true)
        let codex = sandbox.appendingPathComponent("codex-skills", isDirectory: true)
        let claude = sandbox.appendingPathComponent("claude-skills", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        paths = ManagerPaths(environment: [
            "HOME": home.path,
            "SKILL_MANAGER_HOME": manager.path,
            "SKILL_MANAGER_CODEX_SKILLS_DIR": codex.path,
            "SKILL_MANAGER_CLAUDE_SKILLS_DIR": claude.path
        ])
        service = SkillManagerService(paths: paths)
        try service.bootstrap(defaultRouterContent: Self.routerContent)
    }

    override func tearDownWithError() throws {
        if let sandbox {
            try? FileManager.default.removeItem(at: sandbox)
        }
    }

    func testManagedDirectLinkLifecycle() throws {
        let skillRoot = paths.sources.appendingPathComponent("owner/repo/sample", isDirectory: true)
        try FileManager.default.createDirectory(at: skillRoot, withIntermediateDirectories: true)
        try Self.skillContent(name: "sample").write(
            to: skillRoot.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        var catalog = try service.store.load()
        let skill = ManagedSkill(
            name: "sample",
            description: "Sample workflow",
            sourceURL: "https://github.com/owner/repo/tree/main/sample",
            repository: "owner/repo",
            repositoryPath: "sample",
            localPath: skillRoot.path,
            revision: "abc123"
        )
        catalog.skills = [skill]
        try service.store.save(catalog)

        try service.setSkill(skill.id, installedOn: .codex, enabled: true)
        let entry = paths.skillsDirectory(for: .codex).appendingPathComponent("sample")
        XCTAssertTrue(try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        XCTAssertEqual(entry.resolvingSymlinksInPath().standardizedFileURL.path, skillRoot.standardizedFileURL.path)
        XCTAssertEqual(try service.store.load().skills[0].mode, .managedDirect)

        try service.setSkill(skill.id, installedOn: .codex, enabled: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: entry.path))
        XCTAssertEqual(try service.store.load().skills[0].mode, .lazy)
    }

    func testBootstrapNeverReplacesExistingRouterContent() throws {
        let customized = Self.routerContent + "\nKeep this user rule.\n"
        try service.saveRouterContent(customized)

        try service.bootstrap(defaultRouterContent: """
        ---
        name: skill-router
        description: A different bundled default.
        ---

        Do something different.
        """)

        XCTAssertEqual(try service.routerContent(), customized)
    }

    func testForceManagedLinkMovesConflictingEntryToRecoverableTrash() throws {
        let forcedTrash = sandbox.appendingPathComponent("forced-trash", isDirectory: true)
        let forcedService = SkillManagerService(paths: paths) { source in
            let result = forcedTrash
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(source.lastPathComponent, isDirectory: true)
            try FileManager.default.createDirectory(at: result.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: source, to: result)
            return result
        }
        let skillRoot = paths.sources.appendingPathComponent("owner/repo/sample", isDirectory: true)
        try FileManager.default.createDirectory(at: skillRoot, withIntermediateDirectories: true)
        try Self.skillContent(name: "sample").write(
            to: skillRoot.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let skill = ManagedSkill(
            name: "sample",
            description: "Sample workflow",
            sourceURL: "https://github.com/owner/repo/tree/main/sample",
            repository: "owner/repo",
            repositoryPath: "sample",
            localPath: skillRoot.path,
            revision: "abc123"
        )
        var catalog = try forcedService.store.load()
        catalog.skills = [skill]
        try forcedService.store.save(catalog)

        let entry = paths.skillsDirectory(for: .codex).appendingPathComponent("sample", isDirectory: true)
        try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
        try "keep me".write(to: entry.appendingPathComponent("existing.txt"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try forcedService.setSkill(skill.id, installedOn: .codex, enabled: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: entry.appendingPathComponent("existing.txt").path))

        try forcedService.setSkill(skill.id, installedOn: .codex, enabled: true, force: true)
        XCTAssertEqual(try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
        XCTAssertEqual(entry.resolvingSymlinksInPath().standardizedFileURL.path, skillRoot.standardizedFileURL.path)

        try FileManager.default.removeItem(at: entry)
        try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
        try "keep this too".write(to: entry.appendingPathComponent("replacement.txt"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try forcedService.setSkill(skill.id, installedOn: .codex, enabled: false))

        try forcedService.setSkill(skill.id, installedOn: .codex, enabled: false, force: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: entry.path))
        let trashedNames = Set(
            (FileManager.default.enumerator(at: forcedTrash, includingPropertiesForKeys: nil)?
                .compactMap { ($0 as? URL)?.lastPathComponent }) ?? []
        )
        XCTAssertTrue(trashedNames.contains("existing.txt"))
        XCTAssertTrue(trashedNames.contains("replacement.txt"))
        XCTAssertEqual(try forcedService.store.load().skills[0].mode, .lazy)
    }

    func testTrashUnmanagedSkillOnlyMovesValidatedCurrentEntry() throws {
        let entryURL = paths.skillsDirectory(for: .codex).appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: entryURL, withIntermediateDirectories: true)
        try Self.skillContent(name: "legacy").write(
            to: entryURL.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let movedURL = sandbox.appendingPathComponent("test-trash/legacy", isDirectory: true)
        let trashingService = SkillManagerService(paths: paths) { source in
            try FileManager.default.createDirectory(at: movedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: source, to: movedURL)
            return movedURL
        }
        let expectedEntryPath = entryURL.resolvingSymlinksInPath().standardizedFileURL.path
        let entry = try XCTUnwrap(
            trashingService.snapshot().detectedSkills.first {
                URL(fileURLWithPath: $0.entryPath).resolvingSymlinksInPath().standardizedFileURL.path == expectedEntryPath
            }
        )

        XCTAssertEqual(try trashingService.trashUnmanagedSkill(entry), movedURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: entryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.appendingPathComponent("SKILL.md").path))
        XCTAssertThrowsError(try trashingService.trashUnmanagedSkill(entry))
    }

    func testDiscoveredInstallRegistersOnlySelectedGitHubSkill() throws {
        let fixture = sandbox.appendingPathComponent("fixture-discovery", isDirectory: true)
        for name in ["first", "second"] {
            let skillDirectory = fixture.appendingPathComponent("skills/\(name)", isDirectory: true)
            try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
            try Self.skillContent(name: name).write(
                to: skillDirectory.appendingPathComponent("SKILL.md"),
                atomically: true,
                encoding: .utf8
            )
        }
        let git = URL(fileURLWithPath: "/usr/bin/git")
        _ = try ProcessRunner.run(executable: git, arguments: ["init"], workingDirectory: fixture)
        _ = try ProcessRunner.run(executable: git, arguments: ["config", "user.email", "tests@example.com"], workingDirectory: fixture)
        _ = try ProcessRunner.run(executable: git, arguments: ["config", "user.name", "Skill Manager Tests"], workingDirectory: fixture)
        _ = try ProcessRunner.run(executable: git, arguments: ["add", "."], workingDirectory: fixture)
        _ = try ProcessRunner.run(executable: git, arguments: ["commit", "-m", "fixture"], workingDirectory: fixture)

        let fakeGH = sandbox.appendingPathComponent("fake-gh-discovery")
        let script = """
        #!/bin/sh
        if [ "$1" = "auth" ]; then
          exit 0
        fi
        if [ "$1" = "repo" ] && [ "$2" = "clone" ]; then
          exec /usr/bin/git clone "$SKILL_MANAGER_TEST_DISCOVERY_FIXTURE" "$4"
        fi
        exit 23
        """
        try script.write(to: fakeGH, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGH.path)

        let previousGHPath = ProcessInfo.processInfo.environment["GH_PATH"]
        let previousFixture = ProcessInfo.processInfo.environment["SKILL_MANAGER_TEST_DISCOVERY_FIXTURE"]
        setenv("GH_PATH", fakeGH.path, 1)
        setenv("SKILL_MANAGER_TEST_DISCOVERY_FIXTURE", fixture.path, 1)
        defer {
            if let previousGHPath { setenv("GH_PATH", previousGHPath, 1) } else { unsetenv("GH_PATH") }
            if let previousFixture { setenv("SKILL_MANAGER_TEST_DISCOVERY_FIXTURE", previousFixture, 1) } else { unsetenv("SKILL_MANAGER_TEST_DISCOVERY_FIXTURE") }
        }

        let imported = try service.importSkill(
            repository: "owner/discovery",
            repositoryPath: "skills/second",
            skillName: "second"
        )
        let catalog = try service.store.load()
        XCTAssertEqual(imported.name, "second")
        XCTAssertEqual(imported.repositoryPath, "skills/second")
        XCTAssertEqual(catalog.skills.map(\.name), ["second"])
    }

    func testMigrationScanDeduplicatesSharedResolvedPath() throws {
        let source = sandbox.appendingPathComponent("legacy-repo/skills/shared", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Self.skillContent(name: "shared").write(
            to: source.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let git = URL(fileURLWithPath: "/usr/bin/git")
        _ = try ProcessRunner.run(executable: git, arguments: ["init"], workingDirectory: source.deletingLastPathComponent().deletingLastPathComponent())
        _ = try ProcessRunner.run(
            executable: git,
            arguments: ["remote", "add", "origin", "https://github.com/owner/legacy-skills.git"],
            workingDirectory: source.deletingLastPathComponent().deletingLastPathComponent()
        )
        for tool in ToolID.allCases {
            let directory = paths.skillsDirectory(for: tool)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("shared"), withDestinationURL: source)
        }

        let candidates = try service.migrationCandidates()
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].installations.count, 2)
        XCTAssertEqual(candidates[0].detectedRepository, "owner/legacy-skills")
        XCTAssertEqual(Set(candidates[0].installations.map(\.tool)), Set(ToolID.allCases))
    }

    func testMigrationRollsBackEarlierItemsWhenLaterCloneFails() throws {
        let fixture = sandbox.appendingPathComponent("fixture-good", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        try Self.skillContent(name: "sample").write(
            to: fixture.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let git = URL(fileURLWithPath: "/usr/bin/git")
        _ = try ProcessRunner.run(executable: git, arguments: ["init"], workingDirectory: fixture)
        _ = try ProcessRunner.run(executable: git, arguments: ["config", "user.email", "tests@example.com"], workingDirectory: fixture)
        _ = try ProcessRunner.run(executable: git, arguments: ["config", "user.name", "Skill Manager Tests"], workingDirectory: fixture)
        _ = try ProcessRunner.run(executable: git, arguments: ["add", "SKILL.md"], workingDirectory: fixture)
        _ = try ProcessRunner.run(executable: git, arguments: ["commit", "-m", "fixture"], workingDirectory: fixture)

        let fakeGH = sandbox.appendingPathComponent("fake-gh")
        let script = """
        #!/bin/sh
        if [ "$1" = "auth" ]; then
          exit 0
        fi
        if [ "$1" = "repo" ] && [ "$2" = "clone" ]; then
          if [ "$3" = "owner/good" ]; then
            exec /usr/bin/git clone "$SKILL_MANAGER_TEST_FIXTURE" "$4"
          fi
          exit 23
        fi
        exit 23
        """
        try script.write(to: fakeGH, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGH.path)

        let previousGHPath = ProcessInfo.processInfo.environment["GH_PATH"]
        let previousFixture = ProcessInfo.processInfo.environment["SKILL_MANAGER_TEST_FIXTURE"]
        setenv("GH_PATH", fakeGH.path, 1)
        setenv("SKILL_MANAGER_TEST_FIXTURE", fixture.path, 1)
        defer {
            if let previousGHPath { setenv("GH_PATH", previousGHPath, 1) } else { unsetenv("GH_PATH") }
            if let previousFixture { setenv("SKILL_MANAGER_TEST_FIXTURE", previousFixture, 1) } else { unsetenv("SKILL_MANAGER_TEST_FIXTURE") }
        }

        let firstEntry = paths.skillsDirectory(for: .codex).appendingPathComponent("sample", isDirectory: true)
        let secondEntry = paths.skillsDirectory(for: .claudeCode).appendingPathComponent("second", isDirectory: true)
        for (entry, name) in [(firstEntry, "sample"), (secondEntry, "second")] {
            try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
            try Self.skillContent(name: name).write(
                to: entry.appendingPathComponent("SKILL.md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let selections = [
            MigrationSelection(
                candidate: MigrationCandidate(
                    id: firstEntry.path,
                    name: "sample",
                    description: "Sample workflow",
                    resolvedPath: firstEntry.path,
                    installations: [MigrationInstallation(tool: .codex, entryPath: firstEntry.path)],
                    detectedRepository: nil,
                    detectedRepositoryPath: nil,
                    hasLocalChanges: false
                ),
                choice: .managedDirect,
                repository: "owner/good"
            ),
            MigrationSelection(
                candidate: MigrationCandidate(
                    id: secondEntry.path,
                    name: "second",
                    description: "Sample workflow",
                    resolvedPath: secondEntry.path,
                    installations: [MigrationInstallation(tool: .claudeCode, entryPath: secondEntry.path)],
                    detectedRepository: nil,
                    detectedRepositoryPath: nil,
                    hasLocalChanges: false
                ),
                choice: .managedDirect,
                repository: "owner/fail"
            )
        ]

        XCTAssertThrowsError(try service.applyMigration(selections, helperSource: nil))
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstEntry.appendingPathComponent("SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondEntry.appendingPathComponent("SKILL.md").path))
        XCTAssertNotEqual(try firstEntry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
        let catalog = try service.store.load()
        XCTAssertTrue(catalog.skills.isEmpty)
        XCTAssertNil(catalog.onboardingCompletedAt)
    }

    private static var routerContent: String {
        """
        ---
        name: skill-router
        description: Find a Lazy Skill when a task requires one.
        ---

        Search the cold library.
        """
    }

    private static func skillContent(name: String) -> String {
        """
        ---
        name: \(name)
        description: Sample workflow
        ---

        Follow the sample workflow.
        """
    }
}

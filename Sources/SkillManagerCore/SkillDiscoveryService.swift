import Foundation

public struct SkillDiscoveryService: Sendable {
    private struct SkillsShResponse: Decodable {
        var skills: [SkillsShSkill]
    }

    private struct SkillsShSkill: Decodable {
        var id: String
        var skillID: String?
        var name: String
        var installs: Int?
        var source: String

        enum CodingKeys: String, CodingKey {
            case id
            case skillID = "skillId"
            case name
            case installs
            case source
        }
    }

    private struct SkillsShLeaderboardSkill: Decodable {
        var source: String
        var skillID: String
        var name: String
        var installs: Int

        enum CodingKeys: String, CodingKey {
            case source
            case skillID = "skillId"
            case name
            case installs
        }
    }

    private struct GitHubSearchItem: Decodable {
        var path: String
        var repository: GitHubSearchRepository
        var url: String
    }

    private struct GitHubSearchRepository: Decodable {
        var nameWithOwner: String
    }

    public let github: GitHubService

    public init(paths: ManagerPaths = ManagerPaths()) {
        github = GitHubService(paths: paths)
    }

    public func fetchSkillsShLeaderboard(limit: Int = 30) async -> SkillDiscoveryOutcome {
        guard let url = URL(string: "https://www.skills.sh/") else {
            return SkillDiscoveryOutcome(errorMessage: CoreL10n.choose(
                "无法创建 skills.sh 榜单地址。",
                "Could not create the skills.sh leaderboard URL."
            ))
        }

        do {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                return SkillDiscoveryOutcome(errorMessage: CoreL10n.choose(
                    "skills.sh 榜单加载失败（HTTP \(status)）。",
                    "skills.sh leaderboard failed to load (HTTP \(status))."
                ))
            }
            let results = try Self.decodeSkillsShLeaderboard(data, limit: limit)
            guard !results.isEmpty else {
                return SkillDiscoveryOutcome(errorMessage: CoreL10n.choose(
                    "skills.sh 榜单暂时没有可用结果。",
                    "The skills.sh leaderboard has no available results."
                ))
            }
            return SkillDiscoveryOutcome(results: results)
        } catch is CancellationError {
            return SkillDiscoveryOutcome()
        } catch {
            return SkillDiscoveryOutcome(errorMessage: error.localizedDescription)
        }
    }

    public func searchSkillsSh(_ query: String, limit: Int = 20) async -> SkillDiscoveryOutcome {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else { return SkillDiscoveryOutcome() }
        guard var components = URLComponents(string: "https://skills.sh/api/search") else {
            return SkillDiscoveryOutcome(errorMessage: CoreL10n.choose("无法创建 skills.sh 搜索地址。", "Could not create the skills.sh search URL."))
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: normalized),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else {
            return SkillDiscoveryOutcome(errorMessage: CoreL10n.choose("无法创建 skills.sh 搜索地址。", "Could not create the skills.sh search URL."))
        }

        do {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                return SkillDiscoveryOutcome(errorMessage: CoreL10n.choose(
                    "skills.sh 搜索失败（HTTP \(status)）。",
                    "skills.sh search failed (HTTP \(status))."
                ))
            }
            return SkillDiscoveryOutcome(results: try Self.decodeSkillsSh(data))
        } catch is CancellationError {
            return SkillDiscoveryOutcome()
        } catch {
            return SkillDiscoveryOutcome(errorMessage: error.localizedDescription)
        }
    }

    public func searchGitHub(_ query: String, limit: Int = 20) -> SkillDiscoveryOutcome {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else { return SkillDiscoveryOutcome() }
        do {
            try github.requireAuthentication()
            let result = try ProcessRunner.run(
                executable: github.ghExecutable(),
                arguments: [
                    "search", "code", normalized,
                    "--filename", "SKILL.md",
                    "--limit", String(limit),
                    "--json", "path,repository,url"
                ]
            )
            return SkillDiscoveryOutcome(results: try Self.decodeGitHub(result.stdout.data(using: .utf8) ?? Data()))
        } catch {
            return SkillDiscoveryOutcome(errorMessage: error.localizedDescription)
        }
    }

    static func decodeSkillsSh(_ data: Data) throws -> [DiscoveredSkill] {
        let response = try JSONDecoder().decode(SkillsShResponse.self, from: data)
        return response.skills.compactMap { skill in
            guard let repository = try? GitHubLocation.parse(skill.source).fullName else { return nil }
            let primaryName = skill.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackName = skill.skillID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = primaryName.isEmpty ? fallbackName : primaryName
            guard !name.isEmpty else { return nil }
            return DiscoveredSkill(
                id: "skills.sh:\(skill.id)",
                name: name,
                repository: repository,
                repositoryPath: nil,
                sourceURL: "https://skills.sh/\(skill.id)",
                discoverySource: .skillsSh,
                installs: skill.installs
            )
        }
    }

    static func decodeSkillsShLeaderboard(_ data: Data, limit: Int) throws -> [DiscoveredSkill] {
        guard limit > 0, let html = String(data: data, encoding: .utf8) else { return [] }
        let startMarker = #"\"initialSkills\":["#
        let endMarker = #"],\"totalSkills\":"#
        guard let markerRange = html.range(of: startMarker),
              let endRange = html.range(of: endMarker, range: markerRange.upperBound ..< html.endIndex) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "skills.sh leaderboard payload was not found"
            ))
        }

        let escapedArray = "[" + String(html[markerRange.upperBound ..< endRange.lowerBound]) + "]"
        let encodedString = Data(("\"" + escapedArray + "\"").utf8)
        let leaderboardJSON = try JSONDecoder().decode(String.self, from: encodedString)
        let skills = try JSONDecoder().decode(
            [SkillsShLeaderboardSkill].self,
            from: Data(leaderboardJSON.utf8)
        )
        var seen = Set<String>()
        return skills.compactMap { skill in
            guard let repository = try? GitHubLocation.parse(skill.source).fullName else { return nil }
            let name = skill.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let skillID = skill.skillID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !skillID.isEmpty else { return nil }
            let identity = "\(repository.lowercased())#\(skillID.lowercased())"
            guard seen.insert(identity).inserted else { return nil }
            return DiscoveredSkill(
                id: "skills.sh:\(repository)/\(skillID)",
                name: name,
                repository: repository,
                repositoryPath: nil,
                sourceURL: "https://skills.sh/\(repository)/\(skillID)",
                discoverySource: .skillsSh,
                installs: skill.installs
            )
        }.prefix(limit).map { $0 }
    }

    static func decodeGitHub(_ data: Data) throws -> [DiscoveredSkill] {
        let items = try JSONDecoder().decode([GitHubSearchItem].self, from: data)
        var seen = Set<String>()
        return items.compactMap { item in
            guard item.path.lowercased().hasSuffix("/skill.md") || item.path.lowercased() == "skill.md" else { return nil }
            guard let repository = try? GitHubLocation.parse(item.repository.nameWithOwner).fullName else { return nil }
            let repositoryPath = (item.path as NSString).deletingLastPathComponent
            let name = repositoryPath.isEmpty
                ? repository.split(separator: "/").last.map(String.init) ?? "skill"
                : (repositoryPath as NSString).lastPathComponent
            let identity = "\(repository.lowercased())#\(repositoryPath.lowercased())"
            guard seen.insert(identity).inserted else { return nil }
            return DiscoveredSkill(
                id: "github:\(identity)",
                name: name,
                repository: repository,
                repositoryPath: repositoryPath,
                sourceURL: item.url,
                discoverySource: .github
            )
        }
    }
}

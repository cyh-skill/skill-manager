import Foundation

public enum RouterSearch {
    public static func search(query: String, catalog: SkillCatalog, limit: Int = 8) -> [RouterSearchResult] {
        let normalizedQuery = normalize(query)
        let tokens = normalizedQuery.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        return catalog.skills
            .filter { $0.mode == .lazy && !$0.isDisabled }
            .compactMap { skill -> RouterSearchResult? in
                let score = score(skill: skill, normalizedQuery: normalizedQuery, tokens: tokens)
                guard normalizedQuery.isEmpty || score > 0 else { return nil }
                return RouterSearchResult(skill: skill, score: score)
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.score > $1.score
            }
            .prefix(max(1, limit))
            .map { $0 }
    }

    private static func score(skill: ManagedSkill, normalizedQuery: String, tokens: [String]) -> Int {
        if normalizedQuery.isEmpty { return 1 }
        let name = normalize(skill.name)
        let description = normalize(skill.description)
        let repository = normalize(skill.repository)
        var score = 0
        if name == normalizedQuery { score += 120 }
        if name.hasPrefix(normalizedQuery) { score += 70 }
        if name.contains(normalizedQuery) { score += 45 }
        if description.contains(normalizedQuery) { score += 30 }
        if repository.contains(normalizedQuery) { score += 15 }
        for token in tokens {
            if name == token { score += 30 }
            else if name.contains(token) { score += 18 }
            if description.contains(token) { score += 10 }
            if repository.contains(token) { score += 4 }
        }
        return score
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[-_/]", with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

import Foundation

public struct SkillDocument: Hashable, Sendable {
    public var name: String
    public var description: String
    public var rawContent: String

    public init(name: String, description: String, rawContent: String) {
        self.name = name
        self.description = description
        self.rawContent = rawContent
    }
}

public enum SkillDocumentError: LocalizedError {
    case unreadable(URL)
    case missingFrontmatter(URL)
    case invalidName(URL)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url):
            CoreL10n.choose("无法读取 \(url.path)", "Could not read \(url.path)")
        case .missingFrontmatter(let url):
            CoreL10n.choose("\(url.path) 缺少有效的 YAML frontmatter", "\(url.path) does not contain valid YAML frontmatter")
        case .invalidName(let url):
            CoreL10n.choose("\(url.path) 缺少有效的 Skill 名称", "\(url.path) does not contain a valid Skill name")
        }
    }
}

public enum SkillDocumentParser {
    public static func parse(fileURL: URL) throws -> SkillDocument {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw SkillDocumentError.unreadable(fileURL)
        }
        return try parse(content: content, fallbackName: fileURL.deletingLastPathComponent().lastPathComponent, sourceURL: fileURL)
    }

    public static func parse(content: String, fallbackName: String, sourceURL: URL = URL(fileURLWithPath: "SKILL.md")) throws -> SkillDocument {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let closingIndex = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            throw SkillDocumentError.missingFrontmatter(sourceURL)
        }

        let frontmatter = Array(lines[1..<closingIndex])
        let values = parseFrontmatter(frontmatter)
        let name = normalizedName(values["name"] ?? fallbackName)
        guard !name.isEmpty else {
            throw SkillDocumentError.invalidName(sourceURL)
        }

        let bodyLines = Array(lines[(closingIndex + 1)...])
        let description = cleanedDescription(values["description"] ?? fallbackDescription(from: bodyLines))
        return SkillDocument(name: name, description: description, rawContent: content)
    }

    public static func normalizedName(_ value: String) -> String {
        let lower = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        var output = ""
        var previousWasDash = false
        for scalar in lower.unicodeScalars {
            if allowed.contains(scalar), scalar != "-" {
                output.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                output.append("-")
                previousWasDash = true
            }
        }
        return output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func parseFrontmatter(_ lines: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard let colon = line.firstIndex(of: ":") else {
                index += 1
                continue
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            value = stripQuotes(value)

            if value == "|" || value == ">" {
                let folded = value == ">"
                var continuation: [String] = []
                index += 1
                while index < lines.count {
                    let next = lines[index]
                    guard next.first == " " || next.first == "\t" || next.isEmpty else {
                        index -= 1
                        break
                    }
                    continuation.append(next.trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                value = continuation.joined(separator: folded ? " " : "\n")
            }
            if !key.isEmpty {
                result[key] = value
            }
            index += 1
        }
        return result
    }

    private static func stripQuotes(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func fallbackDescription(from lines: [String]) -> String {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") } ?? ""
    }

    private static func cleanedDescription(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }
}

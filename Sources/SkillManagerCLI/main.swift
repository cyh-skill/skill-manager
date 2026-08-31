import Darwin
import Foundation
import SkillManagerCore

private enum CLIError: LocalizedError {
    case missingArgument(String)
    case notFound(String)
    case unknownCommand(String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let value): "缺少参数：\(value)"
        case .notFound(let value): "找不到 Lazy Skill：\(value)"
        case .unknownCommand(let value): "未知命令：\(value)"
        }
    }
}

@main
struct SkillManagerCLI {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("skill-manager-cli: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }
        let store = CatalogStore()
        let catalog = try store.load()
        let wantsJSON = arguments.contains("--json")

        switch command {
        case "search":
            let query = valueArguments(Array(arguments.dropFirst())).joined(separator: " ")
            guard !query.isEmpty else { throw CLIError.missingArgument("query") }
            let results = RouterSearch.search(query: query, catalog: catalog)
            if wantsJSON {
                try printJSON(results)
            } else if results.isEmpty {
                print("没有匹配的 Lazy Skill。")
            } else {
                for result in results {
                    print("\(result.id.uuidString)\t\(result.name)\t\(result.repository)\t\(result.description)")
                }
            }

        case "list":
            let results = RouterSearch.search(query: "", catalog: catalog, limit: max(catalog.skills.count, 1))
            if wantsJSON {
                try printJSON(results)
            } else {
                for result in results {
                    print("\(result.id.uuidString)\t\(result.name)\t\(result.repository)")
                }
            }

        case "show":
            guard let identifier = valueArguments(Array(arguments.dropFirst())).first else {
                throw CLIError.missingArgument("id-or-name")
            }
            let skill = catalog.skills.first {
                $0.mode == .lazy && ($0.id.uuidString.caseInsensitiveCompare(identifier) == .orderedSame
                    || $0.name.caseInsensitiveCompare(identifier) == .orderedSame)
            }
            guard let skill else { throw CLIError.notFound(identifier) }
            let result = RouterSearchResult(skill: skill, score: 0)
            if wantsJSON {
                try printJSON(result)
            } else {
                print(result.skillPath)
            }

        case "paths":
            let paths = ManagerPaths()
            let payload = [
                "catalog": paths.catalog.path,
                "coldLibrary": paths.sources.path,
                "router": paths.routerSkill.path
            ]
            if wantsJSON {
                try printJSON(payload)
            } else {
                payload.sorted(by: { $0.key < $1.key }).forEach { print("\($0.key)\t\($0.value)") }
            }

        case "help", "--help", "-h":
            printHelp()

        default:
            throw CLIError.unknownCommand(command)
        }
    }

    private static func valueArguments(_ arguments: [String]) -> [String] {
        arguments.filter { $0 != "--json" && $0 != "--query" }
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }

    private static func printHelp() {
        print(
            """
            Skill Manager Lazy Skill helper

              skill-manager-cli search <query> [--json]
              skill-manager-cli list [--json]
              skill-manager-cli show <id-or-name> [--json]
              skill-manager-cli paths [--json]
            """
        )
    }
}

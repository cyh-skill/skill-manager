import Foundation

public struct ProcessResult: Sendable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public struct ProcessFailure: LocalizedError, Sendable {
    public var command: String
    public var exitCode: Int32
    public var message: String

    public var errorDescription: String? {
        let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty
            ? CoreL10n.choose("命令失败（\(exitCode)）：\(command)", "Command failed (\(exitCode)): \(command)")
            : detail
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

public enum ProcessRunner {
    @discardableResult
    public static func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        allowFailure: Bool = false
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let reads = DispatchGroup()
        reads.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutBox.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            reads.leave()
        }
        reads.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            reads.leave()
        }

        try process.run()
        process.waitUntilExit()
        reads.wait()

        let result = ProcessResult(
            stdout: String(data: stdoutBox.data, encoding: .utf8) ?? "",
            stderr: String(data: stderrBox.data, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
        if result.exitCode != 0 && !allowFailure {
            throw ProcessFailure(
                command: ([executable.path] + arguments).joined(separator: " "),
                exitCode: result.exitCode,
                message: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
        return result
    }
}

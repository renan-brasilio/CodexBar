import Foundation

public enum OMPUsageError: LocalizedError, Sendable {
    case binaryNotFound(String)
    case executionFailed(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .binaryNotFound(binary):
            "\(binary) executable not found. Ensure OMP is installed and in PATH."
        case let .executionFailed(msg):
            "OMP execution failed: \(msg)"
        case let .parseFailed(msg):
            "Failed to parse OMP usage output: \(msg)"
        }
    }
}

public struct OMPCLIProbe: Sendable {
    private static let commandTimeout: TimeInterval = 15

    public init() {}

    public func fetch(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        subprovider: String = "all",
        hiddenItemIDs: [String] = [],
        now: Date = Date()) async throws -> UsageSnapshot
    {
        let loginPATH = LoginShellPathCache.shared.current
        guard let executable = BinaryLocator.resolveOMPBinary(env: environment, loginPATH: loginPATH) else {
            throw OMPUsageError.binaryNotFound("omp")
        }

        var commandEnvironment = environment
        commandEnvironment["NO_COLOR"] = "1"
        commandEnvironment["PATH"] = PathBuilder.effectivePATH(
            purposes: [.tty, .nodeTooling],
            env: environment,
            loginPATH: loginPATH)

        let result: SubprocessResult
        do {
            result = try await SubprocessRunner.run(
                binary: executable,
                arguments: ["usage", "--json"],
                environment: commandEnvironment,
                timeout: Self.commandTimeout,
                standardInput: FileHandle.nullDevice,
                label: "omp-usage")
        } catch let error as SubprocessRunnerError {
            throw OMPUsageError.executionFailed(error.localizedDescription)
        }

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stdout.isEmpty else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderr.isEmpty {
                let sanitized = String(stderr.prefix(200))
                throw OMPUsageError.executionFailed(sanitized)
            }
            throw OMPUsageError.parseFailed("The omp CLI returned no usage data.")
        }

        return try OMPUsageParser.parse(
            jsonString: stdout,
            subprovider: subprovider,
            hiddenItemIDs: hiddenItemIDs,
            now: now)
    }
}

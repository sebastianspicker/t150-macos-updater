import Foundation
import T150Core

enum EngineClient {
    static func tool(_ name: String) throws -> URL {
        guard let resources = Bundle.main.resourceURL else { throw UpdaterError.missingTool(name) }
        let url = resources.appendingPathComponent("Tools").appendingPathComponent(name)
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw UpdaterError.missingTool(name) }
        return url
    }

    static func run(_ operation: String, session: URL, extra: [String] = []) throws -> EngineResult {
        let identifier = UUID().uuidString
        let resultURL = session.appendingPathComponent("\(operation)-\(identifier)-result.json")
        let logURL = session.appendingPathComponent("\(operation)-\(identifier)-console.log")
        let args = operation == "status" ? [operation] : [operation, "--session", session.path]
        let status = try ChildProcess.run(executable: tool("t150-engine"),
            arguments: args + extra + ["--result", resultURL.path], log: logURL)
        let data: Data
        do { data = try PrivateFiles.readRegular(resultURL, maximum: 128 * 1024) }
        catch { throw UpdaterError.process("The device tool stopped without a complete result (exit \(status)). Keep USB and wheel power connected if an update had started. Your session files are preserved; do not start another flash attempt.") }
        let result = try JSONDecoder().decode(EngineResult.self, from: data)
        guard result.schema == 1, result.operation == operation, !result.ok || status == 0 else {
            throw UpdaterError.process("The device tool returned an inconsistent result. The operation has stopped; keep your backup session.")
        }
        return result
    }
}

import Foundation
import Darwin

public enum ChildProcess {
    /// Called off the main thread. Output goes to a private file rather than an
    /// unread pipe, so verbose utilities cannot block an update through pipe fill.
    public static func run(executable: URL, arguments: [String], log: URL,
                           timeout: TimeInterval? = nil) throws -> Int32 {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw UpdaterError.missingTool(executable.lastPathComponent)
        }
        let fd = open(log.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw UpdaterError.invalid("Could not create a new operation log.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.synchronize(); try? handle.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "C", "TMPDIR": NSTemporaryDirectory()]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        try process.run()
        if let timeout, completed.wait(timeout: .now() + timeout) == .timedOut {
            // Only extraction uses a timeout. A firmware engine is never killed
            // by the GUI; it owns bounded USB operations and its own sleep lock.
            process.terminate()
            if completed.wait(timeout: .now() + 3) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                completed.wait()
            }
            throw UpdaterError.process("Installer extraction timed out. No firmware update was started.")
        } else if timeout == nil {
            completed.wait()
        }
        return process.terminationStatus
    }
}

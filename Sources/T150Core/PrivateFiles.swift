import Foundation
import Darwin

public enum PrivateFiles {
    public static func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        var information = stat()
        guard lstat(url.path, &information) == 0,
              information.st_mode & S_IFMT == S_IFDIR, information.st_uid == getuid(),
              information.st_mode & 0o077 == 0 else {
            throw UpdaterError.invalid("The backup folder must be a private folder owned by your account.")
        }
    }

    /// Exclusive creation: an existing backup or a symbolic link is never replaced.
    public static func writeNew(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw UpdaterError.invalid("Cannot create a new private file: \(url.lastPathComponent). Existing files are never overwritten.") }
        defer { close(fd) }
        try data.withUnsafeBytes { buffer in
            var written = 0
            while written < buffer.count {
                let amount = Darwin.write(fd, buffer.baseAddress!.advanced(by: written), buffer.count - written)
                if amount < 0 && errno == EINTR { continue }
                guard amount > 0 else { throw UpdaterError.invalid("Could not save \(url.lastPathComponent). Check free disk space.") }
                written += amount
            }
        }
        guard fsync(fd) == 0 else { throw UpdaterError.invalid("Could not synchronize \(url.lastPathComponent) to storage.") }
        let directory = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw UpdaterError.invalid("Could not open the backup directory.") }
        defer { close(directory) }
        guard fsync(directory) == 0 else { throw UpdaterError.invalid("Could not synchronize the backup directory.") }
    }

    public static func readRegular(_ url: URL, maximum: Int) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw UpdaterError.invalid("Cannot open \(url.lastPathComponent). Choose a regular file, not a symbolic link.") }
        defer { close(fd) }
        var information = stat()
        guard fstat(fd, &information) == 0, information.st_mode & S_IFMT == S_IFREG,
              information.st_size > 0, information.st_size <= maximum else {
            throw UpdaterError.invalid("\(url.lastPathComponent) is empty, too large, or is not a regular file.")
        }
        let length = Int(information.st_size)
        var data = Data(count: length)
        try data.withUnsafeMutableBytes { buffer in
            var received = 0
            while received < length {
                let amount = Darwin.read(fd, buffer.baseAddress!.advanced(by: received), length - received)
                if amount < 0 && errno == EINTR { continue }
                guard amount > 0 else { throw UpdaterError.invalid("The selected file changed while it was being read.") }
                received += amount
            }
        }
        var extra: UInt8 = 0
        var trailing: Int
        repeat { trailing = Darwin.read(fd, &extra, 1) } while trailing < 0 && errno == EINTR
        var final = stat()
        guard trailing == 0, fstat(fd, &final) == 0, final.st_size == information.st_size,
              final.st_mtimespec.tv_sec == information.st_mtimespec.tv_sec,
              final.st_mtimespec.tv_nsec == information.st_mtimespec.tv_nsec else {
            throw UpdaterError.invalid("The selected file changed while it was being read.")
        }
        return data
    }
}

/// The app holds this lock for its lifetime, including dialogs and child work.
/// The engine holds its own lock; it must never depend on the GUI staying alive.
public final class InstanceLock {
    private var descriptor: Int32 = -1
    public init(url: URL) throws {
        descriptor = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        var info = stat()
        guard descriptor >= 0, fstat(descriptor, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0,
              flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if descriptor >= 0 { close(descriptor); descriptor = -1 }
            throw UpdaterError.invalid("Another updater window is open, or the private updater lock is unavailable. Use the existing app window. Never quit an update in progress.")
        }
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
    }
    deinit { if descriptor >= 0 { close(descriptor) } }
}

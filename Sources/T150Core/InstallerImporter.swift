import Foundation

public struct ImportedFirmware: Sendable {
    public let profile: FirmwareProfile
    public let session: URL
    public let decodedFile: URL
}

public enum InstallerImporter {
    /// No USB code exists in this import path. Unknown packages stop before
    /// extraction; the only child process is the bundled native cabinet reader.
    public static func inspect(installer: URL, session: URL, unshield: URL) throws -> ImportedFirmware {
        try PrivateFiles.createDirectory(session)
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: session.path)
        guard let free = attributes[.systemFreeSize] as? NSNumber, free.uint64Value > 512 * 1024 * 1024 else {
            throw UpdaterError.invalid("At least 512 MB of free disk space is needed to inspect the package and preserve backups.")
        }
        let installerData = try PrivateFiles.readRegular(installer, maximum: 128 * 1024 * 1024)
        let profile = try FirmwareProfile.identify(installerData)
        let cabinets = try InstallerContainer.cabinets(from: installerData)
        let work = session.appendingPathComponent("Import", isDirectory: true)
        // Exclusive creation: an existing Import folder is never adopted (and so never removed below).
        guard mkdir(work.path, 0o700) == 0 else { throw UpdaterError.invalid("This import session has already been used. Choose the installer again to start a new session.") }
        try PrivateFiles.createDirectory(work)
        // Cabinets and the extracted vendor payload are only needed for validation.
        // `work` was created above for this import alone; remove it on failure too.
        var workRemoved = false
        defer { if !workRemoved { try? FileManager.default.removeItem(at: work) } }
        for (name, content) in cabinets {
            try PrivateFiles.writeNew(content, to: work.appendingPathComponent(name))
        }
        let payload = work.appendingPathComponent("payload", isDirectory: true)
        let code = try ChildProcess.run(executable: unshield,
            arguments: ["-d", payload.path, "x", work.appendingPathComponent("data1.cab").path],
            log: session.appendingPathComponent("import.log"), timeout: 120)
        guard code == 0 else { throw UpdaterError.process("The firmware cabinet could not be extracted. The wheel has not been changed. See the private session log.") }
        let wrapped = try PrivateFiles.readRegular(payload.appendingPathComponent(profile.firmwareMember), maximum: 57_472)
        let driver = try PrivateFiles.readRegular(payload.appendingPathComponent(profile.driverMember), maximum: 383_008)
        let decoded = try FirmwareDecoder.decode(wrapped: wrapped, driver: driver, profile: profile)
        let decodedFile = session.appendingPathComponent("imported-decoded.tmf")
        try PrivateFiles.writeNew(decoded, to: decodedFile)
        let receipt: [String: Any] = ["schema": 1, "profile": profile.identifier,
            "installerSHA256": profile.installerSHA256, "decodedSHA256": profile.decodedSHA256,
            "targetVersion": profile.version, "source": "user-selected official installer",
            "created": ISO8601DateFormatter().string(from: Date())]
        try PrivateFiles.writeNew(JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys, .prettyPrinted]),
                                  to: session.appendingPathComponent("import-receipt.json"))
        // The decoded image and receipt remain. Temporary cabinets and all other
        // proprietary driver payloads are no longer needed after validation.
        try FileManager.default.removeItem(at: work)
        workRemoved = true
        return ImportedFirmware(profile: profile, session: session, decodedFile: decodedFile)
    }
}

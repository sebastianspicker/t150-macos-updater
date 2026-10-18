import AppKit
import SwiftUI
import T150Core

@MainActor
final class UpdateModel: ObservableObject {
    @Published var stage: UpdateStage = .installer
    @Published var busy = false
    @Published var headline = "Update your T150 from a Mac."
    @Published var detail = "Choose the official Thrustmaster installer. This app checks compatibility, saves two backups, and verifies every flash byte before restarting your wheel."
    @Published var failure: String?
    @Published var technicalDetail = ""
    @Published var firmware: ImportedFirmware?
    @Published var target: FirmwareTarget?
    @Published var device: EngineResult.Device?
    @Published var plan: [EngineResult.Run] = []
    @Published var secured = false
    @Published var powerConnected = false
    @Published var ps3 = false
    @Published var stableUSB = false
    @Published var modifiedAcknowledged = false {
        didSet { if !modifiedAcknowledged { experimentalAcknowledged = false } }
    }
    /// Second, separate opt-in for experimental targets (`requiresDoubleOptIn`); it
    /// is cleared whenever the first acknowledgement is withdrawn.
    @Published var experimentalAcknowledged = false
    @Published var backupAcknowledged = false
    @Published var confirmUpdate = false
    @Published var alreadyCurrent = false
    @Published var startupFailure: String?
    @Published var helpVisible = false
    private var instanceLock: InstanceLock?
    private var activity: NSObjectProtocol?
    /// The engine's artifacts are single-use, so every backup attempt gets a new
    /// private engine session inside the import session.
    private var attempt: URL?
    let base: URL

    /// Engine apply codes that are emitted before the apply-started marker, so no
    /// programming command can have been sent. Anything else is treated as a write.
    private static let applyCodesBeforeWrite: Set<String> = [
        "arguments", "confirmation_required", "busy", "sleep_assertion", "session_directory",
        "memory", "session_invalid", "ac_power_required", "log", "device_changed", "baseline_changed", "marker_failed"
    ]

    init() {
        base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/T150 Firmware Updater", isDirectory: true)
        do {
            try PrivateFiles.createDirectory(base)
            instanceLock = try InstanceLock(url: base.appendingPathComponent("gui.lock"))
            try PrivateFiles.createDirectory(base.appendingPathComponent("Sessions", isDirectory: true))
        } catch { startupFailure = error.localizedDescription }
    }

    var safetyReady: Bool { secured && powerConnected && ps3 && stableUSB && targetReady }
    /// Official: always. Modified: the modified-firmware acknowledgement. Experimental:
    /// that one and the separate experimental acknowledgement, both ticked for this target.
    var targetReady: Bool {
        guard let target else { return false }
        if target.isOfficial { return true }
        return modifiedAcknowledged && (!target.requiresDoubleOptIn || experimentalAcknowledged)
    }
    var canAct: Bool { !busy && startupFailure == nil }
    /// The target may change until backups have been prepared for one.
    var canChangeTarget: Bool {
        canAct && firmware != nil && (stage == .recovery || stage == .backup || (stage == .complete && alreadyCurrent))
    }

    func chooseInstaller() {
        guard canAct else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose the official Thrustmaster installer"
        panel.message = "Select the .exe file downloaded from Thrustmaster. The Windows installer will not be run."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        let session = base.appendingPathComponent("Sessions", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        do { try PrivateFiles.createDirectory(session) } catch { fail(error); return }
        firmware = nil; target = nil; attempt = nil; device = nil; alreadyCurrent = false; plan = []
        backupAcknowledged = false; modifiedAcknowledged = false; experimentalAcknowledged = false
        stage = .installer
        begin("Checking the official installer", "Verifying the package, extracting its cabinet privately, and validating the T150 image. Temporary extracted files are removed after validation. The wheel is not being changed.")
        Task {
            do {
                let unshield = try EngineClient.tool("unshield")
                let imported = try await Task.detached(priority: .userInitiated) {
                    try InstallerImporter.inspect(installer: selected, session: session, unshield: unshield)
                }.value
                firmware = imported
                target = imported.profile.targets.first
                stage = .recovery
                headline = "Official V\(imported.profile.version) is ready"
                detail = "The installer and firmware match this app’s reviewed compatibility profile. Check the connected wheel before entering recovery mode."
                end()
                await readStatus()
            } catch { fail(error) }
        }
    }

    func selectTarget(_ identifier: String) {
        guard canChangeTarget, let firmware, identifier != target?.identifier,
              let selected = firmware.profile.targets.first(where: { $0.identifier == identifier }) else { return }
        target = selected; modifiedAcknowledged = false; experimentalAcknowledged = false; alreadyCurrent = false; failure = nil
        stage = .recovery
        headline = "\(selected.name) selected"
        detail = "Check the wheel connection again for this firmware."
    }

    func refreshDevice() {
        guard canAct else { return }
        Task { await readStatus() }
    }

    private func readStatus() async {
        guard !busy, let firmware, let target else { return }
        begin("Checking the wheel", "Reading device identity and firmware version. No firmware is written.")
        do {
            let result = try await Task.detached { try EngineClient.run("status", session: firmware.session) }.value
            device = result.device
            technicalDetail = result.message
            if result.state == "multiple_devices" {
                throw UpdaterError.process("More than one Thrustmaster USB device is connected. Disconnect every other Thrustmaster product (a second wheel, pedals or a shifter with its own USB plug), keep only the T150, and check again. Nothing was sent to the wheel.")
            }
            guard result.ok else { throw UpdaterError.process(result.message) }
            let version = result.device?.applicationVersion
            let sameVersionCheck = version == target.version && target.allowsSameVersion
            if let version, version >= target.version, !sameVersionCheck {
                alreadyCurrent = true; stage = .complete
                headline = version == target.version ? "Your wheel is already up to date" : "Your wheel has newer firmware"
                detail = "The wheel reports V\(version); the selected firmware is V\(target.version). No update or downgrade will be performed."
                if result.device?.pid == 0xb676 {
                    detail += " You entered recovery mode without starting an update. With no operation running, reconnect USB normally without holding L3 + R3 to leave recovery."
                }
            } else if result.device?.pid == 0xb676 {
                stage = .backup; headline = "Recovery mode detected"
                detail = "Confirm the connection and power checks below. The next step reads the entire flash twice and saves matching backups before any firmware write is allowed."
                if sameVersionCheck {
                    detail += " The wheel already reports V\(target.version), so the backups also show whether \(target.name) is already installed."
                }
            } else {
                stage = .recovery; headline = "Put the T150 into recovery mode"
                detail = "Follow the steps below, then check the connection again. A dark MODE light and no calibration are expected in recovery mode."
            }
            end()
        } catch { fail(error) }
    }

    func prepareBackup() {
        guard canAct, safetyReady, let firmware, let target else { return }
        guard PowerState.isOnAC else { failure = "Connect your Mac to AC power before preparing the update, and keep its lid open."; return }
        let folder = firmware.session.appendingPathComponent("Update-\(UUID().uuidString)", isDirectory: true)
        do { try PrivateFiles.createDirectory(folder) } catch { fail(error); return }
        attempt = folder; plan = []; backupAcknowledged = false
        begin("Saving and checking two backups", "Keep USB and wheel power connected. No firmware is being written. Both complete flash reads must match and be safely saved.")
        Task {
            do {
                let result = try await Task.detached {
                    try EngineClient.run("prepare", session: folder,
                        extra: ["--firmware", firmware.decodedFile.path, "--profile", target.identifier])
                }.value
                device = result.device
                if !result.ok, result.code == "already_current" {
                    try Self.requireProfile(result, target)
                    attempt = nil; alreadyCurrent = true; stage = .complete
                    headline = "\(target.name) is already installed"
                    detail = result.message
                    if result.device?.pid == 0xb676 {
                        detail += " With no operation running, reconnect USB normally without holding L3 + R3 to leave recovery."
                    }
                    end(); return
                }
                guard result.ok else { throw UpdaterError.process(result.message) }
                try Self.requireProfile(result, target)
                plan = result.plan ?? []; stage = .review
                headline = "Your backups are saved. Review the update."
                detail = "The original bootloader is supported, two complete backups match, and the update plan preserves the bootloader. A third read will check that the wheel is unchanged immediately before writing."
                end()
            } catch { attempt = nil; fail(error) }
        }
    }

    func update() {
        guard canAct, stage == .review, safetyReady, backupAcknowledged, let target, let attempt else { return }
        guard PowerState.isOnAC else { failure = "Reconnect your Mac to AC power before starting the update."; return }
        stage = .updating
        begin("Updating to \(target.name)", "Keep USB and wheel power connected. Keep the Mac awake with its lid open. The app will verify the entire flash before restarting; the wheel may then calibrate.")
        Task {
            var writeMayHaveStarted = true
            var verifiedNotRestarted: Bool? = nil   // set once apply succeeded: whether finish issued the reset
            do {
                let applied: EngineResult
                do {
                    applied = try await Task.detached {
                        try EngineClient.run("apply", session: attempt, extra: ["--confirm-program"])
                    }.value
                } catch let error as UpdaterError {
                    // The engine could not even be launched: nothing was sent to the wheel.
                    if case .missingTool = error { writeMayHaveStarted = false }
                    throw error
                }
                if !applied.ok, Self.applyCodesBeforeWrite.contains(applied.code) { writeMayHaveStarted = false }
                guard applied.ok else { throw UpdaterError.process(applied.message) }
                try Self.requireProfile(applied, target)
                verifiedNotRestarted = true
                headline = "Firmware verified. Preparing to restart."
                detail = "Reading the complete flash once more before restarting. Keep hands and objects clear of the wheel’s rotation."
                let finished = try await Task.detached {
                    try EngineClient.run("finish", session: attempt, extra: ["--confirm-restart"])
                }.value
                verifiedNotRestarted = finished.restartIssued != true
                guard finished.ok, finished.device?.applicationVersion == target.version,
                      finished.device?.pid == 0xb677 else { throw UpdaterError.process(finished.message) }
                try Self.requireProfile(finished, target)
                device = finished.device; stage = .complete
                headline = "\(target.name) is installed and verified"
                detail = "The entire image was verified, the original bootloader is unchanged, and the wheel reports V\(target.version) in normal mode. Check that calibration and the MODE light look normal. Your backups and verification records are saved."
                end()
            } catch {
                if let verifiedNotRestarted {
                    failedAfterVerification(error, restartIssued: !verifiedNotRestarted, target: target)
                } else if writeMayHaveStarted { fail(error, afterWrite: true) } else { stoppedBeforeWrite(error) }
            }
        }
    }

    /// The complete target image was written and read back byte for byte, so the flash
    /// is in a known good state; only the restart step did not complete.
    private func failedAfterVerification(_ error: Error, restartIssued: Bool, target: FirmwareTarget) {
        failure = error.localizedDescription
        stage = .updating
        if restartIssued {
            headline = "Firmware verified and restart sent. Check the wheel."
            detail = "The new image was fully verified and the restart command was sent, but the app could not confirm normal mode within its time limit. Do not start another update. Wait for the wheel to finish calibrating, then reconnect USB normally (without holding L3 + R3) and use Check the wheel; it should report V\(target.version). Keep this session’s backups."
        } else {
            headline = "Firmware verified, but the wheel was not restarted"
            detail = "The new image was written and verified byte for byte, but the restart step stopped before sending the reset, so the wheel is still in recovery mode with the new firmware in flash. Do not start another update. Disconnect the wheel’s USB and power, reconnect without holding L3 + R3, let it calibrate, then use Check the wheel; it should report V\(target.version). Keep this session’s backups."
        }
        end()
    }

    func showSession() { if let session = firmware?.session { NSWorkspace.shared.open(session) } }
    func showAllSessions() { NSWorkspace.shared.open(base.appendingPathComponent("Sessions")) }
    func showOfficialWebsite() { NSWorkspace.shared.open(FirmwareProfile.supportURL) }
    func showRecoveryGuide() { NSWorkspace.shared.open(FirmwareProfile.recoveryURL) }

    private static func requireProfile(_ result: EngineResult, _ target: FirmwareTarget) throws {
        guard result.profile == target.identifier else {
            throw UpdaterError.process("The device tool reported a different firmware target than the one selected. The operation has stopped; keep your backup session.")
        }
    }

    private func begin(_ title: String, _ text: String) {
        busy = true; failure = nil; headline = title; detail = text
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled, .idleDisplaySleepDisabled], reason: "T150 firmware verification and update")
    }
    private func end() {
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        busy = false
    }
    /// The engine refused before sending any programming command; the prepared
    /// attempt is spent, so a retry starts with fresh backups.
    private func stoppedBeforeWrite(_ error: Error) {
        attempt = nil; plan = []; backupAcknowledged = false; stage = .backup
        headline = "No firmware was written"
        detail = "The update stopped before writing. Check the connection and power, then save new backups to try again."
        failure = error.localizedDescription
        end()
    }
    private func fail(_ error: Error, afterWrite: Bool = false) {
        failure = error.localizedDescription
        if afterWrite {
            headline = "Update stopped. Keep the wheel connected."
            detail = "Do not start another update or disconnect power. The app will not automatically retry a write or reset unverified firmware. Keep this session’s backups and logs, and follow the recovery guidance."
            stage = .updating // No update/retry button is offered in a failed write state.
        }
        end()
    }
}

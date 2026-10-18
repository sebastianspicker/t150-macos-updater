import Foundation
import CryptoKit

/// A compiled native-engine target built from a reviewed installer's decoded image.
/// The engine rebuilds and hash-checks every target independently; this entry only
/// selects which compiled engine profile to request and how to describe it.
public struct FirmwareTarget: Equatable, Sendable, Identifiable {
    public let identifier: String
    public let title: String
    public let version: Int
    public let targetSHA256: String
    public let isOfficial: Bool
    /// The engine accepts only pinned full-flash images at this same version (the
    /// other reviewed V35 images). The engine decides from flash content.
    public let allowsSameVersion: Bool
    /// Experimental targets need a second, separate acknowledgement in addition to
    /// the modified-firmware one before any backup or write step is offered.
    public let requiresDoubleOptIn: Bool
    public let summary: String
    /// Short name for headlines and buttons. `title` is the full technical name.
    public let name: String
    /// One line shown under the name in the build picker.
    public let tagline: String
    public let role: Role
    public var id: String { identifier }

    /// How the build picker presents a target.
    public enum Role: Sendable {
        /// Thrustmaster's image, unchanged.
        case official
        /// A modified build offered next to the official one.
        case modified
        /// The build that fixed the ACC PS5 stutter.
        case recommendedFix
        /// Experimental builds kept for completeness and further testing.
        case extra
    }
}

/// Trust is established by a reviewed app release, never by an editable manifest.
/// Adding a profile also requires a corresponding independent native-engine gate.
public struct FirmwareProfile: Equatable, Sendable {
    public let identifier: String
    public let version: Int
    public let installerName: String
    public let installerSize: Int
    public let installerSHA256: String
    public let driverSHA256: String
    public let wrappedSHA256: String
    public let decodedSHA256: String
    public let firmwareMember: String
    public let driverMember: String
    /// The first target is always the unmodified official image.
    public let targets: [FirmwareTarget]

    public static let reviewed: [FirmwareProfile] = [FirmwareProfile(
        identifier: "t150-lpc11-v35-2026-ttrs-2",
        version: 35,
        installerName: "2026_TTRS_2.exe",
        installerSize: 50_836_032,
        installerSHA256: "fccd2dff4ecebf4a13616d6d7acb836ba668c0d327c1f5bb990947355842bc09",
        driverSHA256: "e2c25fcca27b69588fb7489c6edf5d2245cbd8d6b4287ce9be558f32ccac8fc4",
        wrappedSHA256: "5d1278d27c8edfdcaffc7886b0d2cc4832ac7d112afa3bd645462e88b790202b",
        decodedSHA256: "267e00a01864a217a83fe6b007cda58651c817ad9706e5cc9e517993f14d08d4",
        firmwareMember: "FW_Updater_C64/firmware/T150_LPC11_v35.tmf",
        driverMember: "Drivers_Win10/amd64/tmwbulk.sys",
        targets: [FirmwareTarget(
            identifier: "t150-v35-boot5",
            title: "Official V35",
            version: 35,
            targetSHA256: "37a481796e85d05cf75bafc56bea73fb647b0cfc63270dbb3761d699ee6c5056",
            isOfficial: true,
            allowsSameVersion: true,
            requiresDoubleOptIn: false,
            summary: "The unmodified Thrustmaster firmware from the selected installer.",
            name: "Official V35",
            tagline: "Thrustmaster's firmware, unchanged.",
            role: .official
        ), FirmwareTarget(
            identifier: "t150-v35-fixes-boot5",
            title: "V35 + fixes",
            version: 35,
            targetSHA256: "7822b9095ee0ebdf466d7a8cbc4bf1fb332521fac89cefd87a63963e8ac03f34",
            isOfficial: false,
            allowsSameVersion: true,
            requiresDoubleOptIn: false,
            summary: "Official V35 with a small set of reviewed byte fixes, built on this Mac from your official image. It stops the settings log from overflowing (D1), restarts the wheel after a power dip instead of hanging (D5), and adds bounds checks to USB control and force-feedback commands (D3, D4, D7, D8). Not an official Thrustmaster release.",
            name: "V35 + fixes",
            tagline: "Official V35 with six firmware defects fixed.",
            role: .modified
        ), FirmwareTarget(
            identifier: "t150-v35-full-boot5",
            title: "V35 + fixes + PS5 stutter patch (experimental)",
            version: 35,
            targetSHA256: "a4444a06ce5a7dcd5e2afaeab76015b588ee55548613ccb17fc8f3148c29509b",
            isOfficial: false,
            allowsSameVersion: true,
            requiresDoubleOptIn: true,
            summary: "Everything in V35 + fixes, plus a first attempt at the Assetto Corsa Competizione stutter on PS5: a DualShock-style frame counter and timestamp in the PlayStation input report, no reports caused by pedal noise, queued force-feedback commands, live GET_REPORT data, a stale USB transfer skipped before reuse, and no EEPROM rewrite for an unchanged range setting. In an earlier test it did not change the stutter; for that, choose PS5 stutter fix. You can return to the official or the fixes firmware with this app at any time.",
            name: "PS5 stutter patch (first attempt)",
            tagline: "Changed the input report. Did not fix the stutter.",
            role: .extra
        ), FirmwareTarget(
            identifier: "t150-v35-sibrec-boot5",
            title: "V35 + sibling mimic + recorder (experimental)",
            version: 35,
            targetSHA256: "6874dd15c981581325396fe6e595fe46ed73c79b1ae1b9a19f3a7685ff60f9a9",
            isOfficial: false,
            allowsSameVersion: true,
            requiresDoubleOptIn: true,
            summary: "A test build for the Assetto Corsa Competizione stutter on PS5. It keeps the fixes of the PS5 stutter patch but drops its DualShock counter, timestamp and pedal filter, sends console vendor replies as 64-byte packets like the T300 and T248, and records what the console sends. Flipping the PS/PC switch saves the record. Tested in an emulator, not yet on a console. You can return to the official or any other build with this app at any time.",
            name: "Sibling mimic",
            tagline: "64-byte console replies only. Not tried on a console.",
            role: .extra
        ), FirmwareTarget(
            identifier: "t150-v35-sibrec-feat-boot5",
            title: "V35 + sibling mimic + T300 features + recorder (experimental)",
            version: 35,
            targetSHA256: "e921b91ee581809c2e138be7706864df608efd69e463f1ccde1db206766f6886",
            isOfficial: false,
            allowsSameVersion: true,
            requiresDoubleOptIn: true,
            summary: "The build to choose for the Assetto Corsa Competizione stutter on PS5. On a tester's T150 it removed the stutter over several races, with the wheel fully working in the game. It is the Sibling mimic build, and it also answers feature reports 0x03, 0x4a and 0x49 like a T300 in PlayStation mode. The recorder only logs what the console sends. This is one owner's result, not a controlled measurement. You can return to the official or any other build with this app at any time.",
            name: "PS5 stutter fix",
            tagline: "Removed the Assetto Corsa Competizione stutter on PS5 on a tester\u{2019}s T150.",
            role: .recommendedFix
        ), FirmwareTarget(
            identifier: "t150-v35-sibrec-raw-boot5",
            title: "V35 + sibling mimic + recorder + RAW keepalive (experimental)",
            version: 35,
            targetSHA256: "1e2de4a320788b58ade80b68a3c9c1c32582588343f13df52bd06d61d733128a",
            isOfficial: false,
            allowsSameVersion: true,
            requiresDoubleOptIn: true,
            summary: "The sibling mimic build plus one more T300 behaviour: after the console sends the vendor command RAW, the wheel sends an input report every 8 ms even when nothing changes, and NORM restores the normal 250 ms keepalive. Only useful if a recorder record shows that the console sends RAW. Tested in an emulator, not yet on a console. You can return to the official or any other build with this app at any time.",
            name: "Sibling mimic + RAW keepalive",
            tagline: "Adds the T300's 8 ms keepalive. Not tried on a console.",
            role: .extra
        ), FirmwareTarget(
            identifier: "t150-v35-sibrec-feat-raw-boot5",
            title: "V35 + sibling mimic + T300 features + recorder + RAW keepalive (experimental)",
            version: 35,
            targetSHA256: "e934f1e6ce741eab4a0e0e0ed24392348310e70732b251a5fb079ae081932005",
            isOfficial: false,
            allowsSameVersion: true,
            requiresDoubleOptIn: true,
            summary: "The sibling mimic + T300 features build plus the T300's RAW keepalive: an input report every 8 ms after the console sends RAW, back to normal after NORM. Only useful if a recorder record shows that the console sends RAW. Tested in an emulator, not yet on a console. You can return to the official or any other build with this app at any time.",
            name: "PS5 stutter fix + RAW keepalive",
            tagline: "The PS5 fix plus the T300's 8 ms keepalive. Not tried on a console.",
            role: .extra
        )]
    )]

    public static let supportURL = URL(string: "https://support.thrustmaster.com/en/product/t150ffb-en/")!
    public static let recoveryURL = URL(string: "https://ts.thrustmaster.com/download/accessories/Manuals/T150/T150_Bootloader_Method.pdf")!

    public static func identify(_ data: Data) throws -> FirmwareProfile {
        let digest = sha256(data)
        guard let profile = reviewed.first(where: { $0.installerSize == data.count && $0.installerSHA256 == digest }) else {
            throw UpdaterError.unsupportedInstaller
        }
        return profile
    }
}

public func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

public enum UpdaterError: LocalizedError {
    case unsupportedInstaller
    case invalid(String)
    case missingTool(String)
    case process(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedInstaller:
            return "This installer has not been reviewed for this app version. No wheel commands were sent. Download the official package listed in Help, or use a newer app release that explicitly supports your installer. Renaming the file will not make it compatible."
        case .invalid(let text), .process(let text): return text
        case .missingTool(let name): return "The app is missing its bundled \(name) tool. Rebuild or reinstall the complete app bundle."
        }
    }
}

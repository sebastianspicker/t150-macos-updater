import SwiftUI
import T150Core

struct HelpView: View {
    @ObservedObject var model: UpdateModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Help & recovery").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Getting the right firmware", "Download the PC drivers + firmware .exe from the official T150 page. Choose that file in this app; do not open it in Windows or Whisky. The filename alone does not prove compatibility. This app currently accepts the reviewed 2026_TTRS_2.exe package containing T150 V35.")
                    Button("Open official downloads", action: model.showOfficialWebsite)
                    section("Future versions", "Future firmware requires a new reviewed app release. Installer, firmware, decoder, controller and bootloader checks must all agree. Unknown packages and bootloaders are blocked; editing a file name or manifest cannot enable them. The app does not claim support for firmware that has not been reviewed.")
                    if FirmwareProfile.reviewed.contains(where: { $0.targets.count > 1 }) {
                        section("Reviewed fixes build", "This app release can also install a fixes build next to the official firmware. It is never downloaded or shipped with the app: the app builds it from your official image by replacing a small, reviewed set of bytes, and the result must match a pinned SHA-256 before anything is written. The bootloader is never changed. To go back, choose the official firmware and update again; this is only accepted when the wheel contains exactly one of the reviewed images.")
                        section("PS5 stutter builds", "Five experimental builds target the Assetto Corsa Competizione stutter on PS5. Each needs two separate acknowledgements before the backup and update buttons unlock. For the stutter, choose \"PS5 stutter fix\", marked Recommended for PS5. On a tester\u{2019}s T150 it removed the stutter over several races. It answers the console's vendor and feature-report requests the way a T300 does, in PlayStation mode only. The other four experimental builds are kept for completeness under Other experimental builds: the first attempt changed the input report and did not help, and the rest have not been tried on a console. You can switch between the official, fixes and experimental builds in any direction while the wheel holds exactly one of them.")
                    }
                    section("Entering recovery mode", "With wheel power connected and the switch on PS3, unplug only USB. Hold L3 + R3 on the base while reconnecting USB, then release after connection. No calibration and a dark MODE light are expected. Connect just one Thrustmaster device. The app detects the recovery interface before reading any backup.")
                    Button("Open the official recovery guide", action: model.showRecoveryGuide)
                    section("What gets backed up", "The full 64 KiB flash is read twice. Both reads must agree, and both original images are saved privately before writing is allowed. The app preserves the original bootloader, compares a fresh baseline immediately before writing, and verifies the entire result before restarting. Backup files are never overwritten.")
                    Button("Show all saved sessions", action: model.showAllSessions)
                    section("If something stops", "During writing or verification, keep USB and wheel power connected. Do not blindly retry or reset the wheel. Preserve the entire session folder and seek qualified recovery help or Thrustmaster support. The app blocks an automatic retry after a partial write. A saved backup is recovery evidence; an automatic restore or downgrade is not provided or tested.")
                    section("If you entered recovery but never started an update", "With no operation running and no firmware write attempted, you can reconnect USB normally without holding L3 + R3. Keep the wheel secured and clear in case it calibrates. After an attempted or interrupted write, use the recovery guidance instead of this shortcut.")
                    section("What the safeguards cannot prevent", "USB cable loss, wheel power loss, a forced shutdown, hardware faults or closing the Mac’s lid can still interrupt an update. No utility can promise zero risk. Keep a stable connection, use AC power, leave the lid open, and do not force-quit the app. The native engine also holds its own lock and sleep protection during its operation.")
                    section("Privacy and compatibility", "Firmware, backups and detailed logs remain on this Mac. Nothing is uploaded. Session folders may contain device identifiers and proprietary firmware: do not post them publicly. This independent utility is not endorsed by Thrustmaster, and it does not add macOS game or force-feedback support.")
                    section("Disclaimer", "This app is provided as is, without warranty of any kind. Updating firmware can leave a wheel unusable, and unofficial software or modified firmware may void your warranty. You use it at your own risk; the authors are not liable for any damage. This project is not affiliated with Thrustmaster.")
                }.padding(.trailing, 8)
            }
        }.padding(28).frame(width: 680, height: 670)
    }
    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

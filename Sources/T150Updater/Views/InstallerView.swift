import SwiftUI
import T150Core

struct InstallerView: View {
    @ObservedObject var model: UpdateModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("1. Download from Thrustmaster") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Open the official T150 support page. Under Drivers, download the PC drivers + firmware package to Downloads. Do not run the Windows installer.")
                    Button("Open official T150 downloads", action: model.showOfficialWebsite)
                    Text("Reviewed in this app: \(FirmwareProfile.reviewed.map { "\($0.installerName) → T150 V\($0.version)" }.joined(separator: ", ")).")
                        .font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("2. Choose the downloaded .exe") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The app checks the exact official package, extracts its cabinet into a private folder, keeps only the supported T150 firmware, removes the rest, and validates the firmware before accessing the wheel.")
                    Button("Choose installer…", action: model.chooseInstaller)
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canAct)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            NoticeView(title: "A future firmware release?", message: "Use an app release whose compatibility list includes that installer. Unknown packages stop safely before extraction or USB access. There is no force-update switch.", symbol: "checkmark.shield")
        }
    }
}

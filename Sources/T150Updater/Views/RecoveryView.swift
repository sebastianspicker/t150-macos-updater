import SwiftUI

struct RecoveryView: View {
    @ObservedObject var model: UpdateModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Enter recovery mode manually") {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Leave wheel power connected. Set the base switch to PS3.", systemImage: "1.circle")
                    Label("Unplug only the wheel’s USB cable.", systemImage: "2.circle")
                    Label("Hold L3 + R3 on the wheel base, then reconnect USB while holding both.", systemImage: "3.circle")
                    Label("Release the buttons after connection. Check the connection below.", systemImage: "4.circle")
                    Text("The wheel should stay still. Its MODE light may be off. Use a direct USB connection where possible; avoid changing ports or hubs during an update.")
                        .foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            HStack {
                Button("Check recovery connection", action: model.refreshDevice)
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canAct)
                Button("Official illustrated guide", action: model.showRecoveryGuide)
            }
        }
    }
}

struct SafetyChecklist: View {
    @ObservedObject var model: UpdateModel
    var body: some View {
        GroupBox("Before saving backups") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("The wheel is securely mounted, with hands and objects clear of its rotation.", isOn: $model.secured)
                Toggle("Wheel power and Mac AC power are connected. The Mac’s lid will remain open.", isOn: $model.powerConnected)
                Toggle("The switch is on PS3, and only this Thrustmaster device is connected.", isOn: $model.ps3)
                Toggle("The USB connection is stable. I will not disconnect it or change ports during the update.", isOn: $model.stableUSB)
                Text("A direct USB connection is recommended. A hub can introduce additional connection or power failures; if it is unreliable, stop here and use another connection.")
                    .font(.callout).foregroundStyle(.secondary)
            }.toggleStyle(.checkbox).disabled(model.busy).padding(8)
        }
    }
}

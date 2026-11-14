import AppKit
import SwiftUI
import T150Core

struct ContentView: View {
    @ObservedObject var model: UpdateModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().interpolation(.high).frame(width: 52, height: 52)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("T150").font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text("Firmware Updater").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(UpdateStage.allCases, id: \.rawValue) { step in
                        StepRow(step: step, current: model.stage)
                    }
                }
                Spacer()
                Button("Help & recovery") { model.helpVisible = true }.buttonStyle(.link)
                Text("Independent utility\nFirmware supplied by Thrustmaster")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(26).frame(width: 225, alignment: .leading).background(.regularMaterial)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text(model.alreadyCurrent ? "NO UPDATE NEEDED" : "NATIVE macOS UTILITY")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if model.busy { ProgressView().controlSize(.small).accessibilityLabel("Operation in progress") }
                    }
                    Text(model.headline).font(.largeTitle.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(model.detail).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                    if let message = model.startupFailure {
                        NoticeView(title: "Updater unavailable", message: message, symbol: "exclamationmark.triangle")
                    } else {
                        stageContent
                    }
                    if let failure = model.failure {
                        NoticeView(title: "Operation stopped", message: failure, symbol: "exclamationmark.triangle")
                        if model.stage == .updating {
                            Button("Open recovery guidance") { model.helpVisible = true }
                        }
                    }
                    if model.firmware != nil {
                        Divider()
                        HStack {
                            Button("Show this session in Finder", action: model.showSession)
                            Spacer()
                            if !model.busy && model.stage != .updating {
                                Button("Choose another installer…", action: model.chooseInstaller)
                            }
                        }
                        Text("Backups and logs stay on this Mac. No account, telemetry, or automatic upload.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(36).frame(maxWidth: 780, alignment: .leading)
            }
        }
        .sheet(isPresented: $model.helpVisible) { HelpView(model: model) }
        .alert("Update the wheel now?", isPresented: $model.confirmUpdate) {
            Button("Cancel", role: .cancel) { }
            Button("Update firmware", action: model.update)
        } message: {
            Text((model.target?.requiresDoubleOptIn == true ? "You chose an experimental build. " : "") +
                 "Firmware will be written to the connected T150. Keep USB, wheel power, and Mac power connected until verification and restart finish. Keep the wheel secured and its rotation clear. Once writing starts, do not quit the app or close the Mac’s lid.")
        }
    }

    @ViewBuilder private var stageContent: some View {
        switch model.stage {
        case .installer:
            InstallerView(model: model)
        case .recovery:
            TargetPicker(model: model)
            RecoveryView(model: model)
        case .backup:
            TargetPicker(model: model)
            SafetyChecklist(model: model)
            Button("Save & verify two backups", action: model.prepareBackup)
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!model.canAct || !model.safetyReady)
        case .review:
            GroupBox("Ready to update") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Installed firmware", value: model.device?.applicationVersion.map { "V\($0)" } ?? "Verified by device checks")
                    LabeledContent("New firmware") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(model.target.map { "\($0.name) (V\($0.version))" } ?? "Unavailable")
                            if let target = model.target, target.name != target.title {
                                Text(target.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let target = model.target, !target.isOfficial {
                        LabeledContent("Image", value: target.requiresDoubleOptIn
                            ? "Modified, experimental: reviewed patch set, pinned SHA-256"
                            : "Modified: reviewed patch set, pinned SHA-256")
                    }
                    LabeledContent("Backups", value: "Two complete, matching flash images")
                    LabeledContent("Bootloader", value: "Verified and preserved")
                    LabeledContent("Application data to update", value: ByteCountFormatter.string(fromByteCount: Int64(model.plan.reduce(0) { $0 + $1.length }), countStyle: .file))
                }.padding(10)
            }
            Toggle("I know where my backups are saved. Power and USB are stable, and the wheel is still clear to calibrate.", isOn: $model.backupAcknowledged)
                .toggleStyle(.checkbox).disabled(model.busy)
            Button("Update to \(model.target?.name ?? "firmware")…") { model.confirmUpdate = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!model.canAct || !model.backupAcknowledged || model.target == nil)
        case .updating:
            NoticeView(title: model.busy ? "Keep everything connected" : "Your session is preserved",
                message: model.busy ? "There is no cancel button during writing. The native device tool performs bounded transfers, verifies the complete image, and only then allows a restart. Quitting and closing this window are blocked while it is working." : "A failed operation is never retried automatically. Keep the original backups and logs for recovery support.",
                symbol: model.busy ? "lock.shield" : "externaldrive")
            if model.verifiedAwaitingCheck {
                Button("Check the wheel", action: model.refreshDevice)
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canAct)
            }
        case .complete:
            Label(model.alreadyCurrent ? "No flash writes performed" : "Normal operating-mode version confirmed", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(.green)
            if !model.alreadyCurrent {
                if model.target?.role == .recommendedFix {
                    NextStepsView()
                }
                Text("Keep the saved session. It holds the backups of your original firmware. This app does not install a macOS force-feedback driver.")
                    .foregroundStyle(.secondary)
            } else {
                TargetPicker(model: model)
            }
        }
    }
}

/// Shown only when the reviewed installer offers more than one compiled target.
/// The official build, the fixes build and the recommended PS5 fix are always visible;
/// the other experimental builds sit in a collapsed group.
struct TargetPicker: View {
    @ObservedObject var model: UpdateModel
    @State private var showExtras = false

    var body: some View {
        if let targets = model.firmware?.profile.targets, targets.count > 1, let target = model.target {
            let main = targets.filter { $0.role != .extra }.sorted { order($0) < order($1) }
            let extras = targets.filter { $0.role == .extra }
            VStack(alignment: .leading, spacing: 12) {
                Text("Firmware to install").font(.headline)
                ForEach(main) { row($0, selected: target) }
                if !extras.isEmpty {
                    DisclosureGroup(isExpanded: $showExtras) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Earlier and alternative test builds, kept for completeness. You don\u{2019}t need them for the PS5 fix.")
                                .font(.callout).foregroundStyle(.secondary)
                            ForEach(extras) { row($0, selected: target) }
                        }.padding(.top, 8)
                    } label: {
                        Text("Other experimental builds (\(extras.count))").font(.callout)
                    }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(target.summary).fixedSize(horizontal: false, vertical: true)
                        if target.name != target.title {
                            Text("Full name: \(target.title)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        if !target.isOfficial {
                            Toggle("I understand this is modified firmware, not an official Thrustmaster release, and that I can return to the official firmware with this app.", isOn: $model.modifiedAcknowledged)
                                .toggleStyle(.checkbox).disabled(model.busy)
                        }
                        if target.requiresDoubleOptIn {
                            Toggle("I also understand this build is experimental. It changes how the wheel talks to a console. Only the PS5 stutter fix has been tried on a PS5 so far, on one tester\u{2019}s wheel; the others were tested in an emulator only. I will check it myself and switch back if anything behaves unexpectedly.", isOn: $model.experimentalAcknowledged)
                                .toggleStyle(.checkbox).disabled(model.busy || !model.modifiedAcknowledged)
                                .accessibilityHint("Second acknowledgement, required only for experimental builds")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }
            .onAppear { if target.role == .extra { showExtras = true } }
        }
    }

    private func order(_ target: FirmwareTarget) -> Int {
        switch target.role {
        case .official: return 0
        case .recommendedFix: return 1
        case .modified: return 2
        case .extra: return 3
        }
    }

    private func row(_ option: FirmwareTarget, selected: FirmwareTarget) -> some View {
        let isSelected = option.identifier == selected.identifier
        return Button { model.selectTarget(option.identifier) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3).foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(option.name).fontWeight(.semibold)
                        RoleBadge(role: option.role)
                    }
                    Text(option.tagline).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!model.canChangeTarget)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct RoleBadge: View {
    let role: FirmwareTarget.Role
    var body: some View {
        let (text, color): (String, Color) = switch role {
        case .official: ("Official", .secondary)
        case .modified: ("Bug fixes", .blue)
        case .recommendedFix: ("Recommended for PS5", .orange)
        case .extra: ("Test build", .secondary)
        }
        Text(text).font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

struct StepRow: View {
    let step: UpdateStage
    let current: UpdateStage
    var body: some View {
        let done = step.rawValue < current.rawValue || (step == .complete && current == .complete)
        let active = step == current && !done
        Label {
            Text(step.title).fontWeight(active ? .semibold : .regular)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : step.symbol)
                .foregroundStyle(done ? Color.green : (active ? Color.accentColor : Color.secondary))
        }
        .foregroundStyle(active ? Color.primary : Color.secondary)
        .accessibilityValue(done ? "Done" : (active ? "Current step" : ""))
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Shown after the recommended PS5 fix was installed and verified.
struct NextStepsView: View {
    var body: some View {
        GroupBox("Next steps") {
            VStack(alignment: .leading, spacing: 10) {
                Label("Connect the wheel to your PS5 the way you normally do.", systemImage: "1.circle")
                Label("Drive Assetto Corsa Competizione. On the tester\u{2019}s wheel the stutter was gone after this update.", systemImage: "2.circle")
                Label("Optional: to help confirm why the fix works, flip the PS/PC switch to PC while the game is running. The wheel then saves a record of what the console sent.", systemImage: "3.circle")
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }
}

struct NoticeView: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol).font(.headline)
                Text(message).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }
}

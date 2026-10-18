import Foundation
import IOKit.ps

enum PowerState {
    static var isOnAC: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else { return false }
        return source as String == kIOPSACPowerValue
    }
}

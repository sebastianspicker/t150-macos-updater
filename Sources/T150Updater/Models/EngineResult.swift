import Foundation

struct EngineResult: Decodable {
    struct Device: Decodable {
        let pid: Int?
        let applicationVersion: Int?
    }
    struct Run: Decodable {
        let address: Int
        let length: Int
    }
    let schema: Int
    let operation: String
    let ok: Bool
    let code: String
    let message: String
    let state: String?
    let profile: String?
    let device: Device?
    let plan: [Run]?
    let restartIssued: Bool?
}

enum UpdateStage: Int, CaseIterable {
    case installer, recovery, backup, review, updating, complete
    var title: String {
        switch self {
        case .installer: return "Choose firmware"
        case .recovery: return "Connect your wheel"
        case .backup: return "Save backups"
        case .review: return "Review update"
        case .updating: return "Update & verify"
        case .complete: return "Finished"
        }
    }
    var symbol: String {
        switch self {
        case .installer: return "square.and.arrow.down"
        case .recovery: return "cable.connector"
        case .backup: return "externaldrive.badge.checkmark"
        case .review: return "checklist"
        case .updating: return "arrow.triangle.2.circlepath"
        case .complete: return "checkmark.circle"
        }
    }
}

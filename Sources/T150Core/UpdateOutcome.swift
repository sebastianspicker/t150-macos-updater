/// What the app tells the user after an update attempt stopped. Decided from the
/// engine's reported results and its durable session markers, never from which call threw.
public enum UpdateOutcome: Equatable, Sendable {
    case notWritten, writeMayHaveStarted, verifiedNotRestarted, verifiedRestartSent

    /// - applyVerified: apply returned ok for the selected target (full readback matched).
    /// - applyStarted / restartStarted: the engine's `apply-started` / `restart-started` markers exist.
    /// - restartIssued: finish's reported flag, nil when finish gave no readable result.
    public static func after(applyVerified: Bool, applyStarted: Bool,
                             restartIssued: Bool?, restartStarted: Bool) -> UpdateOutcome {
        // The marker is saved just before the reset, so without a result it counts as sent.
        if applyVerified { return restartIssued ?? restartStarted ? .verifiedRestartSent : .verifiedNotRestarted }
        return applyStarted ? .writeMayHaveStarted : .notWritten
    }
}

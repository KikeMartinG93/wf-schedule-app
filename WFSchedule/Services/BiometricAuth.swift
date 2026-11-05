import Foundation
import LocalAuthentication

/// Face ID / Touch ID / device passcode gate used before revealing Keys codes.
enum BiometricAuth {
    enum Outcome: Equatable {
        case success
        case failed
        case cancelled
        case unavailable
    }

    /// Prompts for biometrics (or device passcode fallback). Safe to call from the main actor.
    static func authenticate(reason: String) async -> Outcome {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")
        var error: NSError?
        let policy = LAPolicy.deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: &error) else {
            return .unavailable
        }

        do {
            let ok = try await context.evaluatePolicy(policy, localizedReason: reason)
            return ok ? .success : .failed
        } catch let authError as LAError {
            switch authError.code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }
}

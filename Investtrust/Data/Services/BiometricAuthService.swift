//
//  BiometricAuthService.swift
//  Investtrust
//

import Foundation
import LocalAuthentication

/// Wraps `LocalAuthentication` for high‑assurance actions. Uses **device owner** authentication:
/// Face ID or Touch ID when enrolled, otherwise the device passcode — not third‑party facial matching.
enum BiometricAuthService {
    enum Failure: LocalizedError {
        case notAvailable
        case passcodeNotSet
        case cancelled
        case lockout
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Secure confirmation isn’t available on this device."
            case .passcodeNotSet:
                return "Set a device passcode (and optionally Face ID or Touch ID) in Settings to sign."
            case .cancelled:
                return "Authentication was cancelled."
            case .lockout:
                return "Too many failed attempts. Try again after unlocking your device in Settings."
            case .failed(let message):
                return message
            }
        }
    }

    /// Requires the person holding the device to authenticate (biometrics and/or passcode).
    @MainActor
    static func requireDeviceOwner(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var nsError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &nsError) else {
            throw mapCanEvaluate(nsError)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: mapEvaluate(error))
                }
            }
        }
    }

    /// Face ID / Touch ID only (`LocalAuthentication`), then returns the same `LAContext` for Keychain access.
    /// Simulator: **Features → Face ID → Enrolled**; success/failure follows **Matching Face** / **Non-matching Face**.
    @MainActor
    static func authenticateWithBiometricsReturningContext(reason: String) async throws -> LAContext {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var nsError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &nsError) else {
            throw mapCanEvaluate(nsError)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: mapEvaluate(error))
                }
            }
        }
        return context
    }

    private static func mapCanEvaluate(_ error: NSError?) -> Error {
        guard let error else { return Failure.notAvailable }
        return mapLAError(error)
    }

    private static func mapEvaluate(_ error: Error?) -> Error {
        guard let error else { return Failure.failed("Authentication failed.") }
        return mapLAError(error as NSError)
    }

    private static func mapLAError(_ nsError: NSError) -> Error {
        guard nsError.domain == LAErrorDomain,
              let code = LAError.Code(rawValue: nsError.code)
        else {
            return nsError
        }
        switch code {
        case .authenticationFailed:
            return Failure.failed("Authentication failed.")
        case .userCancel, .systemCancel, .appCancel, .invalidContext:
            return Failure.cancelled
        case .userFallback:
            return Failure.failed("Authentication wasn’t completed. Try again.")
        case .passcodeNotSet:
            return Failure.passcodeNotSet
        case .biometryNotAvailable:
            return Failure.notAvailable
        case .biometryNotEnrolled:
            return Failure.failed(
                "Enroll Face ID or Touch ID in Settings. In the Simulator choose Features → Face ID → Enrolled."
            )
        case .biometryLockout:
            return Failure.lockout
        case .notInteractive:
            return Failure.failed("Try again when the app is in the foreground.")
        @unknown default:
            return nsError
        }
    }
}

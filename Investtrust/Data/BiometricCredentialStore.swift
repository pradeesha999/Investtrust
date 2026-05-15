//
//  BiometricCredentialStore.swift
//  Investtrust
//

import Foundation
import LocalAuthentication
import Security

// Stores the last email/password sign-in behind Face ID / Touch ID (Keychain + biometric ACL).
enum BiometricCredentialStore {
    private static let service = "app.investtrust.biometricFirebaseLogin"
    private static let account = "emailPassword"
    private static let prefsKey = "investtrust.hasBiometricLoginCredentials"

    private struct Payload: Codable {
        var email: String
        var password: String
    }

    static var hasStoredCredentials: Bool {
        UserDefaults.standard.bool(forKey: prefsKey)
    }

    static func save(email: String, password: String) throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else { return }

        var cfError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &cfError
        ) else {
            throw cfError?.takeRetainedValue() ?? BiometricCredentialError.keychainAccess
        }

        let data = try JSONEncoder().encode(Payload(email: trimmed, password: password))

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: data,
        ]

        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BiometricCredentialError.saveFailed(status)
        }
        UserDefaults.standard.set(true, forKey: prefsKey)
    }

    // Reads credentials. Pass the **same** `LAContext` returned after a successful `evaluatePolicy` so Keychain uses that authentication (single Face ID / Touch ID prompt).
    static func readCredentials(authenticationContext: LAContext) throws -> (email: String, password: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: authenticationContext,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecUserCanceled || status == errSecAuthFailed {
                throw BiometricCredentialError.cancelled
            }
            if status == errSecItemNotFound {
                UserDefaults.standard.set(false, forKey: prefsKey)
                throw BiometricCredentialError.notFound
            }
            throw BiometricCredentialError.readFailed(status)
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return (payload.email, payload.password)
    }

    static func delete() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        UserDefaults.standard.set(false, forKey: prefsKey)
    }

    enum BiometricCredentialError: LocalizedError {
        case keychainAccess
        case saveFailed(OSStatus)
        case readFailed(OSStatus)
        case notFound
        case cancelled

        var errorDescription: String? {
            switch self {
            case .keychainAccess:
                return "Could not enable Face ID sign-in on this device."
            case .saveFailed:
                return "Could not save sign-in for Face ID."
            case .readFailed:
                return "Could not read saved sign-in. Try email sign-in instead."
            case .notFound:
                return "No saved sign-in for Face ID. Sign in with email once first."
            case .cancelled:
                return "Face ID sign-in was cancelled."
            }
        }
    }
}

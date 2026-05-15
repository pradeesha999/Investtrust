//
//  AuthService.swift
//  Investtrust
//

import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import Observation
import SwiftUI

// Central authentication and session state for the app.
// Observes Firebase Auth, syncs user profile from Firestore, and exposes sign-in/out actions.
@MainActor
@Observable
final class AuthService {
    var currentUserID: String?
    var currentUserEmail: String?
    var errorMessage: String?
    var isLoading = false  // true while a sign-in/sign-up/Google flow is in progress

    // Increments on each successful sign-in so the main tab resets to the Home tab
    private(set) var sessionEpoch = 0

    var activeProfile: UserProfile.ActiveProfile = .investor
    var roles: UserProfile.Roles = .init(investor: true, seeker: true)

    var isSignedIn: Bool { currentUserID != nil }

    // True when the user has previously signed in with email/password and stored credentials for biometrics
    var canSignInWithBiometrics: Bool { BiometricCredentialStore.hasStoredCredentials }

    private let userService: UserService
    private var authListener: AuthStateDidChangeListenerHandle?

    init(userService: UserService) {
        self.userService = userService

        let user = Auth.auth().currentUser
        currentUserID = user?.uid
        currentUserEmail = user?.email

        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                self.currentUserID = user?.uid
                self.currentUserEmail = user?.email
                if let user {
                    do {
                        try await self.userService.ensureUserDocumentExists(for: user)
                        try await self.userService.syncIdentityFromAuthIfNeeded(for: user)
                        if let profile = try await self.userService.fetchProfile(userID: user.uid) {
                            self.activeProfile = profile.activeProfile
                            self.roles = profile.roles
                        }
                    } catch {
                        self.errorMessage = FirestoreUserFacingMessage.text(for: error)
                    }
                } else {
                    self.activeProfile = .investor
                    self.roles = .init(investor: true, seeker: true)
                }
            }
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        isLoading = true
        do {
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await Auth.auth().signIn(withEmail: trimmed, password: password)
            try? BiometricCredentialStore.save(email: trimmed, password: password)
            syncLocalUserFromFirebase()
            sessionEpoch += 1
            acknowledgeSessionReady()
        } catch {
            isLoading = false
            errorMessage = (error as NSError).localizedDescription
        }
    }

    // `LocalAuthentication` Face ID / Touch ID, then Keychain read, then Firebase sign-in.
    func signInWithBiometrics() async {
        errorMessage = nil
        guard BiometricCredentialStore.hasStoredCredentials else {
            errorMessage = "Sign in with email and password once on this device to enable Face ID."
            return
        }
        isLoading = true
        do {
            let context = try await BiometricAuthService.authenticateWithBiometricsReturningContext(
                reason: "Sign in to Investtrust."
            )
            let (email, password) = try BiometricCredentialStore.readCredentials(authenticationContext: context)
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
            syncLocalUserFromFirebase()
            sessionEpoch += 1
            acknowledgeSessionReady()
        } catch let bioFailure as BiometricAuthService.Failure {
            isLoading = false
            errorMessage = bioFailure.localizedDescription
        } catch let credError as BiometricCredentialStore.BiometricCredentialError {
            isLoading = false
            errorMessage = credError.localizedDescription
        } catch {
            isLoading = false
            errorMessage = (error as NSError).localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        errorMessage = nil
        isLoading = true
        do {
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await Auth.auth().createUser(withEmail: trimmed, password: password)
            try? BiometricCredentialStore.save(email: trimmed, password: password)
            syncLocalUserFromFirebase()
            sessionEpoch += 1
            acknowledgeSessionReady()
        } catch {
            isLoading = false
            errorMessage = (error as NSError).localizedDescription
        }
    }

    // Call when the signed-in shell (`HomeView`) is on screen so the post–sign-in loading overlay can dismiss.
    func acknowledgeSessionReady() {
        isLoading = false
    }

    private func syncLocalUserFromFirebase() {
        let user = Auth.auth().currentUser
        currentUserID = user?.uid
        currentUserEmail = user?.email
    }

    // Sends Firebase’s password-reset email. Does not touch `errorMessage` (used for sign-in).
    func sendPasswordReset(email: String) async throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PasswordResetError.emptyEmail
        }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: trimmed)
        } catch {
            throw PasswordResetError.map(error)
        }
    }

    enum PasswordResetError: LocalizedError {
        case emptyEmail
        case invalidEmail
        case network
        case other(String)

        var errorDescription: String? {
            switch self {
            case .emptyEmail:
                return "Enter the email you used to sign up."
            case .invalidEmail:
                return "That doesn’t look like a valid email address."
            case .network:
                return "Check your connection and try again."
            case .other(let message):
                return message
            }
        }

        static func map(_ error: Error) -> PasswordResetError {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain {
                return .network
            }
            if let code = AuthErrorCode(rawValue: ns.code) {
                switch code {
                case .invalidEmail:
                    return .invalidEmail
                case .networkError:
                    return .network
                default:
                    break
                }
            }
            return .other(ns.localizedDescription)
        }
    }

    func signInWithGoogle() async {
        errorMessage = nil
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Missing Firebase client ID. Check GoogleService-Info.plist."
            return
        }

        isLoading = true

        let configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = configuration

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController
        else {
            errorMessage = "Could not find a view controller for Google sign-in."
            isLoading = false
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google sign-in did not return an ID token."
                isLoading = false
                return
            }
            let accessToken = result.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            let authResult = try await Auth.auth().signIn(with: credential)
            BiometricCredentialStore.delete()
            try await userService.ensureUserDocumentExists(for: authResult.user)
            try await userService.syncIdentityFromAuthIfNeeded(for: authResult.user)
            syncLocalUserFromFirebase()
            sessionEpoch += 1
            acknowledgeSessionReady()
        } catch {
            let ns = error as NSError
            if ns.domain == "com.google.GIDSignIn" && ns.code == GIDSignInError.canceled.rawValue {
                isLoading = false
                return
            }
            errorMessage = ns.localizedDescription
            isLoading = false
        }
    }

    func signOut() {
        errorMessage = nil
        isLoading = false
        sessionEpoch = 0
        HomeWidgetSnapshotWriter.clearForSignedOut()
        Task {
            await SessionMediaCache.shared.clear()
            await MainActor.run {
                NotificationCenter.default.post(name: .investtrustSessionMediaDidReset, object: nil)
            }
        }
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }
    
    func switchActiveProfile(_ profile: UserProfile.ActiveProfile) async {
        guard let userID = currentUserID else { return }
        if profile == .investor && !roles.investor { return }
        if profile == .seeker && !roles.seeker { return }
        
        let previous = activeProfile
        activeProfile = profile
        do {
            try await userService.updateActiveProfile(userID: userID, activeProfile: profile)
            HomeWidgetSnapshotWriter.updateActiveProfile(auth: self)
        } catch {
            activeProfile = previous
            errorMessage = (error as NSError).localizedDescription
        }
    }

    static var previewSignedOut: AuthService {
        AuthService(userService: UserService())
    }

    static var previewSignedIn: AuthService {
        let service = AuthService(userService: UserService())
        service.currentUserID = "preview"
        service.currentUserEmail = "preview@investtrust.app"
        return service
    }
}

extension AuthService {
    // App-wide accent for controls, tab bar, and highlights (depends on `activeProfile`).
    var accentColor: Color {
        ProfileTheme.accent(for: activeProfile)
    }
}


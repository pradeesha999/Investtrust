//
//  AuthService.swift
//  Investtrust
//

import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import Observation
import SwiftUI

@MainActor
@Observable
final class AuthService {
    var currentUserID: String?
    var currentUserEmail: String?
    var errorMessage: String?
    var isLoading = false
    var activeProfile: UserProfile.ActiveProfile = .investor
    var roles: UserProfile.Roles = .init(investor: true, seeker: true)

    var isSignedIn: Bool { currentUserID != nil }

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
                        if let profile = try await self.userService.fetchProfile(userID: user.uid) {
                            self.activeProfile = profile.activeProfile
                            self.roles = profile.roles
                        }
                    } catch {
                        self.errorMessage = (error as NSError).localizedDescription
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
        defer { isLoading = false }
        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await Auth.auth().createUser(withEmail: email, password: password)
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }

    func signInWithGoogle() async {
        errorMessage = nil
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Missing Firebase client ID. Check GoogleService-Info.plist."
            return
        }

        isLoading = true
        defer { isLoading = false }

        let configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = configuration

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController
        else {
            errorMessage = "Could not find a view controller for Google sign-in."
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google sign-in did not return an ID token."
                return
            }
            let accessToken = result.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            _ = try await Auth.auth().signIn(with: credential)
        } catch {
            let ns = error as NSError
            if ns.domain == "com.google.GIDSignIn" && ns.code == GIDSignInError.canceled.rawValue {
                return
            }
            errorMessage = ns.localizedDescription
        }
    }

    func signOut() {
        errorMessage = nil
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


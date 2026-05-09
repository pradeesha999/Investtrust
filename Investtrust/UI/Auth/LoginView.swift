//
//  LoginView.swift
//  Investtrust
//

import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var auth
    @State private var email = ""
    @State private var password = ""
    @State private var showForgotPassword = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 0) {
                        titleBlock

                        authCard {
                            fieldSection(title: "Email", isFocused: focusedField == .email) {
                                TextField("Email", text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .email)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .password }
                            }
                            .padding(.top, 4)

                            fieldSection(title: "Password", isFocused: focusedField == .password) {
                                SecureField("Password", text: $password)
                                    .textContentType(.password)
                                    .textInputAutocapitalization(.never)
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(.go)
                                    .onSubmit { Task { await signIn() } }
                            }
                            .padding(.top, 20)

                            forgotPasswordRow
                                .padding(.top, 12)

                            if let message = auth.errorMessage {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .padding(.top, 12)
                                    .accessibilityIdentifier("authError")
                            }

                            signInButton
                                .padding(.top, 18)

                            if auth.canSignInWithBiometrics {
                                faceIDSignInButton
                                    .padding(.top, 10)
                            }

                            signUpFooter
                                .padding(.top, 22)

                            googleButton
                                .padding(.top, 20)
                        }
                        .padding(.top, 20)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.white.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet(initialEmail: email)
        }
    }

    private func authCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 14, y: 6)
    }

    private var titleBlock: some View {
        VStack(alignment: .center, spacing: 8) {
            Image("LoginLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .shadow(color: AuthTheme.primaryPink.opacity(0.14), radius: 20, y: 10)
                .padding(.bottom, 10)
            Text("Welcome Back")
                .font(AuthTheme.titleLarge)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
            Text("Sign in to continue")
                .font(.subheadline)
                .foregroundStyle(AuthTheme.subtitleMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func fieldSection(title: String, isFocused: Bool, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AuthTheme.fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: AuthTheme.fieldCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AuthTheme.fieldCornerRadius, style: .continuous)
                        .strokeBorder(isFocused ? AuthTheme.primaryPink : AuthTheme.fieldBorder, lineWidth: isFocused ? 2 : 1)
                )
                .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
    }

    private var forgotPasswordRow: some View {
        HStack {
            Spacer(minLength: 0)
            Button("Forgot password?") {
                showForgotPassword = true
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AuthTheme.primaryPink)
            .padding(.vertical, 8)
        }
    }

    private var faceIDSignInButton: some View {
        Button {
            Task { await auth.signInWithBiometrics() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "faceid")
                    .font(.title2)
                    .foregroundStyle(AuthTheme.primaryPink)
                Text("Sign in with Face ID")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AuthTheme.primaryPink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(AuthTheme.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: AuthTheme.buttonCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AuthTheme.buttonCornerRadius, style: .continuous)
                    .strokeBorder(AuthTheme.primaryPink.opacity(0.45), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(auth.isLoading)
        .accessibilityLabel("Sign in with Face ID")
    }

    private var signInButton: some View {
        Button(action: { Task { await signIn() } }) {
            ZStack {
                if auth.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Sign in")
                        .font(.headline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(AuthTheme.primaryPink, in: RoundedRectangle(cornerRadius: AuthTheme.buttonCornerRadius, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(auth.isLoading || !isFormValid)
        .opacity(isFormValid ? 1 : 0.45)
    }

    private var signUpFooter: some View {
        HStack(spacing: 4) {
            Text("Don't have an account?")
                .foregroundStyle(.secondary)
            NavigationLink {
                SignUpView()
            } label: {
                Text("Sign up")
                    .fontWeight(.semibold)
                    .foregroundStyle(AuthTheme.primaryPink)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var googleButton: some View {
        Button {
            Task { await auth.signInWithGoogle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "g.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
                Text("Continue with Google")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AuthTheme.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: AuthTheme.buttonCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AuthTheme.buttonCornerRadius, style: .continuous)
                    .strokeBorder(AuthTheme.fieldBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(auth.isLoading)
        .accessibilityLabel("Continue with Google")
    }

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= 6
    }

    private func signIn() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        await auth.signIn(email: trimmed, password: password)
    }
}

// MARK: - Forgot password

private struct ForgotPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    let initialEmail: String

    @State private var resetEmail = ""
    @State private var isSending = false
    @State private var errorText: String?
    @State private var didSucceed = false
    @FocusState private var resetEmailFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if didSucceed {
                    successView
                } else {
                    formView
                }
            }
            .navigationTitle(didSucceed ? "Check your email" : "Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSucceed ? "Done" : "Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AuthTheme.primaryPink)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            resetEmail = initialEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            resetEmailFocused = true
        }
    }

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("We’ll email you a link to choose a new password.")
                    .font(.subheadline)
                    .foregroundStyle(AuthTheme.subtitleMuted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Email")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    TextField("you@example.com", text: $resetEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($resetEmailFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AuthTheme.fieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AuthTheme.fieldCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AuthTheme.fieldCornerRadius, style: .continuous)
                                .strokeBorder(resetEmailFocused ? AuthTheme.primaryPink : AuthTheme.fieldBorder, lineWidth: resetEmailFocused ? 2 : 1)
                        )
                        .animation(.easeInOut(duration: 0.2), value: resetEmailFocused)
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button(action: { Task { await sendReset() } }) {
                    ZStack {
                        if isSending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Send reset link")
                                .font(.headline.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AuthTheme.primaryPink, in: RoundedRectangle(cornerRadius: AuthTheme.buttonCornerRadius, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isSending || resetEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(resetEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)

                Text("Check your spam folder if you don’t see it within a few minutes.")
                    .font(.caption)
                    .foregroundStyle(AuthTheme.subtitleMuted)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.palette)
                .foregroundStyle(AuthTheme.primaryPink, Color(.systemGray4))
                .padding(.top, 8)

            Text("If an account exists for \(maskedEmail), we sent a link to reset your password.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var maskedEmail: String {
        let t = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "that address" : t
    }

    private func sendReset() async {
        errorText = nil
        isSending = true
        defer { isSending = false }

        do {
            try await auth.sendPasswordReset(email: resetEmail)
            didSucceed = true
            resetEmailFocused = false
        } catch let resetError as AuthService.PasswordResetError {
            errorText = resetError.localizedDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
    .environment(AuthService.previewSignedOut)
}


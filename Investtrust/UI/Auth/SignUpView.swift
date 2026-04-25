//
//  SignUpView.swift
//  Investtrust
//

import SwiftUI

struct SignUpView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password, confirm
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 0) {
                        header

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
                        .padding(.top, 28)

                        fieldSection(title: "Password", isFocused: focusedField == .password) {
                            SecureField("At least 6 characters", text: $password)
                                .textContentType(.newPassword)
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .confirm }
                        }
                        .padding(.top, 24)

                        fieldSection(title: "Confirm password", isFocused: focusedField == .confirm) {
                            SecureField("Re-enter password", text: $confirmPassword)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .confirm)
                                .submitLabel(.go)
                                .onSubmit { Task { await signUp() } }
                        }
                        .padding(.top, 24)

                        Text(passwordMatchHint)
                            .font(.caption)
                            .foregroundStyle(passwordsMatch ? Color.secondary : Color.orange)
                            .padding(.top, 8)

                        if let message = auth.errorMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.top, 12)
                        }

                        createAccountButton
                            .padding(.top, 24)

                        googleButton
                            .padding(.top, 28)

                        signInFooter
                            .padding(.top, 24)
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
        .background {
            AuthScreenBackground()
        }
        .navigationTitle("Create account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .center, spacing: 8) {
            Image("LoginLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .shadow(color: AuthTheme.primaryPink.opacity(0.14), radius: 20, y: 10)
                .padding(.bottom, 4)
            Text("Join to post or support opportunities.")
                .font(.subheadline)
                .foregroundStyle(AuthTheme.subtitleMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
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

    private var signInFooter: some View {
        HStack(spacing: 4) {
            Text("Already have an account?")
                .foregroundStyle(.secondary)
            Button("Sign in") {
                dismiss()
            }
            .buttonStyle(.plain)
            .fontWeight(.semibold)
            .foregroundStyle(AuthTheme.primaryPink)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var createAccountButton: some View {
        Button {
            Task { await signUp() }
        } label: {
            ZStack {
                if auth.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Create account")
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
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && password.count >= 6
            && password == confirmPassword
    }

    private var passwordsMatch: Bool {
        !confirmPassword.isEmpty && password == confirmPassword
    }

    private var passwordMatchHint: String {
        if confirmPassword.isEmpty {
            return "Use at least 6 characters."
        }
        return passwordsMatch ? "Passwords match." : "Passwords do not match yet."
    }

    private func signUp() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard password == confirmPassword else {
            auth.errorMessage = "Passwords do not match."
            return
        }
        await auth.signUp(email: trimmed, password: password)
    }
}

#Preview {
    NavigationStack {
        SignUpView()
    }
    .environment(AuthService.previewSignedOut)
}


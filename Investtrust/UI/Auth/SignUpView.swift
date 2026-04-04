//
//  SignUpView.swift
//  Investtrust
//

import SwiftUI

struct SignUpView: View {
    @Environment(AuthService.self) private var auth
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

                        fieldSection(title: "Email") {
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

                        fieldSection(title: "Password") {
                            SecureField("At least 6 characters", text: $password)
                                .textContentType(.newPassword)
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .confirm }
                        }
                        .padding(.top, 24)

                        fieldSection(title: "Confirm password") {
                            SecureField("Re-enter password", text: $confirmPassword)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .confirm)
                                .submitLabel(.go)
                                .onSubmit { Task { await signUp() } }
                        }
                        .padding(.top, 24)

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
                .padding(.bottom, 10)
            Text("Create Account")
                .font(AuthTheme.titleLarge)
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
            Text("Join to post or support opportunities.")
                .font(.subheadline)
                .foregroundStyle(AuthTheme.subtitleMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func fieldSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AuthTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(AuthTheme.fieldBorder, lineWidth: 1.5)
                )
        }
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
            .frame(height: 44)
            .background(AuthTheme.primaryPink, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
            .background(AuthTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(AuthTheme.fieldBorder, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(auth.isLoading)
    }

    private var isFormValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && password.count >= 6
            && password == confirmPassword
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


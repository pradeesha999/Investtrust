//
//  LoginView.swift
//  Investtrust
//

import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var auth
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBlock
                    .padding(.top, 8)

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
                .padding(.top, 40)

                fieldSection(title: "Password") {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await signIn() } }
                }
                .padding(.top, 24)

                forgotPasswordRow
                    .padding(.top, 16)

                if let message = auth.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.top, 12)
                        .accessibilityIdentifier("authError")
                }

                signInButton
                    .padding(.top, 20)

                signUpFooter
                    .padding(.top, 28)

                googleButton
                    .padding(.top, 36)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AuthTheme.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome Back")
                .font(AuthTheme.titleLarge)
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text("Sign in to continue")
                .font(.subheadline)
                .foregroundStyle(AuthTheme.subtitleMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var forgotPasswordRow: some View {
        HStack {
            Spacer(minLength: 0)
            Button("Forgot password?") {}
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AuthTheme.primaryPink)
        }
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
            .frame(height: 44)
            .background(AuthTheme.primaryPink, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(auth.isLoading || !isFormValid)
        .opacity(isFormValid ? 1 : 0.45)
    }

    private var signUpFooter: some View {
        HStack(spacing: 4) {
            Text("Don't have an account?")
                .foregroundStyle(Color(white: 0.35))
            NavigationLink {
                SignUpView()
            } label: {
                Text("Sign up")
                    .fontWeight(.semibold)
                    .foregroundStyle(AuthTheme.primaryPink)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
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
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= 6
    }

    private func signIn() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        await auth.signIn(email: trimmed, password: password)
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
    .environment(AuthService.previewSignedOut)
}


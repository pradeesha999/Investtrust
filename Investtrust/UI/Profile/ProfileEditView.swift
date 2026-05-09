import SwiftUI
import FirebaseAuth
import PhotosUI
import UIKit

/// Shared profile form for investors and opportunity builders (stored in `users.profile`).
struct ProfileEditView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    private let userService = UserService()

    @State private var legalFullName = ""
    @State private var phoneNumber = ""
    @State private var country = ""
    @State private var city = ""
    @State private var shortBio = ""
    @State private var experienceLevel: ProfileExperienceLevel = .beginner
    @State private var pastWorkProjects = ""
    @State private var avatarURL = ""
    @State private var authPhotoURL = ""
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedAvatarData: Data?

    @State private var isSaving = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var saveAlertTitle = ""
    @State private var saveAlertMessage = ""
    @State private var showSaveAlert = false

    var body: some View {
        Form {
            Section {
                Text("Shared across your account. Investors must complete required fields before sending requests.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Identity") {
                TextField("Legal full name", text: $legalFullName)
                    .textContentType(.name)
                LabeledContent("Email") {
                    Text(auth.currentUserEmail ?? "—")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                TextField("Phone number", text: $phoneNumber)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                TextField("Country", text: $country)
                TextField("City", text: $city)
            }

            Section("Photo") {
                if let selectedAvatarData,
                   let preview = UIImage(data: selectedAvatarData) {
                    HStack(spacing: 12) {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color(.separator).opacity(0.25), lineWidth: 1))
                        Text("Selected photo will be uploaded when you save.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                    Label("Upload from gallery", systemImage: "photo.on.rectangle")
                }

                TextField("Profile picture URL (optional)", text: $avatarURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                if !authPhotoURL.isEmpty {
                    Button {
                        avatarURL = authPhotoURL
                    } label: {
                        Label("Use Google profile photo", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
                if !avatarURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Remove profile photo", role: .destructive) {
                        avatarURL = ""
                        selectedAvatarData = nil
                    }
                }
                Text("Use a full URL like https://example.com/photo.jpg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About you") {
                TextField("Short bio (who you are, what you do)", text: $shortBio, axis: .vertical)
                    .lineLimit(3...6)
                Picker("Experience level", selection: $experienceLevel) {
                    ForEach(ProfileExperienceLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                TextField("Past work / projects (optional)", text: $pastWorkProjects, axis: .vertical)
                    .lineLimit(2...8)
            }

            if let loadError {
                Section {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            if let saveError {
                Section {
                    Text(saveError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Your profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { @MainActor in
                            await save()
                        }
                    }
                }
            }
        }
        .alert(saveAlertTitle, isPresented: $showSaveAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveAlertMessage)
        }
        .task(id: auth.currentUserID) {
            await load()
        }
        .onChange(of: selectedAvatarItem) { _, item in
            guard let item else { return }
            Task { await loadPickedAvatar(item) }
        }
    }

    @MainActor
    private func load() async {
        guard let uid = auth.currentUserID else {
            loadError = "Please sign in."
            return
        }
        loadError = nil
        do {
            if let authUser = Auth.auth().currentUser,
               let s = authUser.photoURL?.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines),
               !s.isEmpty {
                authPhotoURL = s
            } else {
                authPhotoURL = ""
            }
            if let p = try await userService.fetchProfile(userID: uid) {
                let d = p.profileDetails
                legalFullName = d?.legalFullName ?? p.displayName ?? ""
                phoneNumber = d?.phoneNumber ?? ""
                country = d?.country ?? ""
                city = d?.city ?? ""
                shortBio = d?.shortBio ?? ""
                experienceLevel = d?.experienceLevel ?? .beginner
                pastWorkProjects = d?.pastWorkProjects ?? ""
                avatarURL = p.avatarURL ?? ""
                if avatarURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    avatarURL = authPhotoURL
                }
            }
        } catch {
            loadError = FirestoreUserFacingMessage.text(for: error)
        }
    }

    @MainActor
    private func save() async {
        guard let uid = auth.currentUserID else {
            saveError = "Please sign in to save your profile."
            saveAlertTitle = "Sign in required"
            saveAlertMessage = saveError ?? ""
            showSaveAlert = true
            return
        }
        saveError = nil
        showSaveAlert = false

        let existing = try? await userService.fetchProfile(userID: uid)
        let trimmedPast = pastWorkProjects.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = ProfileDetails(
            legalFullName: legalFullName,
            phoneNumber: phoneNumber,
            country: country,
            city: city,
            shortBio: shortBio,
            experienceLevel: experienceLevel,
            pastWorkProjects: trimmedPast.isEmpty ? nil : trimmedPast,
            verificationStatus: existing?.profileDetails?.verificationStatus ?? .unverified
        )

        guard next.isCompleteForInvesting else {
            saveError = "Still missing: \(next.missingProfileHints.joined(separator: ", "))."
            saveAlertTitle = "Profile incomplete"
            saveAlertMessage = saveError ?? ""
            showSaveAlert = true
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await userService.saveProfileDetails(userID: uid, details: next)
            let finalAvatarURL: String?
            if let selectedAvatarData {
                let payload = ImageJPEGUploadPayload.jpegForUpload(from: selectedAvatarData)
                try await InappropriateImageGate.validateImageDataForUpload(payload)
                let filename = "avatar-\(uid)-\(UUID().uuidString.prefix(8)).jpg"
                let uploaded = try await CloudinaryImageUploadClient.uploadImageData(payload, filename: filename)
                finalAvatarURL = uploaded.secureURL
            } else {
                let trimmedAvatar = avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
                finalAvatarURL = trimmedAvatar.isEmpty ? nil : trimmedAvatar
            }
            try await userService.updateAvatarURL(userID: uid, url: finalAvatarURL)
            dismiss()
        } catch {
            saveError = (error as NSError).localizedDescription
            saveAlertTitle = "Couldn't save"
            saveAlertMessage = saveError ?? ""
            showSaveAlert = true
        }
    }

    @MainActor
    private func loadPickedAvatar(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self), !data.isEmpty {
                selectedAvatarData = data
            }
        } catch {
            saveError = FirestoreUserFacingMessage.text(for: error)
        }
    }
}

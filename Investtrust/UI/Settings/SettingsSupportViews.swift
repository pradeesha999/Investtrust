import SwiftUI

enum AppSupportLinks {
    static let contactEmail = "support@investtrust.app"
    static let helpEmailSubject = "Investtrust help request"
}

// MARK: - Help center

struct SettingsHelpCenterView: View {
    private let faqs: [(String, String)] = [
        (
            "How do I invest in a listing?",
            "From Home, open Explore (toolbar) or use the Invest tab to find listings. Review the terms, tap Invest, and enter your amount. The seeker can accept or decline your request."
        ),
        (
            "What does “pending” mean?",
            "Your request was sent but the seeker has not accepted it yet. You’ll see updates on the Invest tab and in Chat."
        ),
        (
            "Where do I see my portfolio?",
            "Use the Home tab for totals, active deals, and projected timelines. The Invest tab lists your requests in detail."
        ),
        (
            "How are returns calculated?",
            "Dashboard figures labeled “projected” or “expected” are estimates based on the terms shown on each listing. Actual results depend on the agreement and real-world performance."
        )
    ]

    var body: some View {
        List {
            Section {
                Text("Quick answers to common questions. For anything else, use Contact us.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            Section("FAQ") {
                ForEach(Array(faqs.enumerated()), id: \.offset) { _, item in
                    DisclosureGroup {
                        Text(item.1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } label: {
                        Text(item.0)
                            .font(.body.weight(.medium))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Help center")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Contact us

struct SettingsContactUsView: View {
    private var mailURL: URL? {
        let encodedSubject = AppSupportLinks.helpEmailSubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let raw = "mailto:\(AppSupportLinks.contactEmail)?subject=\(encodedSubject)"
        return URL(string: raw)
    }

    var body: some View {
        List {
            Section {
                Text("We’re happy to help with account issues, bugs, or general questions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Group {
                    if let mailURL {
                        Link(destination: mailURL) {
                            Label(AppSupportLinks.contactEmail, systemImage: "envelope.fill")
                                .font(.body.weight(.medium))
                        }
                    } else {
                        Text(AppSupportLinks.contactEmail)
                    }
                }
            } header: {
                Text("Email")
            } footer: {
                Text("Opens your mail app. Update the support address in code if your team uses a different inbox.")
                    .font(.footnote)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Contact us")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Terms & conditions

struct SettingsTermsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last updated: April 2026")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Group {
                    sectionTitle("1. Agreement")
                    bodyText(
                        "By using Investtrust, you agree to these terms. If you do not agree, do not use the app."
                    )

                    sectionTitle("2. Not financial advice")
                    bodyText(
                        "Investtrust is a platform to connect investors and opportunity seekers. Nothing in the app is investment, legal, or tax advice. You are responsible for your own decisions and due diligence."
                    )

                    sectionTitle("3. Risks")
                    bodyText(
                        "Investments may lose value. Past or projected performance does not guarantee future results. Only commit funds you can afford to lose."
                    )

                    sectionTitle("4. Accounts & conduct")
                    bodyText(
                        "You must provide accurate information and keep your account secure. We may suspend access for abuse, fraud, or violations of applicable law."
                    )

                    sectionTitle("5. Changes")
                    bodyText(
                        "We may update these terms. Continued use after changes means you accept the updated terms."
                    )

                    sectionTitle("6. Contact")
                    bodyText(
                        "Questions about these terms: use Contact us in Settings or write to \(AppSupportLinks.contactEmail)."
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Terms & conditions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .padding(.top, 4)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

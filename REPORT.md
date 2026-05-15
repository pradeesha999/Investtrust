# Investtrust — Final Project Report

> Native iOS investment marketplace that takes a deal from listing and discovery through negotiation, digital agreement signing, principal disbursement, repayment tracking, and closure — implemented in Swift / SwiftUI on Firebase + Cloudinary.

This report is the as-built complement to `proposal.md`. The proposal scope is the contract; every section here either confirms the proposed behaviour against the shipped code, or documents the implementation decisions taken to deliver it.

---

## Table of Contents

1. Executive Summary
2. Goals and Outcomes (vs. proposal)
3. Target Users and Roles
4. End-to-End User Journey
5. System Architecture
6. Domain Model and Data Schema
7. Investment Lifecycle and State Machines
8. Feature Catalogue (As Built)
9. Advanced iOS Capabilities
10. Backend, Storage and Security
11. UI / UX and Accessibility
12. Quality, Testing and Build Tooling
13. Project Structure
14. Known Limitations and Roadmap
15. Conclusion
16. Appendix A — Firestore Collections
17. Appendix B — Key Files Map

---

## 1) Executive Summary

**Application name:** Investtrust
**Domain:** FinTech / Investment marketplace / Agreement and repayment workflow
**Platform:** Native iOS (Swift, SwiftUI, iOS 17+ with `@Observable`, WidgetKit, EventKit, LocalAuthentication, PDFKit)
**Backend:** Firebase (Authentication, Cloud Firestore, Cloud Storage) + Cloudinary (media)
**Bundle:** `Investtrust` app target + `InvesttrustWidgetExtension` (Home Screen widget) + `WidgetShared` (App Group payload)

Investtrust connects **Opportunity Seekers** (founders / borrowers) and **Investors** (lenders / equity participants) on a single platform that does not stop at matchmaking. It owns the full lifecycle:

1. Seeker publishes a funding opportunity (loan or equity).
2. Investor discovers, evaluates, and submits a structured request or a negotiated offer.
3. Both parties review and digitally sign a Memorandum of Agreement (MOA) PDF rendered on-device by Investtrust.
4. The investor sends principal with transfer proof; the seeker confirms receipt.
5. The platform generates a deterministic repayment schedule (loan) or milestone tracker (equity) and tracks each installment with **dual confirmation + proof of payment**.
6. Closure happens automatically when the final installment is mutually confirmed.

Every state transition is captured as Firestore fields, so dashboards, in-app notifications, the iOS calendar, and the Home Screen widget all read the same source of truth.

---

## 2) Goals and Outcomes (vs. proposal)

| Proposal commitment | Delivered? | Implementation notes |
|---|---|---|
| Two-sided marketplace (seeker + investor) | Yes | Single account with role switching; one auth identity, two operating modes. |
| Email + Google + biometric sign-in | Yes | `AuthService` (Firebase Auth + Google Sign-In SDK) and `BiometricAuthService` / `BiometricCredentialStore` with Keychain-backed Face ID / Touch ID re-auth. |
| Role-aware dashboards and tabs | Yes | `DashboardView` switches `InvestorDashboardView` ↔ `SeekerHomeDashboardView`; the Action tab swaps between `InvestorActionTabView` and `SeekerDashboardView` by `auth.activeProfile`. |
| Opportunity publish / edit / lifecycle | Yes | `CreateOpportunityWizardView`, `EditOpportunityView`, and `OpportunityService` with guard rails for blocking states. |
| Request + offer negotiation flow | Yes | `InvestProposalSheet`, `OfferService`, `InvestmentService.createInvestmentRequest` and `createOrUpdateOfferRequest`. Investors can supersede their own pending offer rather than create duplicates. |
| Digital MOA agreement lifecycle | Yes | `InvestmentService.acceptInvestmentRequest` snapshots terms; `signAgreement` writes signatures; `MOAPDFBuilder` renders the multi-page PDF; `InvestmentAgreementReviewView` + `SignaturePadView` collect the signatures. |
| Loan / revenue / equity post-deal tracking | Loan and equity delivered. Revenue share modeled but not surfaced as a separate listing type in the final wizard. | `LoanInstallment` + `LoanScheduleGenerator`, `EquityVentureUpdate` / `EquityMilestoneProgress`, dual-confirmation flows for installments. |
| User-to-user chat with opportunity context | Yes | `ChatService` with canonical pair-based chat IDs, `ChatListView`, `ChatRoomView`, and structured `OpportunityInquirySnapshot` / `InvestmentRequestSnapshot` / `InvestmentOfferSnapshot` message kinds. |
| Calendar-linked commitment tracking (EventKit) | Yes | `LoanRepaymentCalendarSync` writes one all-day event per unpaid installment (with a one-day-before alarm) and per milestone. User consent is gated through an in-app alert and an iOS permission request. |
| Home Screen widget (WidgetKit) | Yes | `InvesttrustHomeWidget` + `HomeWidgetSnapshot` via an App Group (`group.investtrust.shared`). |
| Charts / investor dashboard | Yes | `InvestorPortfolioMetrics` plus the SwiftUI Charts framework in `InvestorDashboardView`. |
| Accessibility settings | Yes | `AppAccessibility`, `AppAccessibilityPreferences`, reduce-motion + haptics toggles, dynamic type, system + in-app high contrast. |
| In-app notifications | Yes | `InAppNotificationService` builds a live action queue from Firestore data; `InAppNotificationsView` is reachable from a top-bar bell. |
| Document integrity for signed PDFs | Yes | `InvestmentService.finalizeMOAAndLoanSchedule` stores a SHA-256 (`moaContentHash`) of the final PDF bytes. |

Items where the final implementation differs from or extends the proposal are flagged in [Section 14](#14-known-limitations-and-roadmap).

---

## 3) Target Users and Roles

Investtrust is a one-account / two-role product. Each Firestore user document carries `roles.investor` and `roles.seeker` (both default `true`) plus an `activeProfile` enum (`UserProfile.ActiveProfile`). The app shell observes the active profile and:

- swaps the tab labels and icons (Invest / Opportunity),
- swaps the primary dashboard,
- changes the accent colour (`ProfileTheme.investorBlue` vs `ProfileTheme.seekerPink`),
- re-derives the in-app notification feed and the Home widget timeline.

There is no role-specific signup. A user becomes a seeker by creating an opportunity and an investor by sending a request. Mode switching is in `SettingsContentView`.

---

## 4) End-to-End User Journey

The flow below is the production path implemented in code, not a wishlist. File references in parentheses point to the entry surface.

### 4.1 Sign-in / Onboarding
- `LoginView`, `SignUpView` (email + password, password reset, Google sign-in).
- After a successful email sign-in, credentials are saved with `BiometricCredentialStore`. Subsequent launches show a Face ID / Touch ID button (`BiometricAuthService.authenticateWithBiometricsReturningContext`).
- `RootView` flips between `AuthRootView` and `HomeView` on `auth.isSignedIn`; a transient `SessionLoadingOverlay` covers the cold-start sign-in race.

### 4.2 Seeker — Publish an opportunity
- `CreateOpportunityWizardView` is a 6-step multi-page wizard: investment type → overview → funding + risk → type-specific terms → use of funds + milestones → review and submit.
- `OpportunityService.createOpportunity` validates inputs, uploads images and an optional pitch video to Cloudinary via `CloudinaryImageUploadClient` / `CloudinaryVideoUploadClient`, runs an inappropriate-image gate (`InappropriateImageGate`), and writes the new `opportunities/{id}` document with normalized terms.
- The seeker manages their own listings from the **Opportunity tab** (`SeekerDashboardView`), can edit (`EditOpportunityView`) or delete (`OpportunityService.deleteOpportunity`) when no request is in a blocking state.

### 4.3 Investor — Browse and request
- The **Invest tab** is segmented (`InvestorActionTabView`): Explore / My Requests / Ongoing / Completed.
- Explore uses `MarketBrowseView` and `InvestorMarketView` (search, type and risk filters, sort by newest / amount).
- `OpportunityDetailView` shows the listing with hero media, key numbers, terms, milestones, and seller profile. From here the investor either submits a default request, a negotiated offer (`InvestProposalSheet`), or opens the chat (`ChatService.getOrCreateChat`).
- Before a request is allowed, `ProfileDetails.isCompleteForInvesting` is verified (legal name, phone, country, city, ≥12-character bio, experience level).

### 4.4 Negotiation
- Negotiable listings (`OpportunityListing.isNegotiable`) accept an investor offer. `InvestmentService.createOrUpdateOfferRequest` supersedes the investor's previous pending offer instead of creating duplicates (`offerStatus = superseded`).
- `OfferService` stores per-row offer snapshots so the seeker sees the latest negotiated terms on the request list, even when reviewing many offers across the same listing.

### 4.5 Seeker accept / decline
- Pending requests appear in the seeker's request board. Accept opens `AcceptInvestmentSheet` which requires a verification message (`InvestmentService.acceptInvestmentRequest`, `InvestmentServiceError.verificationMessageTooShort` guard).
- On accept:
  - The opportunity's `amountRequested`, interest rate, and timeline are overwritten with the accepted terms (`OpportunityService.applyAcceptedInvestmentTermsToListing`) so list views reflect the agreed deal.
  - A new `InvestmentAgreementSnapshot` is materialized on the investment row with `agreementStatus = pending_signatures` and a deterministic `termsSnapshotHash` over the frozen terms.
  - A verification message is posted into the pair chat as a structured `investmentRequest` message.

### 4.6 Digital signing
- Both sides see an "Awaiting signatures" status card and a "Review & sign agreement" CTA (`InvestmentAgreementReviewView`).
- `SignaturePadView` captures a PNG signature. `InvestmentService.signAgreement` uploads it to Cloudinary, updates the participant snapshot, and detects when both signatures are present.
- When fully signed, `finalizeMOAAndLoanSchedule` runs:
  - Downloads each signature PNG, generates the MOA PDF with `MOAPDFBuilder` (titled multi-page document with parties, reference, summary, terms, schedule, commitments, signatures, hash footer).
  - Uploads the PDF to Cloudinary (`moaPdfURL`).
  - Computes and stores a SHA-256 digest of the PDF bytes (`moaContentHash`).
  - For loan deals, calls `LoanScheduleGenerator.generateSchedule(...)` and stores the installment array; sets `fundingStatus = awaiting_disbursement`.

### 4.7 Principal disbursement (loan)
- Investor flow (gated UI in `OpportunityDetailView` + `LoanInstallmentsSection`): upload proof image(s) → `attachPrincipalDisbursementProof` → mark principal sent (`markPrincipalSentByInvestor`).
- Seeker flow (`SeekerLoanPaymentConfirmBlock`): confirm receipt (`confirmPrincipalReceivedBySeeker`) or report not received with a reason (`reportPrincipalNotReceivedBySeeker`) which un-sets the sent flag and surfaces a "send again with new proof" notification on the investor side.

### 4.8 Installment repayments (loan, dual-confirmation)
- Each repayment requires both the seeker to mark sent (with proof) and the investor to mark received. The `LoanInstallment.status` machine moves `scheduled → awaiting_confirmation → confirmed_paid` (or `disputed`).
- Out-of-order payment is rejected (`InvestmentServiceError.installmentOutOfOrder`). The investor can flag a disputed installment with a reason; the seeker re-uploads proof and re-marks sent.
- The funding status auto-progresses from `disbursed` to `closed` when the final installment is confirmed (`computeFundingStatus`). An overdue grace of 7 days is built in for default detection.

### 4.9 Equity tracking
- For an equity deal, the investor sees venture updates and milestone progress; the seeker can `postEquityVentureUpdate(...)` (title, message, growth metric, stage, attachments) and `updateEquityMilestoneStatus(...)` to advance milestones.

### 4.10 Closure
- When `fundingStatus == .closed` (loan) or all milestones complete (equity), the status card flips to "Investment completed" with a full repayment history (kept readable thanks to `loanRepaymentsUnlocked` covering `.disbursed`, `.closed`, and `.defaulted`).

### 4.11 Communication everywhere
- Each opportunity detail (investor and seeker) exposes a persistent **Contact seeker / Chat with investor** action through the entire lifecycle. The `ChatService` chats are pair-based, not opportunity-based, so the same conversation continues across deals between the same two users.

---

## 5) System Architecture

### 5.1 Layered design (matches the proposal)

```
SwiftUI Views (UI/)
     │  uses @Environment(AuthService.self), @StateObject(MainTabRouter)
     ▼
Domain Models (Models/)
     │  pure Swift structs / enums; Firestore decoding kept in *+Firestore.swift
     ▼
Services (Data/Services/)
     │  business operations, Firestore writes, lifecycle transitions
     ▼
Firebase (Auth, Firestore, Storage) + Cloudinary HTTP API
```

Notable rules:

- **Models are presentation-agnostic.** `+Firestore.swift` files own all snake_case key parsing so view code never touches Firestore types.
- **Services are stateless** and constructed on demand. They are not singletons; views typically create them as `private let svc = InvestmentService()`. Where shared state is necessary (auth identity, in-flight session), `AuthService` (`@Observable`, `@MainActor`) is injected through `@Environment`.
- **Concurrency.** All I/O uses `async / await`. Long-running calls (Cloudinary uploads, Firestore reads) are wrapped in `withTimeout(seconds:)` task groups so a failing network does not freeze the UI.

### 5.2 Process diagram (signed-in shell)

```
InvesttrustApp
└── AccessibilityEnvironmentRoot   (system + in-app reduce motion, high contrast)
    └── RootView
        ├── AuthRootView           (LoginView, SignUpView)
        └── HomeView               (TabView, MainTabRouter, top notification bell)
            ├── DashboardView
            │   ├── InvestorDashboardView   (charts, hero profits, KPI tiles)
            │   └── SeekerHomeDashboardView (capital + activity)
            ├── Action tab
            │   ├── InvestorActionTabView  (Explore / My Requests / Ongoing / Completed)
            │   └── SeekerDashboardView    (listings + requests)
            ├── ChatListView → ChatRoomView
            └── SettingsView (mode switch, profile, accessibility, support)
```

### 5.3 Data flow for one lifecycle event

Example: investor signs the MOA.

1. `OpportunityDetailView` → `InvestmentAgreementReviewView` collects PNG from `SignaturePadView`.
2. `InvestmentService.signAgreement` writes the participant signature, then, if both parties have signed, calls `finalizeMOAAndLoanSchedule`.
3. `finalizeMOAAndLoanSchedule` re-downloads both signature PNGs, builds the PDF (`MOAPDFBuilder`), uploads it (`CloudinaryImageUploadClient.uploadFileData`), and writes `agreementStatus = .active`, `fundingStatus = .awaiting_disbursement`, `moaPdfURL`, `moaContentHash`, and the loan schedule (if applicable).
4. `InAppNotificationService` re-reads investments and emits "Send principal" / "Confirm receipt" notifications.
5. `LoanRepaymentCalendarSync.syncIfEligible` adds calendar entries if the user has opted in (`isCalendarSyncEnabled`).
6. `HomeWidgetSnapshotWriter` regenerates the widget payload through the App Group.

### 5.4 Cross-cutting infrastructure

- `MainTabRouter`: tab selection and deep links (chat deep link from an investment row, route enum on a notification).
- `SessionMediaCache`: clears image / video URL caches on sign-out.
- `FirestoreUserFacingMessage`: turns raw Firestore / `NSError` codes into human strings.
- `StorageFriendlyError`: makes Firebase Storage failures explain themselves.

---

## 6) Domain Model and Data Schema

### 6.1 Core entities

| Entity | File | Purpose |
|---|---|---|
| `UserProfile` | `Models/UserProfile.swift` | Account-level profile (roles, active profile, display name, avatar). |
| `ProfileDetails` | `Models/ProfileDetails.swift` | Shared credibility data (legal name, phone, country, city, bio, experience). `isCompleteForInvesting` is the gate before sending a request. |
| `OpportunityListing` | `Models/OpportunityListing.swift` | Funding listing (title, category, description, type, amount, terms, milestones, media). |
| `OpportunityTerms` | `Models/OpportunitySchema.swift` | Type-specific terms (loan: rate, timeline, frequency; equity: percentage, valuation, stage, exit). |
| `OpportunityMilestone` | `Models/OpportunitySchema.swift` | Time-stamped or days-after-acceptance milestones. |
| `InvestmentListing` | `Models/InvestmentListing.swift` | Investor request / offer + agreement + funding state + repayment / equity progress. |
| `InvestmentAgreementSnapshot` | `Models/InvestmentAgreement.swift` | Frozen terms + signer snapshots at acceptance time. |
| `LoanInstallment` | `Models/LoanModels.swift` | One row in the repayment schedule, dual-confirmation aware. |
| `RevenueSharePeriod` | `Models/RevenueShareModels.swift` | Period record with dual confirmation + proof. |
| `FirestoreInvestorOffer` | `Models/FirestoreInvestorOffer.swift` | Offer rows in `offers/` for richer seeker-facing offer cards. |
| `ChatThread`, `ChatMessage`, `OpportunityInquirySnapshot`, `InvestmentRequestSnapshot`, `InvestmentOfferSnapshot` | `Models/ChatModels.swift` | Pair-based chat and structured message kinds. |
| `InAppNotification` | `Models/InAppNotification.swift` | Action-required vs info notifications with a `route` to deep-link. |
| `HomeWidgetSnapshot`, `HomeWidgetEvent` | `WidgetShared/HomeWidgetSnapshot.swift` | Shared payload written through an App Group. |

### 6.2 Enumerations driving the lifecycle

- `InvestmentType`: `loan`, `equity` (revenue-share modeled internally but not exposed as a wizard option).
- `RepaymentFrequency`: `monthly`, `weekly`, `one_time` (single payment at maturity).
- `RiskLevel`: `low`, `medium`, `high`.
- `VerificationStatus`: `unverified`, `verified`.
- `AgreementStatus`: `none`, `pending_signatures`, `active`.
- `FundingStatus`: `none`, `awaiting_disbursement`, `disbursed`, `defaulted`, `closed`.
- `InvestmentRequestKind`: `default_request`, `offer_request`.
- `InvestmentOfferStatus`: `pending`, `accepted`, `declined`, `superseded`.
- `LoanInstallmentStatus`: `scheduled`, `awaiting_confirmation`, `confirmed_paid`, `disputed`.

### 6.3 Firestore collections

The app talks to five top-level collections (see [Appendix A](#16-appendix-a--firestore-collections)):

- `users/{uid}` — profile, roles, active profile.
- `opportunities/{oid}` — listings with `terms`, `milestones`, media URLs, ownership.
- `investments/{iid}` — requests / offers / agreements / installments / proofs.
- `offers/{oid}` — denormalized offer rows for fast seeker views (indexes in `firestore.indexes.json`).
- `chats/{chatId}` + `chats/{chatId}/messages/{messageId}` — pair-based threads.

A composite index set is committed in `firestore.indexes.json` for `offers`, `chats`, and `messages` to keep list queries within Firestore's free read tier.

---

## 7) Investment Lifecycle and State Machines

The shipping product runs three coupled state machines off the same `investments/{iid}` document. They are intentionally orthogonal so each can be queried independently.

### 7.1 Request state (`InvestmentListing.status` + helpers)

```
pending → accepted → active → completed
       ↘
        declined  /  rejected
       ↘
        withdrawn / cancelled
```

User-facing strings come from `InvestmentListing.lifecycleDisplayTitle` so labels never drift between cards.

### 7.2 Agreement state (`agreementStatus`)

```
none → pending_signatures → active
```

Driven by `acceptInvestmentRequest` (creates pending), `signAgreement` (moves to active when both participants are signed). Each signer is captured as `AgreementSignerSnapshot` with `signedAt` and `signatureURL`.

### 7.3 Funding state (loan only) (`fundingStatus`)

```
none → awaiting_disbursement → disbursed → closed
                              ↘
                               defaulted (overdue beyond grace)
```

- `awaiting_disbursement` is set when the MOA becomes active.
- `disbursed` is set when the seeker confirms receipt of the principal.
- `closed` is computed inside `computeFundingStatus` after the last installment is fully confirmed.
- `defaulted` is computed when an installment is past due beyond the 7-day grace.

`loanRepaymentsUnlocked` (`disbursed`, `closed`, `defaulted`) is what the UI uses to choose between "principal action required" and the repayment schedule view, so a completed loan keeps its history visible.

### 7.4 Guardrails

The platform encodes its business rules as enums plus throwing service errors so the UI does not need to re-validate. Highlights from `InvestmentServiceError`:

- `cannotInvestInOwnListing`, `pendingRequestExists`, `acceptanceCapacityReached`.
- `notOpportunityOwner`, `notPending` for accept / decline paths.
- `agreementNotAwaitingSignatures`, `wrongSigner`, `alreadySigned`, `emptySignature`, `missingSignatureImages`, `profileIncomplete`.
- `principalDisbursementNotReady`, `principalNotMarkedSentByInvestor`, `principalAlreadyReceivedBySeeker`, `seekerMustConfirmPaymentFirst`, `seekerPaymentProofRequired`.
- `installmentOutOfOrder`, `installmentAlreadyComplete`, `disputeReasonTooShort`.
- Edit / delete blocked while a non-declined request is alive (`OpportunityServiceError.blockedByActiveInvestmentRequests`).

---

## 8) Feature Catalogue (As Built)

### 8.1 Identity and Access
- Firebase Authentication (email + password, password reset, Google Sign-In).
- `BiometricAuthService` (LocalAuthentication) + `BiometricCredentialStore` (Keychain).
- `SessionLoadingOverlay` covers the cold-start race so the tab bar never flashes before the user doc is ready.

### 8.2 Role-Based Product Navigation
- `MainTabRouter` (4 tabs: Dashboard, Action, Chat, Settings).
- Active-profile switcher in `SettingsContentView`.
- Theme accent changes globally (`AuthService.accentColor`).
- Notification bell injected via `safeAreaInset(edge: .top)` so it is reachable from any tab.

### 8.3 Product and Opportunity Management
- 6-step `CreateOpportunityWizardView` with type-specific term steps for loan / equity.
- `EditOpportunityView` with the same validation pipeline.
- Negotiation toggle (`isNegotiable`) enabled only for single-investor listings.
- Multi-image carousel (`AutoPagingImageCarousel`) and optional pitch video (Cloudinary streaming HTTPS).

### 8.4 Opportunity Discovery
- `InvestorMarketView` and `MarketBrowseView` with search, filters by `InvestmentType` / `RiskLevel` / verification, and sort by newest / amount.
- `OpportunityCard` renders the listing tile; the detail view auto-overlays accepted economics for partial-fill rounds via `OpportunityListing.overlayingAcceptedIfPresent`.

### 8.5 Investment Management and History
- Investor: `OpportunityDetailView` (status card per state), `InvestProposalSheet` (default + offer modes), `MyRequests`, `InvestorOngoingDealsView`, `InvestorCompletedDealsView`.
- Seeker: request board, `AcceptInvestmentSheet` (verification message required), `SeekerOpportunityDetailView`, `SeekerLoanPaymentConfirmBlock`.
- Agreement: `InvestmentAgreementReviewView` + `SignaturePadView` + `MOAPDFKitViewer` (PDFKit-backed reader).
- Payment proofs: `DocumentCameraView` (VisionKit-based scanner) and one-tap photo picker (PhotosUI).

### 8.6 Collaboration and Communication
- Pair-based chats (`ChatService.canonicalChatId`) so the same thread is reused across opportunities.
- Structured message kinds for inquiry, request, and offer.
- Deep linking: tapping a chat card in the notification feed deep-links into the right thread via `tabRouter.pendingChatDeepLink`.

### 8.7 Settings and Account
- `SettingsContentView` and `SettingsPreferencesViews`: theme (system / light / dark), language (system + supported locales), accessibility (haptics, reduce motion in app, high contrast), profile edit, support, sign out.
- `SettingsSupportViews`: about, privacy, contact.

### 8.8 Local Notifications and Engagement
- `InAppNotificationService` derives a live action list from Firestore data (signature required, principal next steps, installment confirmation, equity updates due, calendar consent reminder).
- Top-right bell badge counts `actionRequired` items.
- Each notification carries a `route` enum so taps land on the correct tab and segment.

---

## 9) Advanced iOS Capabilities

### 9.1 EventKit — calendar-linked commitments (`LoanRepaymentCalendarSync`)
- Loan installment events: one all-day event per unpaid installment with an alarm one day before. Title encodes the amount and opportunity (`"Investtrust — Pay LKR 12,500 · Cafe expansion"`); notes carry instalment number and balance.
- Milestone events: all-day events anchored to acceptance date + `dueDaysAfterAcceptance`.
- Consent is **opt-in**: a SwiftUI alert ("Sync due dates to Calendar?") in `HomeView` and `OpportunityDetailView`. We do **not** call `ensureCalendarAccess()` before `isCalendarSyncEnabled` is set, so the system permission sheet never races the in-app alert. The Info.plist supplies `NSCalendarsWriteOnlyAccessUsageDescription`.

### 9.2 WidgetKit — Home Screen widget (`InvesttrustWidget`)
- Small and medium sizes.
- Reads `HomeWidgetSnapshot` from the App Group (`group.investtrust.shared`); the app rewrites the snapshot on each lifecycle event through `HomeWidgetSnapshotWriter`.
- Shows the next loan payment (or seeker payment due), amount in LKR, days remaining, and an urgency colour (red overdue, orange ≤1 day, pink ≤7 days, blue otherwise).

### 9.3 Charts framework
- `InvestorDashboardView` uses SwiftUI Charts for the hero profits chart and the KPI tiles (total invested, total liability in red, projected returns, active deals).
- Period-scoped numbers come from `InvestorPortfolioMetrics`.

### 9.4 PDFKit + Core Graphics — MOA generation (`MOAPDFBuilder`)
- Custom multi-page renderer (US Letter, 612 × 792 pt) with a defined palette and typographic hierarchy.
- Sections: parties → reference → investment summary → loan or equity terms → schedule or venture profile → commitments → signatures → footer (SHA-256 of bytes).
- `signaturesBySignerId: [String: UIImage]` is consumed in-render so the same PDF instance contains both signatures.

### 9.5 LocalAuthentication — biometric unlock
- Returning users can sign in with Face ID / Touch ID without re-entering email or password; an authenticated `LAContext` unlocks the Keychain entry stored at sign-up.

### 9.6 VisionKit / Photos
- `DocumentCameraView` (`VNDocumentCameraViewController`) lets the seeker scan receipts directly into a payment proof.
- One-tap photo picker (PhotosUI `PhotosPicker`) replaces older multi-step menus across the loan + seeker flows.

### 9.7 UserNotifications and in-app feed
- `InAppNotificationService` builds the in-app feed live (Firestore-derived, no push).
- Push notifications are out of scope for this build; the proposal flagged it as a Tier A roadmap item.

---

## 10) Backend, Storage and Security

### 10.1 Firebase project layout
- **Cloud Firestore** — primary database, five collections (see Appendix A). Composite indexes in `firestore.indexes.json` cover offers and chat queries.
- **Firebase Authentication** — email / password and Google providers; password reset wired to `AuthService.sendPasswordReset`.
- **Cloud Storage** — used for MOA artefacts and loan / principal proof images. Storage rules limit `opportunities/{userId}/...` writes to the owner and require auth for `investments/{investmentId}/...`.
- **Cloudinary** — primary media path for opportunity images and pitch video (`CloudinaryImageUploadClient`, `CloudinaryVideoUploadClient`). Unsigned uploads through an upload preset (`Investtrust`), with `public_id` retained so `CloudinaryDestroyClient` can delete assets on listing delete.

### 10.2 Configuration files
| File | Purpose |
|---|---|
| `Investtrust-Info.plist` | Cloudinary cloud + preset, Google Sign-In client URL scheme, EventKit / Photos / Camera / Face ID privacy strings. |
| `Investtrust/GoogleService-Info.plist` | Firebase iOS config. |
| `firebase.json` | Wires `firestore.rules`, `firestore.indexes.json`, `storage.rules`. |
| `firestore.indexes.json` | Composite indexes for offers + chats + messages. |
| `firestore.rules` | **Currently open access** for the demo; see Section 14 (Tier A roadmap). |
| `storage.rules` | Owner-scoped writes for opportunity media, authenticated writes for investment-scoped artefacts. |
| `Investtrust.entitlements` | App Group (`group.investtrust.shared`) for the widget. |
| `InvesttrustWidgetExtension-Info.plist` + `InvesttrustWidget.entitlements` | Widget target metadata. |

### 10.3 Document integrity
- The final MOA PDF is hashed with `CryptoKit.SHA256` and the hex digest is stored on the investment row (`moaContentHash`). Any later re-render that does not match this digest is treated as tampered.
- Signatures are stored as Cloudinary-hosted PNGs referenced from the snapshot; the PDF re-downloads them so a snapshot-only check is sufficient.

### 10.4 Permissions and rules
- **iOS privacy strings** in `Investtrust-Info.plist` cover the photo library, camera, Face ID, and write-only calendar access.
- **Firestore rules** (`firestore.rules`) and **Storage rules** (`storage.rules`) are committed and deployable via `npm run firebase:deploy:firestore` / `firebase:deploy:storage`.
- Owner enforcement also lives on the client (`OpportunityServiceError.notOwner`) so the app shows the right error even before a rule denial.

---

## 11) UI / UX and Accessibility

### 11.1 Design system (`AppTheme`, `ProfileTheme`)
- Centralized tokens: card corner radius 20, control radius 12, screen padding 20, card padding 16, minimum tap target 44 pt.
- `Color` usage is system-aware: `systemBackground`, `systemGroupedBackground`, `secondarySystemFill` so dark mode is automatic.
- Each role has its own accent (`ProfileTheme.investorBlue`, `ProfileTheme.seekerPink`); the tab bar tint, primary buttons, and Charts series all read from `auth.accentColor`.

### 11.2 Reusable components
- `OpportunityCard`, `InvestmentCard` — the two primary list tiles.
- `LoanRepaymentScheduleView`, `LoanInstallmentsSection` — repayment UI with overlay progress when an upload is in-flight (`imageUploadProgressOverlay`).
- `SeekerLoanPaymentConfirmBlock` — seeker proof + mark-sent block.
- `SignaturePadView` — PencilKit-style trace with redraw / clear.
- `StatusBlock` — empty / error states.
- `MOAPDFKitViewer`, `FullscreenVideoPlayer`, `AutoPagingImageCarousel`, `StorageBackedAsyncImage` / `StorageBackedVideoPlayer`, `CachedImageLoader`.

### 11.3 Accessibility
- System integration: dynamic type, system bold text, system high contrast, system Reduce Motion (`@Environment(\.accessibilityReduceMotion)`).
- In-app overrides (independent of system Settings) live in `AppAccessibilityPreferences`: haptics, reduce motion in app, high contrast.
- `AccessibilityEnvironmentRoot` injects the merged environment value (`effectiveReduceMotion`, `appHighContrastEnabled`) used by all animations.
- VoiceOver labels and hints are set explicitly on the loading overlay, the notification bell, status cards, and the agreement review screen.
- Haptics fan out through `AppHaptics.selection / lightImpact / success / warning`, all of which respect the in-app haptics toggle.

### 11.4 Localization
- Supported locales (`AppLanguageOption`) are persisted as a per-user preference; the `.environment(\.locale, ...)` is applied at scene root.

---

## 12) Quality, Testing and Build Tooling

### 12.1 Unit tests (`InvesttrustTests/`)
- `InvestmentAgreementFlowTests.swift` — verifies the accept → sign → activate transitions.
- `InvestmentOfferFlowTests.swift` — covers the negotiation path including supersede behaviour.
- `LoanScheduleGeneratorTests.swift` — exercises monthly / weekly / one-time schedule generation and rounding.

### 12.2 Build and deploy
- `Investtrust.xcodeproj` builds two targets (app + widget) with `GENERATE_INFOPLIST_FILE` on for the app and an explicit Info.plist for the widget.
- Last verified build (during this report): `xcodebuild -scheme Investtrust -destination 'platform=iOS Simulator,name=iPhone 17' build` → **BUILD SUCCEEDED**.
- Firebase: `npm install` then `npm run firebase:deploy:firestore` / `firebase:deploy:storage` (see `package.json` scripts).
- Cloudinary: cloud + preset embedded in `Investtrust-Info.plist`. Uploads are unsigned (no API secret in the binary).
- A helper bootstrap script (`scripts/provision-default-storage-bucket.sh`) provisions the default Storage bucket through gcloud.

### 12.3 Build configuration highlights
- iOS 17 minimum (`@Observable`, `@MainActor`, `safeAreaInset`).
- Portrait + landscape on iPhone; portrait on iPad through `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`.
- App Group entitlement (`group.investtrust.shared`) shared between the app and widget.

---

## 13) Project Structure

```
Investtrust/
├── App/
│   ├── InvesttrustApp.swift      // @main, Firebase configure, environment
│   ├── AppDelegate.swift         // adaptor for Firebase / Google ordering
│   └── RootView.swift            // auth gating + session overlay
├── Data/
│   ├── BiometricCredentialStore.swift  // Keychain wrapper
│   └── Services/
│       ├── AuthService.swift
│       ├── BiometricAuthService.swift
│       ├── ChatService.swift
│       ├── Cloudinary/ ...
│       ├── FirebaseStorageAsync.swift
│       ├── FirestoreUserFacingMessage.swift
│       ├── HomeWidgetSnapshotWriter.swift
│       ├── ImageJPEGUploadPayload.swift
│       ├── InAppNotificationService.swift
│       ├── InappropriateImageGate.swift
│       ├── InvestmentService.swift  // 1.9k LoC — lifecycle, signing, repayments
│       ├── LoanRepaymentCalendarSync.swift
│       ├── MOAPDFBuilder.swift
│       ├── OfferService.swift
│       ├── OpportunityService.swift
│       ├── SessionMediaCache.swift
│       ├── StorageFriendlyError.swift
│       └── UserService.swift
├── Models/   // Pure Swift + +Firestore decoding extensions
├── UI/
│   ├── Accessibility/
│   ├── AppShell/                 // HomeView, MainTabRouter
│   ├── Auth/                     // LoginView, SignUpView, AuthTheme
│   ├── Chat/                     // ChatListView, ChatRoomView, ChatThreadRowView
│   ├── Components/               // 16 reusable components
│   ├── Dashboard/                // Investor / Seeker / Market dashboards
│   ├── Investor/                 // Detail, Proposal sheet, MyRequests, Ongoing, Completed
│   ├── Notifications/            // InAppNotificationsView
│   ├── Profile/                  // ProfileEditView, PublicProfileView
│   ├── Seeker/                   // Wizard, Edit, Detail, accept sheet, payment confirm
│   ├── Settings/                 // Settings shell + preferences + support
│   └── Theme/                    // AppTheme, ProfileTheme
├── Assets.xcassets
├── GoogleService-Info.plist
└── Investtrust.entitlements

InvesttrustWidget/                // Widget target
├── InvesttrustHomeWidget.swift
├── InvesttrustWidgetBundle.swift
└── InvesttrustWidget.entitlements

WidgetShared/
└── HomeWidgetSnapshot.swift      // App Group payload (shared)

InvesttrustTests/                 // XCTest unit tests

firebase.json                     // wires rules + indexes
firestore.rules                   // (open in demo build)
firestore.indexes.json
storage.rules
Investtrust-Info.plist
package.json                      // firebase CLI helpers
scripts/provision-default-storage-bucket.sh
proposal.md                       // original proposal
BUSINESS_USECASES.md              // business flow reference
REPORT.md                         // this document
```

Module sizes for reference (`wc -l` on services + models): **~8.3k LoC** in shared service / model code alone, of which `InvestmentService.swift` (~1.9k) is the lifecycle engine and `MOAPDFBuilder.swift` (~890) is the PDF renderer.

---

## 14) Known Limitations and Roadmap

### 14.1 Carried over directly from the proposal (Tier A)
1. **Real payment rails.** Investtrust models principal and installments with **dual confirmation + proof of payment**, but does not move money. The next step is a payments integration (LankaQR, card, or bank rail) replacing the "mark sent" + "confirm received" gates.
2. **Push notifications.** The in-app feed is complete; APNs + Cloud Functions for cross-device push is still future work.
3. **Server-hardened signing and media delete.** Today the client renders the PDF, computes the hash, and calls Cloudinary's destroy endpoint directly. Tier A moves this to Firebase Cloud Functions so secrets never leave the server.
4. **Tighten Firestore rules.** `firestore.rules` is intentionally permissive (`allow read, write: if true;`) for the demo. Production rules need owner / participant assertions matching the queries the app makes.

### 14.2 Tier B and C
- Analytics and telemetry dashboards (proposal Tier B).
- Moderation, dispute workflows, automated reminder escalations.
- Smart matching, KYC / document vault, offline resilience.

### 14.3 Smaller follow-ups noticed during the build
- Revenue-share has full model + service support but no end-user listing-creation path in the wizard.
- The current Firestore demo rules also mean unauthenticated clients with the project's public web config could read or write data — flagged with an inline comment in `firestore.rules`.
- Widget timeline currently refreshes hourly when there are no upcoming events; with push or BackgroundTasks we could move that closer to real time.

---

## 15) Conclusion

Investtrust ships against the proposal as a coherent, **lifecycle-complete** investment app rather than a static marketplace. The shipped feature set covers identity, role-aware navigation, opportunity publishing and discovery, negotiation, digital MOA signing, principal disbursement with proof, repayment tracking with dual confirmation, equity progress updates, in-app notifications, calendar sync, a Home Screen widget, charts-driven dashboards, and accessibility-aware design.

The remaining work is explicitly the production-hardening path called out in the proposal: real payment rails, push notifications, server-side rule and signing hardening, and the analytics / compliance layer. Everything else — the lifecycle, the agreement engine, the iOS integrations, the role-flexible product model — is built and verified by the included unit tests and a green `xcodebuild` against the current scheme.

---

## 16) Appendix A — Firestore Collections

```
users/{uid}
  createdAt: Timestamp
  updatedAt: Timestamp
  activeProfile: "investor" | "seeker"
  roles: { investor: Bool, seeker: Bool }
  displayName: String?
  avatarURL: String?
  profile: {
    legalFullName, phoneNumber, country, city, shortBio,
    experienceLevel, pastWorkProjects, verificationStatus
  }

opportunities/{oid}
  ownerId: String
  title, category, description, location: String
  investmentType: "loan" | "equity"
  amountRequested, minimumInvestment: Double
  maximumInvestors: Int?
  terms: { interestRate, repaymentTimelineMonths, repaymentFrequency,
           equityPercentage, businessValuation, equityTimelineMonths,
           ventureName, ventureStage, futureGoals, revenueModel,
           targetAudience, demoLinks, equityRoiTimeline, exitPlan, ... }
  milestones: [{ title, description, daysAfterAcceptance | expectedDate }]
  riskLevel, verificationStatus, status: String
  isNegotiable: Bool
  imageURLs, imagePublicIds: [String]
  videoURL, videoStoragePath, videoPublicId: String?
  mediaWarnings: [String]
  viewCount: Int?
  createdAt, updatedAt: Timestamp

investments/{iid}
  opportunityId, investorId, seekerId: String?
  opportunityTitle: String
  imageURLs: [String]
  investmentType: "loan" | "equity"
  status: String   // pending / accepted / active / completed / declined / withdrawn / cancelled
  investmentAmount, receivedAmount: Double
  finalInterestRate, finalTimelineMonths
  requestKind: "default_request" | "offer_request"
  offerStatus: "pending" | "accepted" | "declined" | "superseded"
  offerSource, offeredAmount, offeredInterestRate, offeredTimelineMonths,
  offerDescription, offerChatId, offerChatMessageId
  agreementStatus: "none" | "pending_signatures" | "active"
  fundingStatus: "none" | "awaiting_disbursement" | "disbursed" | "defaulted" | "closed"
  acceptedAt, signedByInvestorAt, signedBySeekerAt, agreementGeneratedAt
  agreement: InvestmentAgreementSnapshot   // frozen at acceptance
  moaPdfURL, moaContentHash
  investorSignatureImageURL, seekerSignatureImageURL
  principalSentByInvestorAt, principalReceivedBySeekerAt
  principalInvestorProofImageURLs, principalSeekerProofImageURLs: [String]
  principalSeekerNotReceivedAt, principalSeekerNotReceivedReason
  loanInstallments: [LoanInstallment]
  revenueSharePeriods: [RevenueSharePeriod]
  equityMilestones: [EquityMilestoneProgress]
  equityUpdates: [EquityVentureUpdate]
  createdAt, updatedAt: Timestamp

offers/{oid}
  opportunityId, seekerId, investmentId, investorId: String
  amount, interestRate: Double
  timelineMonths: Int
  description: String
  createdAt, updatedAt: Timestamp

chats/{chatId}                   // chatId is canonical pair-based
  opportunityId, seekerId, investorId: String
  participantIds: [String]
  title, lastMessagePreview: String
  createdAt, lastMessageAt, updatedAt: Timestamp

chats/{chatId}/messages/{messageId}
  senderId: String
  text: String
  participantIds: [String]
  kind: "text" | "opportunityInquiry" | "investmentRequest" | "investmentOffer"
  snapshot: { ... }              // structured payload per kind
  createdAt: Timestamp
```

## 17) Appendix B — Key Files Map

| Capability | File |
|---|---|
| App entry, Firebase config | `Investtrust/App/InvesttrustApp.swift`, `Investtrust/App/AppDelegate.swift` |
| Auth gate, session overlay | `Investtrust/App/RootView.swift`, `Investtrust/UI/Auth/AuthRootView.swift`, `Investtrust/UI/Auth/LoginView.swift`, `Investtrust/UI/Auth/SignUpView.swift` |
| Identity service, biometric | `Investtrust/Data/Services/AuthService.swift`, `Investtrust/Data/Services/BiometricAuthService.swift`, `Investtrust/Data/BiometricCredentialStore.swift` |
| Tab shell, deep links | `Investtrust/UI/AppShell/HomeView.swift`, `Investtrust/UI/AppShell/MainTabRouter.swift` |
| Investor dashboard, charts | `Investtrust/UI/Dashboard/InvestorDashboardView.swift`, `Investtrust/UI/Dashboard/InvestorPortfolioMetrics.swift` |
| Seeker dashboards | `Investtrust/UI/Dashboard/DashboardView.swift`, `Investtrust/UI/Seeker/SeekerHomeDashboardView.swift`, `Investtrust/UI/Seeker/SeekerDashboardView.swift` |
| Opportunity create / edit | `Investtrust/UI/Seeker/CreateOpportunityWizardView.swift`, `Investtrust/UI/Seeker/EditOpportunityView.swift`, `Investtrust/Data/Services/OpportunityService.swift` |
| Market browse + filters | `Investtrust/UI/Dashboard/MarketBrowseView.swift`, `Investtrust/UI/Investor/InvestorMarketView.swift`, `Investtrust/UI/Components/OpportunityCard.swift` |
| Opportunity detail (investor) | `Investtrust/UI/Investor/OpportunityDetailView.swift` |
| Opportunity detail (seeker) | `Investtrust/UI/Seeker/SeekerOpportunityDetailView.swift` |
| Request / offer composer | `Investtrust/UI/Investor/InvestProposalSheet.swift`, `Investtrust/UI/Components/InvestmentOfferComposerForm.swift`, `Investtrust/Data/Services/OfferService.swift` |
| Investment lifecycle engine | `Investtrust/Data/Services/InvestmentService.swift` |
| MOA review + signing | `Investtrust/UI/Investor/InvestmentAgreementReviewView.swift`, `Investtrust/UI/Components/SignaturePadView.swift`, `Investtrust/UI/Components/MOAPDFKitViewer.swift` |
| MOA PDF rendering + hashing | `Investtrust/Data/Services/MOAPDFBuilder.swift` |
| Loan repayments | `Investtrust/Models/LoanModels.swift`, `Investtrust/UI/Components/LoanInstallmentsSection.swift`, `Investtrust/UI/Components/LoanRepaymentScheduleView.swift`, `Investtrust/UI/Seeker/SeekerLoanPaymentConfirmBlock.swift` |
| Equity tracking | `Investtrust/Models/InvestmentListing.swift` (`EquityVentureUpdate`, `EquityMilestoneProgress`) plus service methods `postEquityVentureUpdate`, `updateEquityMilestoneStatus` |
| Chat | `Investtrust/Data/Services/ChatService.swift`, `Investtrust/UI/Chat/ChatListView.swift`, `Investtrust/UI/Chat/ChatRoomView.swift`, `Investtrust/UI/Chat/ChatThreadRowView.swift`, `Investtrust/Models/ChatModels.swift` |
| Notifications | `Investtrust/Data/Services/InAppNotificationService.swift`, `Investtrust/UI/Notifications/InAppNotificationsView.swift`, `Investtrust/Models/InAppNotification.swift` |
| Calendar sync | `Investtrust/Data/Services/LoanRepaymentCalendarSync.swift` |
| Home widget | `InvesttrustWidget/InvesttrustHomeWidget.swift`, `InvesttrustWidget/InvesttrustWidgetBundle.swift`, `WidgetShared/HomeWidgetSnapshot.swift`, `Investtrust/Data/Services/HomeWidgetSnapshotWriter.swift` |
| Media handling | `Investtrust/Data/Services/Cloudinary/CloudinaryImageUploadClient.swift`, `CloudinaryVideoUploadClient.swift`, `CloudinaryDestroyClient.swift`, `CloudinarySignature.swift`, `CloudinaryPublicIdExtractor.swift`, `Investtrust/Data/Services/InappropriateImageGate.swift`, `Investtrust/Data/Services/FirebaseStorageAsync.swift`, `Investtrust/UI/Components/AutoPagingImageCarousel.swift`, `StorageBackedAsyncImage.swift`, `StorageBackedVideoPlayer.swift`, `CachedImageLoader.swift` |
| Theme & components | `Investtrust/UI/Theme/AppTheme.swift`, `Investtrust/UI/Theme/ProfileTheme.swift`, `Investtrust/UI/Components/*.swift` |
| Accessibility | `Investtrust/UI/Accessibility/AppAccessibility.swift`, `AppAccessibilityPreferences.swift`, `AccessibilityEnvironmentRoot.swift` |
| Settings | `Investtrust/UI/Settings/SettingsView.swift`, `SettingsContentView.swift`, `SettingsPreferencesViews.swift`, `SettingsSupportViews.swift` |
| Tests | `InvesttrustTests/InvestmentAgreementFlowTests.swift`, `InvestmentOfferFlowTests.swift`, `LoanScheduleGeneratorTests.swift` |
| Backend config | `firebase.json`, `firestore.rules`, `firestore.indexes.json`, `storage.rules`, `package.json`, `scripts/provision-default-storage-bucket.sh` |

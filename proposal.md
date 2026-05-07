# Investtrust - Proposed Product Report

## Table of Sections
1. Executive Introduction  
2. Concept and Business Rationale  
3. Intended User Segments  
4. Problem Definition  
5. Baseline Feature Set (Core Scope)  
6. Advanced Capability Set  
7. System and Data Architecture  
8. Tools, Services, and Technical Justification  
9. Differentiators and Value Proposition  
10. Delivery Roadmap and Recommendations  
11. Conclusion

## 1) Executive Introduction

**Application Name:** Investtrust  
**Domain:** FinTech / Investment Marketplace / Agreement and Repayment Workflow  
**Platform:** Native iOS

Investtrust is proposed as a two-sided digital investment environment where seekers will publish capital opportunities and investors will review, negotiate, and fund those opportunities through structured workflows. The application will not be limited to listing and matching; it will also include agreement execution and post-deal tracking, making it suitable for realistic multi-stage investment operations.

## 2) Concept and Business Rationale

Many small and medium capital opportunities struggle with trust, process clarity, and execution visibility after initial investor interest. Traditional informal channels usually fail in three places: term negotiation, legal agreement finalization, and post-funding accountability.

Investtrust will address this by combining:
- marketplace discovery and filtering
- transparent request and offer flow
- digital agreement lifecycle
- repayment/progress monitoring tied to investment type

This will create a controlled process from first contact to operational completion.

## 3) Intended User Segments

The platform will primarily serve:
- **Opportunity Seekers** (builders/founders requiring capital)
- **Investors** (individual or group participants evaluating opportunities)
- **Hybrid Users** who may alternate roles based on context

The role-switching model will allow one account to operate in different business contexts without creating separate identities.

## 4) Problem Definition

Current investment coordination in early-stage ecosystems often has:
- fragmented communication channels
- unstructured offer handling
- manual agreement follow-up
- weak repayment/performance traceability

Investtrust will solve these gaps by establishing a digital lifecycle that captures request state, agreement state, and execution state in one connected system.

## 5) Baseline Feature Set (Core Scope)

### Feature Group 1 - Identity and Access
- Email/password registration and login
- Google sign-in integration
- Password reset support
- Face ID / biometric quick unlock using LocalAuthentication
- Role-aware session handling

### Feature Group 2 - Role-Based Product Navigation
- Investor and Seeker mode switching
- Context-aware tabs and dashboards
- Action screens based on active role
- Landing page flow for authenticated users
- User onboarding path for first-time experience guidance
- Dedicated dashboard views for both Investor and Seeker users

### Feature Group 3 - Product and Opportunity Management
- Opportunity publishing workflow
- Editing and updating listed opportunities
- Listing visibility and maintenance controls
- Product/opportunity detail management with lifecycle-aware status handling

### Feature Group 4 - Opportunity Discovery
- Search and filter for market exploration
- Risk and type-based selection
- Sorting support for decision efficiency

### Feature Group 5 - Investment Management and History
- Investor request submission
- Seeker accept/decline actions
- Investor withdrawal before confirmation
- Negotiation and offer updates before final confirmation
- Lifecycle status visibility across request, agreement, and active phases
- Investment history views for tracking past and ongoing activity
- Agreement-linked history context for better investment traceability
- Digital agreement flow with signing and document tracking
- Post-agreement execution tracking (loan/revenue/equity progress)

### Feature Group 6 - Collaboration and Communication
- User-to-user chat threads
- Opportunity/investment context in chat
- Message continuity across lifecycle stages

### Feature Group 7 - Settings and Account Management
- Profile details updates
- Theme/language style preferences
- Accessibility settings support (readability and usability preferences)
- Session and account controls

### Feature Group 8 - Local Notifications and Engagement
- Local notifications for reminders and lifecycle follow-ups
- In-app notification center for key investment and agreement events

## 6) Advanced Capability Set

### Advanced Capability 1 - Calendar-Linked Commitment Tracking (EventKit)
- Repayment/milestone events synced to iOS Calendar
- Permission-driven EventKit integration

### Advanced Capability 2 - Widget Extension for At-a-Glance Status (WidgetKit)
- Home screen widget with next relevant commitment
- Shared app-group snapshot flow for lightweight updates
- WidgetKit-based quick visibility for role-specific upcoming actions

## 7) System and Data Architecture

Investtrust will follow a layered architecture:
- **UI Layer:** SwiftUI screens by role and workflow
- **Domain Model Layer:** opportunity, investment, agreement, and user entities
- **Service Layer:** business operations, firestore writes, lifecycle transitions

Data flow will follow state-driven transitions where each operation updates status fields (request/agreement/funding/payment), enabling traceable lifecycle movement rather than ad-hoc state changes.

## 8) Tools, Services, and Technical Justification

### Swift + SwiftUI
Used for native iOS experience, rapid UI iteration, and strong integration with Apple ecosystem features.

### Firebase Authentication
Used for secure identity management, session support, and account-level access control.

### Cloud Firestore
Primary database for opportunities, investments, agreements, user profiles, and chat-linked operational data.

### Firebase Storage and Cloudinary
Used for media and document handling. Cloudinary is leveraged for primary media workflows.

### Apple Framework Integrations
- **EventKit:** repayment/milestone calendar syncing
- **WidgetKit:** home widget summary support
- **Charts:** investor dashboard visual insights
- **LocalAuthentication:** biometric convenience and security
- **UserNotifications (Local Notifications):** on-device reminders and lifecycle nudges
- **Vision/Photos-related tooling:** document and image handling paths

### Security and Governance
- Firestore and Storage rules for access control
- role and lifecycle-aware data ownership
- document integrity support through hashing

## 9) Differentiators and Value Proposition

Proposed strengths that will distinguish Investtrust:
- Full lifecycle coverage from listing to post-funding execution
- Negotiation-ready investment workflow instead of static interest forms
- Multi-stage agreement management with digital signing
- Execution discipline through proof and confirmation flows
- Role-flexible product model for real user behavior
- Advanced iOS integrations through EventKit and WidgetKit

## 10) Delivery Roadmap and Recommendations

### Priority Tier A (Immediate)
1. Add payment rail integrations for direct settlement support
2. Add push notifications for time-sensitive lifecycle transitions
3. Move sensitive media-signing/deletion operations to secured backend functions

### Priority Tier B (Next)
1. Introduce analytics and product telemetry dashboards
2. Add moderation/risk workflows for dispute-intensive cases
3. Build automated reminder and escalation schedules

### Priority Tier C (Growth)
1. Intelligent investor-opportunity matching suggestions
2. Extended compliance flows (KYC/document vault)
3. Offline resilience and performance optimization passes

## 11) Conclusion

Investtrust is proposed with a strong functional base that combines practical core features and meaningful advanced workflows. With payment integration, notification infrastructure, and hardened server-side security operations, the platform is expected to evolve from a robust coordination tool into a transaction-complete investment ecosystem suitable for broader production adoption.

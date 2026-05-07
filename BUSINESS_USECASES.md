# Investtrust Business Use Cases and Process Guide

## Purpose of the Platform
Investtrust connects two types of users:
- **Opportunity Builders (Seekers):** people or businesses raising funds for a specific opportunity.
- **Investors:** people looking to discover opportunities and place investment requests.

The app supports the full journey from opportunity creation, to investor request handling, to agreement signing, and ongoing relationship management through chat.

---

## Core Business Objects

### 1) Opportunity
An opportunity is a funding listing created by a seeker. It includes:
- Business context (title, category, description, location)
- Funding ask (amount needed, minimum investment, optional investor cap)
- Risk level
- Use of funds and milestones
- Supporting media (images/video) and optional documents
- A deal structure (loan, equity, revenue share, project, or custom)

### 2) Investment Request
An investment request is submitted by an investor against an opportunity. It includes:
- Proposed amount
- Snapshot context of the deal at the time of request
- Lifecycle status (pending, accepted, declined, etc.)
- Agreement status (none, awaiting signatures, active)

### 3) Agreement (MOA)
When a seeker accepts a request, an agreement snapshot is generated from the accepted terms. Both sides can review and sign. Once signed by both, it becomes active.

### 4) Conversation (Chat)
A dedicated chat thread supports negotiation and coordination between seeker and investor.

---

## User Modes and Business Intent

The same account can operate in two modes:
- **Investor mode:** discover opportunities, submit requests, track deals.
- **Opportunity Builder mode:** publish and manage opportunities, process incoming requests.

Users can switch active mode in settings depending on what they need to do.

---

## End-to-End Business Flow

## A. Opportunity Builder (Seeker) Journey

### Step A1: Create an Opportunity
The seeker creates a listing using a guided multi-step flow:
1. Choose investment type:
   - Loan
   - Equity
   - Revenue share
   - Project-based return
   - Custom terms
2. Enter overview details (title, category, story)
3. Define funding and risk (amount, minimum ticket, optional max investors)
4. Add type-specific terms
5. Add execution plan (use of funds + milestones)
6. Review and submit

**Business result:** listing becomes available for discovery in the market.

### Step A2: Manage Own Listings
In the Create area, seekers can:
- View all their listings
- Open listing details
- Edit listing content (when allowed)
- Delete listing (when allowed)

### Step A3: Receive Investor Requests
For each listing, seekers can see incoming requests and their state.

For a **pending** request, seeker can:
- View investor profile
- Accept
- Decline

### Step A4: Accept Request with Verification Message
On acceptance, seeker sends a verification/confirmation message to investor chat and finalizes acceptance.

**Business result:**
- Request status moves from pending to accepted phase
- Agreement snapshot becomes available for signature workflow
- Both parties have clear communication context

### Step A5: Sign Agreement
If agreement is awaiting signatures, seeker reviews and signs.

**Business result:** after both sides sign, agreement status becomes active.

---

## B. Investor Journey

### Step B1: Explore the Market
Investors browse open listings in Explore. They can:
- Search listings
- Filter by sensible business criteria (type, risk, verification, etc.)
- Sort by relevance criteria (newest/amount)

### Step B2: Evaluate an Opportunity
Inside opportunity detail, investor reviews:
- Story and context
- Funding goal and minimum ticket
- Key terms and timeline
- Milestones and use of funds
- Media and supporting documents
- Seeker verification signal

### Step B3: Submit Investment Request
Investor submits a request by:
- Entering amount (must satisfy listing minimum)
- Confirming key acknowledgements

**Business result:** request enters pending state for seeker decision.

### Step B4: Track Request Lifecycle
In **My Requests**, investor tracks all requests:
- Waiting for seeker
- Accepted
- Awaiting signatures
- Agreement active
- Declined/rejected/completed where applicable

### Step B5: Review & Sign Agreement
Investor opens agreement snapshot and signs when required.

**Business result:** once both signatures exist, the agreement becomes active.

### Step B6: Monitor Portfolio
Investor Home provides business-level visibility:
- Total invested (booked in accepted/active deals)
- Expected projected returns
- Amount received so far
- Count of active deals
- Pending approval amounts
- Alerts and timeline-oriented views

---

## Request and Agreement Lifecycle (Business States)

## Request States (human meaning)
- **Pending / Waiting for seeker:** investor has submitted; seeker must decide.
- **Accepted:** seeker approved request.
- **Declined / Rejected:** seeker did not approve.
- **Active:** request is part of an active agreement.
- **Completed:** deal has finished.

## Agreement States
- **None:** no agreement yet.
- **Pending signatures (Awaiting signatures):** agreement prepared; one or both parties still need to sign.
- **Active (Agreement active):** both signatures complete; agreement is in effect.

---

## Business Rules and Guardrails

## Opportunity Submission Guardrails
- Required core fields must be completed (title/category/description/location/use of funds, valid amount, and terms).
- Minimum investment logic ensures realistic ticket sizing.
- Type-specific term rules enforce clear offer structure.

## Investment Request Guardrails
- Request amount must be valid and above listing minimum.
- Investor must explicitly acknowledge key conditions before sending.

## Seeker Management Guardrails
- A listing with active/blocking request states cannot be freely edited/deleted until those blocking states are resolved.
- Non-blocking states (like declined/withdrawn/cancelled) do not prevent listing management.

## Signature Guardrails
- Only the correct party can sign their side.
- Signing is only available while agreement is pending signatures.

---

## Communication Process

Chat is the operational layer for:
- Negotiation
- Clarifications
- Acceptance follow-up messages
- Ongoing coordination after agreement

This reduces friction between decision points and keeps counterparties aligned.

---

## Role-Based Functional Summary

## Opportunity Builder (Seeker)
- Create funding opportunities with structured terms
- Publish and manage listings
- Review investor requests
- Accept/decline requests
- Send verification message at acceptance
- Review and sign agreements
- Coordinate via chat

## Investor
- Browse and filter opportunities
- Inspect opportunity details and terms
- Submit investment requests
- Track request/agreement lifecycle
- Review and sign agreements
- Monitor portfolio-level outcomes
- Coordinate via chat

---

## Typical Real-World Scenario
1. Seeker publishes a loan-based listing for inventory financing.
2. Investor discovers listing through Explore filters and detail review.
3. Investor sends request for a compliant amount.
4. Seeker evaluates request, reviews investor profile, and accepts with a verification message.
5. Agreement snapshot is generated and both sides review/sign.
6. Status becomes agreement active; both parties continue through chat.
7. Investor dashboard reflects the deal in active portfolio and projected outcomes.

---

## Business Value Delivered
- **For seekers:** structured fundraising workflow, clearer investor intake, and controlled request handling.
- **For investors:** discovery, due diligence context, lifecycle transparency, and portfolio visibility.
- **For both sides:** shared agreement process and communication continuity.


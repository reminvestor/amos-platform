# AMOS Platform - End-to-End User Test Guide

> **Purpose**: Walk through the complete user journey before mainnet launch.
> **Environment**: Development/Staging (not production)
> **Estimated Time**: 30-45 minutes

---

## Prerequisites

Before starting, ensure:
- [ ] Local development server is running (`bin/dev`)
- [ ] Database is seeded (`rails db:seed`)
- [ ] Redis is running
- [ ] Solana programs are deployed to devnet

---

## Test Flow Overview

```
┌─────────────────┐
│  1. SIGNUP      │
└────────┬────────┘
         │
┌────────▼────────┐
│  2. ONBOARDING  │
└────────┬────────┘
         │
┌────────▼────────┐
│  3. EXPLORE     │──────────────────┐
│     PLATFORM    │                  │
└────────┬────────┘                  │
         │                           │
    ┌────┴────┐                      │
    ▼         ▼                      ▼
┌───────┐ ┌───────┐           ┌───────────┐
│BOUNTY │ │REFER  │           │  USE AI   │
│ WORK  │ │FRIEND │           │  FEATURES │
└───┬───┘ └───┬───┘           └─────┬─────┘
    │         │                     │
    └────┬────┘                     │
         ▼                          ▼
┌─────────────────┐         ┌─────────────┐
│  4. EARN POINTS │         │ 5. PAY FOR  │
│     /TOKENS     │         │   SERVICES  │
└────────┬────────┘         └──────┬──────┘
         │                         │
         └───────────┬─────────────┘
                     ▼
         ┌───────────────────┐
         │  6. GOVERNANCE    │
         │     VOTING        │
         └───────────────────┘
```

---

## Phase 1: User Signup & Authentication

### Step 1.1: Create Account
**URL**: `http://localhost:3000/users/sign_up`

**Actions**:
1. Enter email address
2. Enter password (min 8 characters)
3. Click "Sign Up"

**Expected Results**:
- [ ] Account created successfully
- [ ] Redirected to onboarding or dashboard
- [ ] Confirmation email sent (check Mailhog at `localhost:8025` if running)

### Step 1.2: Email Verification (Optional)
**Actions**:
1. Check email inbox
2. Click verification link

**Expected Results**:
- [ ] Email marked as verified
- [ ] Can proceed with full platform access

---

## Phase 2: Onboarding & Entity Setup

### Step 2.1: Create Entity (Organization)
**URL**: After signup, follow onboarding flow

**Actions**:
1. Enter company/organization name
2. Select industry (optional)
3. Complete wizard steps

**Expected Results**:
- [ ] Entity created with your user as owner
- [ ] Default AI policies created automatically
- [ ] Dashboard becomes accessible

### Step 2.2: Check Default Policies
**URL**: `/entity/policies`

**Expected Results**:
- [ ] See default policies:
  - "Require confirmation for write operations"
  - "Daily API call limit"
  - etc.
- [ ] Can view policy details

---

## Phase 3: Explore Platform Features

### Step 3.1: Dashboard Overview
**URL**: `/dashboard`

**Expected Results**:
- [ ] See main dashboard with widgets
- [ ] Activity feed shows recent actions
- [ ] Navigation sidebar works

### Step 3.2: AI Chat (Scout)
**URL**: `/scout`

**Actions**:
1. Type a message: "Hello, what can you help me with?"
2. Wait for AI response
3. Try: "Create a simple task for me"

**Expected Results**:
- [ ] AI responds intelligently
- [ ] Chat history is preserved
- [ ] Can see thinking/reasoning (if enabled)

### Step 3.3: Contacts
**URL**: `/contacts`

**Actions**:
1. Click "Add Contact"
2. Fill in: Name, Email, Phone
3. Save

**Expected Results**:
- [ ] Contact created successfully
- [ ] Appears in contact list
- [ ] Can view contact details

### Step 3.4: Workflows
**URL**: `/entity/workflows`

**Actions**:
1. View existing workflow templates
2. Create a simple workflow (if available)

**Expected Results**:
- [ ] Can see workflow list
- [ ] Workflow editor loads
- [ ] Can save workflow

---

## Phase 4: Contribution & Earning

### Step 4.1: View Available Bounties
**URL**: `/bounties` (or `/entity/bounties`)

**Expected Results**:
- [ ] See list of available bounties
- [ ] Each shows: title, description, point value
- [ ] Can filter by category/status

### Step 4.2: Claim a Bounty
**Actions**:
1. Find a bounty you can complete
2. Click "Claim" or "Start Working"
3. Read the requirements

**Expected Results**:
- [ ] Bounty status changes to "In Progress"
- [ ] You're assigned as the worker
- [ ] Timer/deadline shown (if applicable)

### Step 4.3: Submit Bounty Work
**Actions**:
1. Complete the required work
2. Add work evidence (description, links, files)
3. Submit for review

**Expected Results**:
- [ ] Bounty status changes to "Pending Review"
- [ ] Work evidence is saved
- [ ] Notification sent to reviewer

### Step 4.4: Check Points/Token Balance
**URL**: `/wallet` or `/amos_wallet`

**Expected Results**:
- [ ] See current point balance
- [ ] See pending rewards
- [ ] Transaction history visible

---

## Phase 5: Referral System

### Step 5.1: Get Referral Link
**URL**: `/referrals` or dashboard

**Actions**:
1. Find "Invite Friends" or referral section
2. Copy your unique referral link

**Expected Results**:
- [ ] Unique referral link generated
- [ ] Can copy to clipboard
- [ ] Shows referral stats (sent, signed up, converted)

### Step 5.2: Track Referrals
**Actions**:
1. (Simulate) Have someone sign up with your link
2. Check referral dashboard

**Expected Results**:
- [ ] New signup appears in your referrals
- [ ] Points credited for signup
- [ ] Conversion tracking works

---

## Phase 6: Token Economy (Devnet)

### Step 6.1: Connect Solana Wallet
**URL**: `/wallet/connect` or within AMOS Wallet

**Actions**:
1. Click "Connect Wallet"
2. Select Phantom/Solflare (must be on Devnet)
3. Approve connection

**Expected Results**:
- [ ] Wallet connected successfully
- [ ] Wallet address displayed
- [ ] Shows devnet SOL balance

### Step 6.2: View AMOS Token Balance
**Expected Results**:
- [ ] AMOS token balance shown (may be 0 initially)
- [ ] Staked amount shown
- [ ] Revenue share eligibility displayed

### Step 6.3: Stake Tokens (if you have any)
**Actions**:
1. Click "Stake"
2. Enter amount
3. Confirm transaction

**Expected Results**:
- [ ] Transaction sent to Solana
- [ ] Stake recorded on-chain
- [ ] UI updates to show staked balance

---

## Phase 7: Transparency Dashboard

### Step 7.1: View Public Economics
**URL**: `/transparency`

**Expected Results**:
- [ ] Platform revenue displayed
- [ ] Cost breakdown visible
- [ ] Token holder payouts shown
- [ ] Decay rate displayed
- [ ] Token supply stats accurate

---

## Phase 8: Premium Features (Optional)

### Step 8.1: Select Premium AI Model
**URL**: `/scout`

**Actions**:
1. Click the brain icon in chat
2. Toggle "Premium Models" on
3. Select Claude Sonnet or Opus
4. Send a message

**Expected Results**:
- [ ] Model selection saved
- [ ] AI responds using premium model
- [ ] Billing/usage tracked (if enabled)

---

## Phase 9: Governance (Future)

### Step 9.1: View Proposals
**URL**: `/governance/proposals` (if implemented)

**Expected Results**:
- [ ] List of active proposals
- [ ] Your voting power shown
- [ ] Can view proposal details

### Step 9.2: Cast Vote
**Actions**:
1. Select a proposal
2. Choose Yes/No/Abstain
3. Sign with wallet

**Expected Results**:
- [ ] Vote recorded on-chain
- [ ] Vote count updates
- [ ] Cannot vote twice

---

## Test Checklist Summary

### Core Functionality
- [ ] User signup works
- [ ] Entity creation works
- [ ] Default policies created
- [ ] AI chat works
- [ ] Contacts CRUD works

### Token Economy
- [ ] Bounties visible
- [ ] Claiming works
- [ ] Point tracking works
- [ ] Wallet connection works
- [ ] Transparency dashboard loads

### Security
- [ ] Policies enforce restrictions
- [ ] Multi-tenant data isolation
- [ ] Authentication required for protected routes

---

## Known Issues / Notes

1. **Solana Devnet**: May be slow or rate-limited
2. **Email**: If not configured, check logs for OTP codes
3. **AI Responses**: May fail if API keys not set
4. **Premium Models**: Requires ANTHROPIC_API_KEY

---

## After Testing

If all tests pass:
1. ✅ Platform is ready for mainnet consideration
2. ✅ Document any issues found
3. ✅ Fix critical bugs before launch

**Next Steps**:
- [ ] Deploy to staging environment
- [ ] Run tests with real users (beta)
- [ ] Final security audit
- [ ] Mainnet token deployment

---

*Document created: February 2026*
*Version: 1.0*
